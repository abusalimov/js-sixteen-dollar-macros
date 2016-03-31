fs   = require 'fs'
path = require 'path'

_ = require 'lodash'


loadString = (source, format, {unsafe, filename} = {}) ->
  switch format
    when 'yaml', 'yml'
      require('js-yaml').load source, {filename, strict: yes}
    when 'cson'
      require('cson-parser').parse source
    when 'json'
      JSON.parse source
    else
      unless unsafe
        throw new Error "Unknown file format '#{format}'"

      switch format
        when 'coffee'
          require('coffee-script').eval source, {filename}
        when 'js', 'javascript'
          require('vm').runInNewContext source, {}, {filename}


loadFile = (filename, options) ->
  source = fs.readFileSync(filename, 'utf8')

  options = _.extend {}, options
  options.format = "#{options.format ?
                      path.extname filename}".replace(/^\./, '').toLowerCase()
  options.filename ?= path.resolve filename

  loadString source, options.format, options


module.exports = {
  loadString
  loadFile
}
