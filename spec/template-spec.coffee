describe 'template', ->
  {expand, CompileError, ExpandError} = require '../lib/template'

  it 'should leave objects with no macros or variables as is', ->
    expect(expand 'Hello world!')
      .toEqual 'Hello world!'

    expect(expand [greeting: 'Hello world!'])
      .toEqual [greeting: 'Hello world!']

  describe 'parsing', ->
    {nodeFromObject, nodeToObject, ParsePass} = require '../lib/template'

    parseCompileDump = (tmpl) ->
      nodeToObject new ParsePass().visit nodeFromObject tmpl

    testObjects = [
      'Hello world!'

      {greeting: 'Hello world!'}

      [greeting: 'Hello world!']

      {foo: (bar) -> baz}

      [[[{string: 'Hello', number: 42, answer: yes}]]]
    ]

    it 'should keep reverse relation between nodeToObject/nodeFromObject', ->
      for object in testObjects
        expect(parseCompileDump object).toEqual object

    it 'should parse/dump ${variable} references properly', ->
      expect(parseCompileDump '${hello}').toEqual '${hello}'
      expect(parseCompileDump '$hello').toEqual '${hello}'

    it 'should parse/dump objects with special directives properly', ->
      expect(parseCompileDump {'$': 'Hello'}).toEqual 'Hello'
      expect(parseCompileDump {'$': 'Hello', '$%': {}}).toEqual 'Hello'

      expect(parseCompileDump {
          '$%var': 'value'
          '$': 'Hello'
        }).toEqual {
          '$%':
            var: 'value'
          '$': 'Hello'
        }

    it "should forbid mixing '$' key with regular keys", ->
      expect(-> parseCompileDump {
          '$': 'Hello'
          foo: 'bar'
        }).toThrowError CompileError, /mixed/i

    it 'should forbid duplicate variable definitions', ->
      expect(-> parseCompileDump {
          '$%var': 'value'
          '$%':
            var: 'value'
          '$': 'Hello'
        }).toThrowError CompileError, /duplicate/i

    it 'should parse nested variable scopes', ->
      expect(parseCompileDump {
          '$%var': 'value'
          '$%varWithOwnScope':
            '$%':
              auxVar: 'helper'
            hello: 'World'
          '$': 'Hello'
        }).toEqual {
          '$%':
            var: 'value'
            varWithOwnScope:
              '$%':
                auxVar: 'helper'
              hello: 'World'
          '$': 'Hello'
        }

    it "should recognize '$!' object assign directive", ->
      expect(parseCompileDump obj = {
          '$%':
            var: 'value'
          '$!':
            foo: 'bar'
          '$': 'Hello'
        }).toEqual obj

  describe 'variable scopes', ->
    it 'should expand variables recursively', ->
      expect(expand 'Hello $world!', Object.create {foo: 'bar'},
          world: {get: -> "#{@foo}f"})
        .toEqual 'Hello barf!'

    it 'inner variables should shadow outer ones', ->
      expect(expand {
          '$%':
            foo: 'dead$bzz'
            bzz: 'bee'
          '$': 'Hello $world!'
        }, Object.create {foo: 'bar'}, world: {get: -> "#{@foo}f"})
        .toEqual 'Hello deadbeef!'

  describe 'string ${expansions}', ->
    it 'should expand simple variable references', ->
      expect(expand 'Hello $world!', world: 'there')
        .toEqual 'Hello there!'

      expect(expand [greeting: 'Hello ${world}!'], world: 'everyone')
        .toEqual [greeting: 'Hello everyone!']

    it 'should fail to produce an object with conflicting keys', ->
      expect(-> expand {
          foo: 'bar'
          '$foo': 'baz'
        }, foo: 'foo').toThrowError ExpandError, /duplicate/i

  describe 'extending objects with $!', ->
    it 'should assign properties from source object', ->
      expect(expand {
          foo: 'bar'
          '$!':
            bar: 'baz'
        }).toEqual foo: 'bar', bar: 'baz'

    it 'should fail to copy conflicting properties', ->
      expect(-> expand {
          foo: 'bar'
          '$!':
            foo: 'baz'
        }).toThrowError ExpandError, /already has/i
