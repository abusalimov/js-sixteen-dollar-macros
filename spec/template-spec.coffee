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
      expect(parseCompileDump '$$hello').toEqual '$$hello'
      expect(parseCompileDump '${$hello}').toEqual '${${hello}}'
      expect(parseCompileDump '${hello.length}').toEqual '${hello.length}'
      expect(parseCompileDump '${hello.$prop}').toEqual '${hello.${prop}}'
      expect(parseCompileDump '${@}').toEqual '${@}'
      expect(parseCompileDump '${func(arg)}').toEqual '${func(arg)}'
      expect(parseCompileDump '${(func)(arg)}').toEqual '${(func)(arg)}'
      expect(parseCompileDump '${hello .meth (arg) : dfl }')
          .toEqual '${hello.meth(arg): dfl }'
      expect(parseCompileDump '\\(noesc\\),but ${hello\\.meth\\((arg).\\:dfl}')
        .toEqual '\\(noesc\\),but ${hello\\.meth\\((arg).\\:dfl}'

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

      expect(parseCompileDump '$:hello': ['args']).toEqual '${hello(args)}'

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

    it 'should return a sole expansion within a string untouched', ->
      expect(expand {
          '$%':
            foo: '$bar'
            bar: '${baz}'
            baz:
              compound: ['object']
          '$': '$foo'
        }).toEqual compound: ['object']
      expect(expand '$foo', foo: {toString: -> 'Whee'}).not.toEqual 'Whee'

    it 'should expand ${} to an empty string', ->
      expect(expand '${}').toEqual ''
      expect(expand '${}$foo', foo: {toString: -> 'Whee'}).toEqual 'Whee'

    it 'should expand variables with computed names properly', ->
      expect(expand {
          '$%':
            foo: 'dead$bzz'
            bzz: 'bee'
            deadbeef: 0xC0FFEE
          '$': '${${foo}f}'
        }).toEqual 0xC0FFEE

    it 'should unescape special chars properly', ->
      expect(expand '$$$$$$$$$$$$$$$${16} macros is ${$$.$$}some',
        $: {$: 'Aww!'}).toEqual '$$$$$$$${16} macros is Aww!some'

      expect(expand '\\(noesc\\),but ${hello\\.meth\\((arg).\\:dfl}',
          'hello.meth(': (arg) -> ':dfl': [arg])
        .toEqual '\\(noesc\\),but arg'

    it 'should raise an error in case of unterminated expansion braces', ->
      expect(-> expand '${${foo}f')
        .toThrowError CompileError, /expected closing/i

    it 'should follow properties within variable expansion', ->
      expect(expand {
          '$%':
            foo: '$bar'
            bar: '${baz}'
            baz:
              compound: ['object']
          '$': '${foo.compound.0}'
        }).toEqual 'object'

    it 'should call a function passing a single argument, if any', ->
      expect(expand '${foo()}${foo(gh)}${foo(${})}', {
          foo: (arg) -> if arg? then "[#{arg}]" else @bar
          bar: 'Arrrr'
        }).toEqual 'Arrrr[gh][]'

    it 'should support balanced parens/braces inside the argument', ->
      expect(expand '${foo(())}', foo: (arg) -> "[#{arg}]")
        .toEqual '[()]'
      expect(expand '${foo(({(aaa)}))}', foo: (arg) -> "[#{arg}]")
        .toEqual '[({(aaa)})]'

      expect(expand '${foo( 1( 2 {3( aaa ) 3}2 ) 1 )}',
          foo: (arg) -> "[#{arg}]")
        .toEqual '[ 1( 2 {3( aaa ) 3}2 ) 1 ]'

    it 'should support backslash escaping inside expression or argument', ->
      expect(expand '${foo\\:bar\\.baz}', 'foo:bar.baz': "ret!")
        .toEqual 'ret!'

      expect(expand '${foo(\\\\aaa\\)\\))}', foo: (arg) -> "[#{arg}]")
        .toEqual '[\\aaa))]'

    it 'should return default value if expression evaluates to undefined', ->
      expect(expand '${foo:bar}', foo: 'baz').toEqual 'baz'
      expect(expand '${foo:bar}').toEqual 'bar'

      expect(expand '${foo:ba${r:z}}', foo: 'foof').toEqual 'foof'
      expect(expand '${foo:ba${r:z}}', r: 'roof').toEqual 'baroof'
      expect(expand '${foo:ba${r:z}}').toEqual 'baz'

    it 'should not propagate "this" when calling parenthesized expression', ->
      expect(expand '${foo():xxx}', foo: (-> @bar), bar: 'baz').toEqual 'baz'
      expect(expand '${(foo)():xxx}', foo: (-> @bar), bar: 'baz').toEqual 'xxx'

    it 'should expand ${@} as "this"', ->
      expect(expand '${arg(${@})}', foo: 'bar', arg: (obj) -> obj.foo)
        .toEqual 'bar'

  describe 'extending objects with $!', ->
    it 'should assign properties from source object', ->
      expect(expand {
          foo: 'bar'
          '$!':
            bar: 'baz'
        }).toEqual foo: 'bar', bar: 'baz'

    it 'should assign properties from source object using expansion', ->
      expect(expand {
          foo: 'bar'
          '$!': '$obj'
        }, obj: {bar: 'baz'}).toEqual foo: 'bar', bar: 'baz'

    it 'should fail to copy conflicting properties', ->
      expect(-> expand {
          foo: 'bar'
          '$!':
            foo: 'baz'
        }).toThrowError ExpandError, /already has/i

  describe 'calling functions with $:func: [...]', ->
    func = null

    beforeEach ->
      func = jasmine.createSpy('func').and.returnValue 42

    it 'should expand the reference and call the result passing args', ->
      expect(expand '$:func': [1, 2, 3], {func}).toEqual 42
      expect(func).toHaveBeenCalled()
      expect(func.calls.count()).toEqual 1


    it 'should support referring a function through properties', ->
      expect(expand '$:lib.func': [1, 2, 3], {lib: {func}}).toEqual 42
      expect(func).toHaveBeenCalled()
      expect(func.calls.count()).toEqual 1

  describe 'loading templates from file', ->
    path = require 'path'
    templatesDir = path.resolve __dirname, 'templates'

    expandFile = do ({expandFile} = require '../lib/template') ->
      (filename, variables, options) ->
        filename = path.resolve templatesDir, filename
        expandFile filename, variables, options

    it 'can load and expand a simple template', ->
      expect(expandFile 'hello.yaml').toEqual hey: 'Hello World!'

    it 'can include a file from within a template', ->
      expect(expand '${include(hello.yaml)}', {}, dirname: templatesDir)
        .toEqual hey: 'Hello World!'

    it 'should "see" outer scope variables inside an included file', ->
      expect(expandFile 'hello-i18n.yaml', lang: 'en')
        .toEqual hey: 'Hello World!'
      expect(expandFile 'hello-i18n.yaml', lang: 'ru')
        .toEqual hey: 'Салют World!'




