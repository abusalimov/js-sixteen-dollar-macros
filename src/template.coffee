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
  visitStringNode: ({object}) -> object
  visitPrimitiveNode: ({object}) -> object

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


expand = (tmpl) ->
  tmpl  # stub!


class TemplateError extends NodeVisitorError
class CompileError extends TemplateError


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

  nodeFromObject
  nodeToObject

  ParsePass

  expand

  TemplateError
  CompileError
}
