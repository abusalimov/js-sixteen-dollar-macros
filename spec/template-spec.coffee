describe 'template', ->
  {expand} = require '../lib/template'

  it 'should leave objects with no macros or variables as is', ->
    expect(expand 'Hello world!')
      .toEqual 'Hello world!'

    expect(expand [greeting: 'Hello world!'])
      .toEqual [greeting: 'Hello world!']

  describe 'parsing', ->
    {nodeFromObject, nodeToObject} = require '../lib/template'

    testObjects = [
      'Hello world!'

      {greeting: 'Hello world!'}

      [greeting: 'Hello world!']

      {foo: (bar) -> baz}

      [[[{string: 'Hello', number: 42, answer: yes}]]]
    ]

    it 'should keep reverse relation between nodeToObject/nodeFromObject', ->
      for object in testObjects
        expect(nodeToObject nodeFromObject object).toEqual object
