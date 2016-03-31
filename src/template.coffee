require('source-map-support').install()

path = require 'path'
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

loader = require './load'
{checkIt, allProperties} = require './util'


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


class ExpandNode extends WrapperNode


class VariableExpandNode extends ExpandNode
  @defineChildrenFields {name: 'node'}
  @wrappedFieldName = 'name'


class PropertyGetNode extends ExpandNode
  @defineChildrenFields [
    {target: 'node'}
    {name: 'node'}
  ]
  @wrappedFieldName = 'target'


class CallNode extends ExpandNode
  @defineChildrenFields [
    {target: 'node'}
    {args: 'node'}
  ]
  @wrappedFieldName = 'target'


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

  visitVariableExpandNode: ({name}, prop) ->
    ret = @visit name
    unless prop?
      ret = "${#{ret}}"
    ret

  visitPropertyGetNode: ({target, name}, prop) ->
    ret = "#{@visit target, yes}.#{@visit name}"
    unless prop?
      ret = "${#{ret}}"
    ret

  visitCallNode: ({target, args}) ->
    funcName = @visit target, yes

    {"$:#{funcName}": @visit args}

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

    parseCallName = (name) =>
      ret = @parseString "${#{name}}"
      unless ret instanceof ExpandNode
        throw new CompileError "Invalid name to call: '${name}'"
      ret

    node = @genericVisit node,
      defineVariables: (scopeMapping) =>
        for name, {value} of scopeMapping
          if name of variables
            throw new CompileError "Duplicate variable definition: '#{name}'"

          variables[name] = @visit value
        return

      defineExpansion: (value, funcName) =>
        if dollarNode?
          throw new CompileError "Multiple '$:' expansions in a single object"
        dollarNode = @visit value
        if funcName
          dollarNode = CallNode.wrap parseCallName(funcName), args: dollarNode

      defineAssignment: (value, funcName) =>
        if assignNode?
          throw new CompileError "Multiple '$!:' directives in a single object"
        assignNode = @visit value
        if funcName
          throw new CompileError "Not implemented yet"

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
    [all, dollar, directive, name] = /^(\$([%!:])?)?(.+)??$/.exec key.object

    switch
      when directive is '%'  # $%...: ...
        actions.defineVariables \
          if name  # $%name: ...
            {"#{name}": node}
          else  # $%: ...
            Node.checkType(value, ObjectNode).mapping

      when directive is '!'  # $!...: ...
        actions.defineAssignment value, name

      when directive is ':'  # $:...: ...
        actions.defineExpansion value, name

      when dollar and not name  # $: ...
        actions.defineExpansion value

      else
        return @genericVisit node

    return  # skip special directive nodes

  visitStringNode: ({object: str}) ->
    @parseString str

  parseString: (str, re) ->
    unless isExpansion = re?
      # The outermost call that produced the resulting string (whereas inner
      # calls are used to compute names of variables to expand).
      # Create a RegExp instance, which is shared across all recursive calls.
      re = /\$(?:([$.}])|(\w+)|(\{))|(\.)|(\})/g

    tokens = []
    tokens.flush = ->
      ret =
        if @length is 1
          # This allows returning a value of any type (without coercing it
          # to a string) in case if the whole string consists of the sole
          # expansion: '${var}'
          this[0]
        else
          StringJoinNode.wrap new ArrayNode null, sequence: this[...]

      @length = 0
      ret

    tokens.pushString = (s) ->
      if s
        last = this[@length - 1]
        if last instanceof StringNode
          last.object += s
        else
          @push new StringNode s

    lastEnd = start = re.lastIndex
    while match = re.exec str
      {
        index: matchStart
        1: escaped
        2: name
        3: lBrace
        4: prop
        5: rBrace
      } = match

      unless isExpansion
        continue if prop or rBrace  # ordinal chars

      tokens.pushString str.substring lastEnd, matchStart

      switch
        when name
          tokens.push VariableExpandNode.wrap new StringNode name

        when lBrace
          tokens.push @parseString str, re  # re object is stateful

        when prop or rBrace
          nameNode = tokens.flush()
          retNode =
            unless retNode?
              VariableExpandNode.wrap nameNode
            else
              PropertyGetNode.wrap retNode, name: nameNode

          if rBrace
            return retNode

      lastEnd = re.lastIndex - escaped?  # to grab an escaped char later on

    if isExpansion  # should have exited upon reaching the closing rBrace
      throw new CompileError "Unterminated variable expansion
                              '${#{str.substring start}'"

    tokens.pushString str.substring lastEnd
    tokens.flush()


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

  visitPropertyGetNode: ({target, name}) ->
    targetDescriptor = @fieldVisit.node target
    nameDescriptor = @fieldVisit.node name

    property get: ->
      targetExpansion = targetDescriptor.apply this
      nameExpansion = nameDescriptor.apply this

      targetExpansion[nameExpansion]

  visitCallNode: ({target, args}) ->
    unless args instanceof ArrayNode
      args = new ArrayNode args.object, sequence: [args]

    targetDescriptor = @fieldVisit.node target
    argsDescriptor = @fieldVisit.node args

    property get: ->
      targetExpansion = targetDescriptor.apply this
      argsExpansion = argsDescriptor.apply this

      targetExpansion.apply this, argsExpansion

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

  genericVisit: (node) ->
    throw new CompileError "Unknown node type '#{node.constructor.name}'"


class CompilerBase

  class @Scope
    @:: = Object.create null
    @::constructor = this
    constructor: (@__compiler) ->

  constructor: ->
    @rootScope = new @constructor.Scope this

    @parsePass = new ParsePass
    @assemblePass = new AssemblePass

  createScope: (variables, parentScope = @rootScope) ->
    Object.create parentScope, allProperties variables

  compile: (template) ->
    node = nodeFromObject template
    preprocessedNode = @parsePass.visit node
    @assemblePass.visit preprocessedNode

  eval: (template, variables, parentScope = @rootScope) ->
    nodeDescriptor = @compile template
    nodeDescriptor.apply @createScope variables, parentScope


class Compiler extends CompilerBase

  class @Scope extends @Scope
    __dirname: '.'

    include: (filename) ->
      filename = path.resolve @__dirname, filename
      @__compiler.evalFile filename, this

  constructor: (@options = {}) ->
    super
    @rootScope.__dirname = @options.dirname if @options.dirname?
    @fileCache = {}

  createFileScope: (filename, variables, parentScope = @rootScope) ->
    __filename = path.resolve filename
    __dirname = path.dirname __filename

    @createScope _.defaults({__filename, __dirname}, variables), parentScope

  loadFile: (filename) ->
    filename = path.resolve filename
    @fileCache[filename] ?= loader.loadFile filename, @options

  compileFile: (filename) ->
    template = @loadFile filename
    @compile template

  evalFile: (filename, variables, parentScope = @rootScope) ->
    nodeDescriptor = @compileFile filename
    nodeDescriptor.apply @createFileScope filename, variables, parentScope


expand = (template, variables, options) ->
  new Compiler(options).eval template, variables

expandFile = (filename, variables, options) ->
  new Compiler(options).evalFile filename, variables


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
  PropertyGetNode
  StringJoinNode

  nodeFromObject
  nodeToObject

  ParsePass
  AssemblePass

  Compiler

  expand
  expandFile

  TemplateError
  CompileError
  ExpandError
}
