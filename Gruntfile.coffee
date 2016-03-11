module.exports = (grunt) ->
  grunt.initConfig
    clean:
      lib:
        src: ['lib/']

    coffee:
      compile:
        options:
          sourceMap: true
        expand: true
        cwd: 'src'
        src: ['*.coffee']
        dest: 'lib'
        ext: '.js'

    jasmine_nodejs:
      run_specs:
        options:
          specNameSuffix: ['spec.js', 'spec.coffee']
        specs: ['spec/**']

  grunt.loadNpmTasks 'grunt-contrib-clean'
  grunt.loadNpmTasks 'grunt-contrib-coffee'
  grunt.loadNpmTasks 'grunt-jasmine-nodejs'

  grunt.registerTask 'build', ['coffee']
  grunt.registerTask 'test', ['clean', 'build', 'jasmine_nodejs']
  grunt.registerTask 'prepublish', ['clean', 'build']

  grunt.registerTask 'default', ['test']
