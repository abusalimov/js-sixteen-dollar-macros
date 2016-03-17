{inspect, format} = require 'util'
_ = require 'lodash'


checkIt = (options, prefix, msg) ->
  values = for predicateName, value of options
    unless _[predicateName] value
      throwTypeError value, predicateName.replace(/^is/, ''), prefix, msg
    value

  if values.length is 1
    values[0]


checkType = (value, type, prefix, msg) ->
  unless value instanceof type
    throwTypeError value, type.constructor?.name ? type, prefix, msg
  value


throwTypeError = (value, typeName, prefix, msg) ->
  unless msg?
    msg = "Expected #{typeName}"
  if prefix
    msg = "#{prefix}: #{msg}"
  throw new TypeError "#{msg}, got #{typeof value} instead:
                       #{inspect value, customInspect: off}"


# Workaround for jashkenas/coffeescript#2359-related oddities
# ("default constructor for subclasses of native objects")
class BaseError extends Error
  constructor: (@message) ->
    super @message
    @name = @constructor.name


module.exports = {
  inspect
  format

  checkIt
  checkType
  throwTypeError

  BaseError
}
