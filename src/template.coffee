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
{checkIt, allProperties, truncateLeft} = require './util'


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

  constructor: (children) ->
    super children[@constructor.wrappedFieldName].object, children

  @wrap: (node, children) ->
    wrappedChild = {"#{@wrappedFieldName}": node}
    new this _.extend wrappedChild, children


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


class ThisNode extends LeafNode


class PropertyNode extends WrapperNode
  @defineChildrenFields [
    {target: 'node'}
    {name: 'node'}
  ]
  @wrappedFieldName = 'target'


class CallNode extends WrapperNode
  @wrappedFieldName = 'target'


class FunctionCallNode extends CallNode
  @defineChildrenFields [
    {target: 'node'}
    {args: 'sequence'}
  ]


class MethodCallNode extends CallNode
  @defineChildrenFields [
    {target: 'node'}
    {name: 'node'}
    {args: 'sequence'}
  ]


class DefaultValueNode extends WrapperNode
  @defineChildrenFields [
    {target: 'node'}
    {fallback: 'node'}
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


class NodeTranslator extends NodeVisitor
  genericVisit: (node) ->
    throw new CompileError "Unknown node type '#{node.constructor.name}'"


class NodeToObject extends NodeTranslator

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
  visitStringNode: ({object: str}, inExpr) ->
    str = str.replace '$', (char) -> "$#{char}"
    if inExpr?
      str = str.replace /[\\{}().:]/g, (char) -> "\\#{char}"
    str

  wrap = (inExpr, trailer, ret) ->
    unless trailer?
      "${#{ret}}"
    else
      "#{ret}#{trailer or ''}"

  visitThisNode: ({}, inExpr, trailer) ->
    unless trailer? then '${@}' else ''

  visitPropertyNode: ({target, name}, inExpr, trailer) ->
    wrap inExpr, trailer,
      "#{@visit target, yes, '.'}#{@visit name, yes}"

  argStr: (args, inExpr) ->
    if args.length > 1
      throw new Error "Not implemented yet"
    if arg = args[0] then @visit arg, inExpr else '${}'

  visitMethodCallNode: ({target, name, args}, inExpr, trailer) ->
    wrap inExpr, trailer,
      "#{@visit target, yes, '.'}#{@visit name, yes}(#{@argStr args, yes})"

  visitFunctionCallNode: ({target, args}, inExpr, trailer) ->
    wrap inExpr, trailer,
      "(#{@visit target, yes, ''})(#{@argStr args, yes})"

  visitDefaultValueNode: ({target, fallback}, inExpr, trailer) ->
    wrap inExpr, trailer,
      "#{@visit target, yes, ':'}#{@visit fallback, yes}"

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

    parseCallTo = (name, arg) =>
      ret = @parseString "${#{name}()}"
      unless ret instanceof CallNode
        throw @error "Invalid name to call: '#{name}'
                      (parsed as a #{ret.constructor.name} object)"
      ret.args = if arg instanceof ArrayNode then arg.sequence else [arg]
      ret

    node = @genericVisit node,
      defineVariables: (scopeMapping) =>
        for name, {value} of scopeMapping
          if name of variables
            throw @error "Duplicate variable definition: '#{name}'"

          variables[name] = @visit value
        return

      defineExpansion: (value, funcName) =>
        if dollarNode?
          throw @error "Multiple '$:' expansions in a single object"
        dollarNode = @visit value
        if funcName
          dollarNode = parseCallTo funcName, dollarNode

      defineAssignment: (value, funcName) =>
        if assignNode?
          throw @error "Multiple '$!:' directives in a single object"
        assignNode = @visit value
        if funcName
          throw @error "Not implemented yet"

    if dollarNode?
      unless _.isEmpty node.mapping
        throw @error "Mixed '$:' expansion and regular object keys"
      node = dollarNode

    if assignNode?
      node = new AssignNode {target: node, assign: assignNode}

    unless _.isEmpty variables
      node = new ScopeNode {node, variables}

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

  parseString: (str) ->
    # A stateful RegExp instance, which is passed to @parseStringInternal,
    # is shared across all recursive calls.
    @parseStringInternal(str, ///
        \$ (\$)  |  # 1: escaped
        \$ (\w+) |  # 2: name
        \$ (\{)  |  # 3: expand

        (\\)? (?: \\ |  # 4: opEscape
          ([{}().:]) )  # 5: op
      ///g) ? new StringNode ''

  matchingOp =
    '(': ')'
    '{': '}'

  parseStringInternal: (str, re, {prefix, closing, inExpr} = {}) ->
    # Parse an ${expansion} expression, or produce a joined string
    start = re.lastIndex

    prefix ?= ''
    target = new ThisNode if inExpr

    tokens = new TokenBuffer str, start
    lastEnd = start
    while match = re.exec str
      {
        index: matchStart
        1: escaped
        2: simpleName
        3: expand
        4: opEscape
        5: op
      } = match

      unless closing? or inExpr
        continue if op  # an ordinal char here

      else if opEscape
        escaped = op ? '\\'
        op = null
      else
        opOpen  = if op in '{(' then op
        opClose = if op in ')}' then op
        opDelim = if op in '.:' then op

      tokens.pushSubstring lastEnd, matchStart, trim: inExpr

      switch
        when simpleName
          tokens.push new PropertyNode
            target: new ThisNode
            name: new StringNode simpleName

        when expand  # is '}'
          tok = @parseStringInternal str, re,
            prefix: "#{prefix}${"
            closing: '}'
            inExpr: yes
          tokens.push tok ? new StringNode ''

        when op and not inExpr  # i.e. inside a call argument
          unless opClose
            tokens.pushString op
          if opOpen
            tok = @parseStringInternal str, re,
              prefix: "#{prefix}#{op}"
              closing: matchingOp[op]
              inExpr: no
            if tok?
              tokens.pushFlat tok
            tokens.pushString matchingOp[op]

        when op and inExpr
          name = tokens.flush(matchStart)
          if name? and lastOp is '('
            throw @error "Unexpected tokens: '(...)#{name.object}'"
          if not name? and lastOp is '.'
            throw @error "Expected a property name after period: '.#{op}'"
          retTarget = target if name?

          if opDelim and not retTarget?
            throw @error "Expected a target expression preceding: '#{op}'"

          retTarget = target =
            if opOpen
              if op is '{'
                throw @error "Unexpected open '{' in expression"

              content = @parseStringInternal str, re,
                prefix: "#{prefix}#{name?.object}#{op}"
                closing: matchingOp[op]
                inExpr: not retTarget?  # i.e. not a call argument

              unless retTarget?
                unless content?
                  errExpr = str.substring matchStart, re.lastIndex
                  throw @error "Empty parens expression: '#{errExpr}'"
                content
              else
                args = if content? then [content] else []
                if name?
                  new MethodCallNode {target, name, args}
                else
                  new FunctionCallNode {target, args}

            else  # opDelim or opClose
              if name? and not (name instanceof StringNode and
                                name.object is '@')
                new PropertyNode {target, name}
              else
                retTarget

          if op is ':'
            fallback = @parseStringInternal str, re,
              prefix: "#{prefix}#{name?.object}#{op}"
              closing: closing
              inExpr: no
            op = opClose = closing  # cheat to break and return

            retTarget = target = new DefaultValueNode {target, fallback}

      lastEnd = re.lastIndex - escaped? # to grab an escaped char later on

      if opClose
        break
      lastOp = op if op

    unless closing? or inExpr
      tokens.pushSubstring lastEnd

    else if op isnt closing
      throw @error "Expected closing '#{closing}':
                    '#{truncateLeft prefix, length: 16}\
                     #{str.substring start, lastEnd}'"
    return retTarget if inExpr

    tokens.flush()

  class TokenBuffer extends Array
    constructor: (@str, @start) ->
      super

    flush: (newStart) ->
      ret =
        if @length is 1
          # This allows returning a value of any type (without coercing it
          # to a string) in case if the whole string consists of the sole
          # expansion: '${var}'
          this[0]
        else if @length > 1
          s = @str.substring @start, newStart
          new StringJoinNode array: new ArrayNode s, sequence: this[...]

      if newStart?
        @start = newStart

      @length = 0
      ret

    pushFlat: (node) ->
      if node instanceof StringJoinNode
        for n in node.array.sequence
          @pushFlat n
        return
      last = this[@length - 1]
      if last instanceof StringNode and node instanceof StringNode
        last.object += node.object
      else
        @push node

    pushString: (s, {trim, force} = {}) ->
      if trim
        s = s.trim()
      if s or force
        @pushFlat new StringNode s

    pushSubstring: (start, end, {trim} = {}) ->
      @pushString @str.substring(start, end), {trim}

  error: (msg) ->
    new ParseError msg


class AssemblePass extends NodeTranslator

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

  visitThisNode: ->
    property get: -> this

  visitPropertyNode: ({target, name}) ->
    targetDescriptor = @fieldVisit.node target
    nameDescriptor = @fieldVisit.node name

    property get: ->
      targetExpansion = targetDescriptor.apply this
      nameExpansion = nameDescriptor.apply this

      targetExpansion[nameExpansion]

  visitMethodCallNode: ({target, name, args}) ->
    targetDescriptor = @fieldVisit.node target
    nameDescriptor = @fieldVisit.node name
    argsDescriptor = @assembleArray args

    property get: ->
      targetExpansion = targetDescriptor.apply this
      argsExpansion = argsDescriptor.apply this
      nameExpansion = nameDescriptor.apply this

      targetExpansion[nameExpansion].apply targetExpansion, argsExpansion

  visitFunctionCallNode: ({target, args}) ->
    targetDescriptor = @fieldVisit.node target
    argsDescriptor = @assembleArray args

    property get: ->
      targetExpansion = targetDescriptor.apply this
      argsExpansion = argsDescriptor.apply this

      targetExpansion.apply targetExpansion, argsExpansion

  visitDefaultValueNode: ({target, fallback}) ->
    targetDescriptor = @fieldVisit.node target
    fallbackDescriptor = @fieldVisit.node fallback

    property get: ->
      targetExpansion = targetDescriptor.apply this
      targetExpansion ? fallbackDescriptor.apply this

  visitStringJoinNode: ({array, object}) ->
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
    @assembleArray sequence

  assembleArray: (sequence) ->
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

  class ScopeBase
    @:: = Object.create null
    @::constructor = this
    constructor: (@__compiler) ->

  class @Scope extends ScopeBase
    _: _

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

    __include: (filename) ->
      filename = path.resolve @__dirname, filename
      @__compiler.evalFile filename, this

    include: ->
      @__include arguments...

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
class ParseError extends CompileError
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

  ThisNode
  PropertyNode
  CallNode
  FunctionCallNode
  MethodCallNode
  DefaultValueNode
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
  ParseError
  ExpandError
}
