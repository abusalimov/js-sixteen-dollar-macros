describe 'template', ->
  {expand, CompileError} = require '../lib/template'

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
