require('source-map-support').install()

{
  isPlainObject
  isArray
  isFunction
  isString
} = _ = require 'lodash'

{
  Node

  NodeVisitor
  NodeTransformer

  NodeError
  NodeVisitorError
} = require './node'

{checkIt} = require './util'


class LeafNode extends Node
class FunctionNode extends LeafNode
class StringNode extends LeafNode
class PrimitiveNode extends LeafNode

class ArrayNode extends Node
  @defineChildrenFields {'sequence'}

class ObjectNode extends Node
  @defineChildrenFields {'mapping'}

class KeyValueNode extends Node
  @defineChildrenFields [
    {key: 'node'}
    {value: 'node'}
  ]


class WrapperNode extends Node
  @wrappedFieldName = 'node'

  @wrap: (node, children) ->
    wrappedChild = {"#{@wrappedFieldName}": node}
    new this node.object, _.extend wrappedChild, children


class ScopeNode extends WrapperNode
  @defineChildrenFields [
    {node: 'node'}
    {variables: 'mapping'}
  ]


class AssignNode extends WrapperNode
  @defineChildrenFields [
    {target: 'node'}
    {assign: 'node'}
  ]
  @wrappedFieldName = 'target'


class VariableExpandNode extends WrapperNode
  @defineChildrenFields {name: 'node'}
  @wrappedFieldName = 'name'


class StringJoinNode extends WrapperNode
  @defineChildrenFields {array: 'node'}
  @wrappedFieldName = 'array'


nodeFromObject = (object) ->
  switch
    when isPlainObject object
      mapping = _.mapValues object, (value, key) ->
          new KeyValueNode value, {
            key: nodeFromObject(key)
            value: nodeFromObject(value)
          }
      new ObjectNode object, {mapping}

    when isArray object
      new ArrayNode object, {sequence: _.map object, nodeFromObject}

    when isFunction object then new FunctionNode object
    when isString object   then new StringNode object
    else new PrimitiveNode object


nodeToObject = (node) ->
  new NodeToObject().visit node


class NodeToObject extends NodeVisitor

  visitScopeNode: ({node, variables}) ->
    unless isPlainObject object = @visit node
      object = {'$': object}

    _.extend {'$%': _.mapValues variables, (value) => @visit value}, object

  visitAssignNode: ({target, assign}) ->
    unless isPlainObject object = @visit target
      object = {'$': object}

    _.extend {'$!': @visit assign}, object

  visitFunctionNode: ({object}) -> object
  visitPrimitiveNode: ({object}) -> object
  visitStringNode: ({object: str}) ->
    str.replace /[$.}]/g, (char) -> "$#{char}"

  visitVariableExpandNode: ({name}) ->
    "${#{@visit name}}"

  visitStringJoinNode: ({array}) ->
    @visit(array).join ''

  visitArrayNode: ({sequence}) ->
    _.map sequence, (item) => @visit item

  visitObjectNode: ({mapping}) ->
    _.mapValues mapping, (keyValue) => @visit keyValue

  visitKeyValueNode: ({value}) -> @visit value


class ParsePass extends NodeTransformer

  visitObjectNode: (node) ->
    variables = {}
    dollarNode = null
    assignNode = null

    node = @genericVisit node,
      defineVariables: (scopeMapping) =>
        for name, {value} of scopeMapping
          if name of variables
            throw new CompileError "Duplicate variable definition: '#{name}'"

          variables[name] = @visit value
        return

      defineExpansion: (value) =>
        if dollarNode?
          throw new CompileError "Multiple '$:' expansions in a single object"
        dollarNode = @visit value

      defineAssignment: (value) =>
        if assignNode?
          throw new CompileError "Multiple '$!:' directives in a single object"
        assignNode = @visit value

    if dollarNode?
      unless _.isEmpty node.mapping
        throw new CompileError "Mixed '$:' expansion and regular object keys"
      node = dollarNode

    if assignNode?
      node = AssignNode.wrap node, {assign: assignNode}

    unless _.isEmpty variables
      node = ScopeNode.wrap node, {variables}

    node

  visitKeyValueNode: (node, actions) ->
    {key, value} = node
    [all, dollar, directive, name] = /^(\$([%!])?)?(.*)$/.exec key.object

    switch
      when directive is '%'  # $%...: ...
        actions.defineVariables \
          if name  # $%name: ...
            {"#{name}": node}
          else  # $%: ...
            Node.checkType(value, ObjectNode).mapping
        return

      when directive is '!' and not name  # $!: ...
        actions.defineAssignment value
        return

      when dollar and not name  # $: ...
        actions.defineExpansion value
        return

      else
        @genericVisit node

  visitStringNode: ({object: str}) ->
    re = /\$(?:(\$)|\{(\w+)\}|(\w+))/g

    tokens = []

    lastEnd = 0
    while match = re.exec str
      escaped = match[1]
      name = match[2] ? match[3]
      matchStart = match.index

      if s = str.substring lastEnd, matchStart
        tokens.push new StringNode s
      if name
        tokens.push new VariableExpandNode name, name: new StringNode name

      lastEnd = re.lastIndex - escaped?  # to grab an escaped char later on

    if s = str.substring lastEnd
      tokens.push new StringNode s

    if tokens.length is 1
      # This allows returning a value of any type (without coercing it
      # to a string) in case if the whole string consists of the sole
      # expansion: '${var}'
      tokens[0]
    else
      StringJoinNode.wrap new ArrayNode null, sequence: tokens


class AssemblePass extends NodeVisitor

  class PropertyDescriptor
    @:: = Object.create null
    enumerable: yes

  class AccessorDescriptor
    constructor: (@get) ->
    apply: (obj, args) ->
      @get.apply obj, args
    call: (obj, args...) ->
      @apply obj, args

  class DataDescriptor
    constructor: (@value) ->
    apply: -> @value
    call: -> @value

  property = (options) ->
    switch
      when options.get?
        new AccessorDescriptor options.get
      when 'value' of options
        new DataDescriptor options.value
      else
        throw new TypeError "Must provide 'value' or 'get' key"

  visitFunctionNode: ({object: func}) ->
    property value: func

  visitPrimitiveNode: ({object: value}) ->
    property value: value

  visitStringNode: ({object: str}) ->
    property value: str

  visitVariableExpandNode: ({name}) ->
    {value, get} = @fieldVisit.node name

    if get?
      property get: -> @[get.apply this]
    else  # probably a hot path
      property get: -> @[value]

  visitStringJoinNode: ({array}) ->
    tokenArrayDescriptor = @fieldVisit.node array
    property get: ->
      tokenArrayExpansion = tokenArrayDescriptor.apply this
      tokenArrayExpansion.join ''

  visitAssignNode: ({target, assign}) ->
    targetDescriptor = @fieldVisit.node target
    assignDescriptor = @fieldVisit.node assign

    property get: ->
      targetExpansion = targetDescriptor.apply this
      assignExpansion = assignDescriptor.apply this

      for value in _.flattenDeep [assignExpansion]
        checkIt isPlainObject: value, 'applied value'
        _.extendWith targetExpansion, value, (objValue, srcValue, key) ->
          unless objValue is undefined
            throw new ExpandError "Destination object already has '#{key}'
                                   property: '#{objValue}'
                                   (attempt to set to '#{srcValue}')"
          srcValue

      targetExpansion


  visitArrayNode: ({sequence}) ->
    itemDescriptorList = @fieldVisit.sequence sequence

    property get: ->
      for itemDescriptor in itemDescriptorList
        itemDescriptor.apply this

  visitObjectNode: ({mapping}) ->
    keyValueDescriptorEntryMap = @fieldVisit.mapping mapping

    property get: ->
      result = {}
      origKeys = {}

      for key, entry of keyValueDescriptorEntryMap
        {key: keyDescriptor, value: valueDescriptor} = entry

        keyExpansion = keyDescriptor.apply this

        checkIt isString: keyExpansion, 'object key'
        if (origKey = origKeys[keyExpansion])?
          throw new ExpandError "Duplicate object key '#{keyExpansion}'
                                 as a result of expanding
                                 both '#{origKey}' and '#{key}'"
        else
          origKeys[keyExpansion] = key

        result[keyExpansion] = valueDescriptor.apply this

      result

  visitKeyValueNode: ({key, value}) ->
    @fieldVisit.mapping {key, value}

  visitScopeNode: ({node, variables}) ->
    nodeDescriptor = @fieldVisit.node node
    variableDescriptorMap = @fieldVisit.mapping variables

    property get: ->
      # Leverage the power of native JS prototype inheritance to make inner
      # scope variables shadow the outer ones.
      scope = Object.create this, variableDescriptorMap
      nodeDescriptor.apply scope


class Compiler
  constructor: ->
    @parsePass = new ParsePass
    @assemblePass = new AssemblePass

  compile: (template) ->
    node = nodeFromObject template
    preprocessedNode = @parsePass.visit node
    nodeDescriptor = @assemblePass.visit preprocessedNode
    (scope = Object.create null) ->
      nodeDescriptor.apply scope


compile = (template) ->
  new Compiler().compile template


expand = (template, variables) ->
  func = compile template
  func variables


class TemplateError extends NodeVisitorError
class CompileError extends TemplateError
class ExpandError extends TemplateError


module.exports = {
  Node

  LeafNode
  FunctionNode
  StringNode
  PrimitiveNode

  ArrayNode
  ObjectNode
  KeyValueNode

  WrapperNode
  ScopeNode
  AssignNode
  VariableExpandNode
  StringJoinNode

  nodeFromObject
  nodeToObject

  ParsePass
  AssemblePass

  Compiler
  compile

  expand

  TemplateError
  CompileError
  ExpandError
}
