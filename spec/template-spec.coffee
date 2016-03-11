describe 'template', ->
  {expand} = require '../lib/template'

  it 'should leave objects with no macros or variables as is', ->
    expect(expand 'Hello world!')
      .toEqual 'Hello world!'

    expect(expand [greeting: 'Hello world!'])
      .toEqual [greeting: 'Hello world!']
