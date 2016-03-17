{isArray, isPlainObject} = _ = require 'lodash'

{checkIt, checkType, BaseError} = require './util'


# The base for all node classes.
class Node
  childrenFields: []

  constructor: (@object, children) ->
    for {name, kind} in @childrenFields
      unless name of children
        throw new TypeError "Missing required child property: '#{name}'"
      @[name] = @constructor.checkNodeField[kind] children[name]

  @defineChildrenField: (name, kind) ->
    unless @::hasOwnProperty 'childrenFields'
      @::childrenFields = []
      @::childrenFieldsByName = {}

    @::childrenFields.push field = {name, kind}
    @::childrenFieldsByName[name] = field

  @defineChildrenFields: (nameKindList) ->
    if isPlainObject nameKindList
      nameKindList = [nameKindList]

    for nameKind in nameKindList
      for name, kind of nameKind
        @defineChildrenField name, kind

  @checkNodeField:
    mapping: (value) -> checkIt isPlainObject: value
    sequence: (value) -> checkIt isArray: value
    node: (value) -> Node.checkType value

  # Helper method to check a given object is a Node instance.
  @checkType = (node, type = Node) ->
    checkType node, type


# An auxiliary class that prepares a @fieldVisit member - an instance of
# a @FieldVisitor inner class. NodeVisitor and its subclasses provide proper
# @FieldVisitor implementation as well.
class NodeVisitorBase

  class @FieldVisitor
    constructor: (@visitor) ->

  constructor: (fieldVisitorClass = @constructor.FieldVisitor) ->
    @fieldVisit = new fieldVisitorClass this


# A node visitor base class that walks a tree under a given node and calls a
# visitor function for every node found. This function may return a value
# which is forwarded by the `visit()` method.
#
# This class is meant to be subclassed, with the subclass adding visitor
# methods.
class NodeVisitor extends NodeVisitorBase

  # Visit a node. The default implementation calls the method called
  # `visitClassName()` where `ClassName` is the name of the node class, or
  # `genericVisit()` if that method doesn't exist.
  visit: (node, args...) ->
    Node.checkType node

    methodName = "visit#{node.constructor.name}"
    unless @[methodName]?
      methodName = 'genericVisit'

    @[methodName] node, args...

  class @FieldVisitor extends @FieldVisitor

    mapping: (mapping, args...) ->
      _.mapValues mapping, (child) =>
        @visitor.visit child, args...

    sequence: (sequence, args...) ->
      for child in sequence
        @visitor.visit child, args...

    node: (node, args...) ->
      if node?
        @visitor.visit node, args...

  # Call `visit()` on all children of the node.
  genericVisit: (node, args...) ->
    for {name, kind} in Node.checkType(node).childrenFields
      @fieldVisit[kind] node[name], args...

    node


# A NodeVisitor subclass that walks a tree under a given node and allows
# modification of nodes.
#
# The NodeTransformer will walk the tree and use the return value of the
# visitor methods to replace or remove the old node.
class NodeTransformer extends NodeVisitor

  class @FieldVisitor extends @FieldVisitor

    mapping: (oldMapping, args...) ->
      newMapping = {}

      for k, child of oldMapping
        newChild = @visitor.visit child, args...
        continue unless newChild?

        unless isPlainObject newChild
          newChild = {"#{k}": newChild}
        for eachKey, eachNewChild of newChild
          if eachKey of newMapping
            throw new NodeVisitorError "Duplicate child key '#{eachKey}'"
          newMapping[eachKey] = Node.checkType eachNewChild

      newMapping

    sequence: (oldSequence, args...) ->
      newSequence = []

      for child in oldSequence
        newChild = @visitor.visit child, args...
        continue unless newChild?

        unless isArray newChild
          newChild = [newChild]
        for eachNewChild in newChild
          newSequence.push Node.checkType eachNewChild

      newSequence

    node: (oldNode, args...) ->
      if oldNode?
        newNode = @visitor.visit oldNode, args...
        if newNode?
          Node.checkType newNode

  genericVisit: (node, args...) ->
    for {name, kind} in Node.checkType(node).childrenFields
      node[name] = @fieldVisit[kind] node[name], args...

    node


class NodeError extends BaseError
class NodeVisitorError extends NodeError


module.exports = {
  Node

  NodeVisitor
  NodeTransformer

  NodeError
  NodeVisitorError
}
