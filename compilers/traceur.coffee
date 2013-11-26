nconf = require("nconf")
traceur = require("traceur")
uglify = require("uglify-js")
fs = require("fs")

SourceMapGenerator = traceur.outputgeneration.SourceMapGenerator

traceur.options.freeVariableChecker = false
traceur.options.deferredFunctions = true
traceur.options.experimental = true

ext = 'es6.js'
extRegex = /\.es6\.js$/

runtime = fs.readFileSync(__dirname + "/../node_modules/traceur/src/runtime/runtime.js", "utf8")
runtime = uglify.minify(runtime, fromString: true)

module.exports = 
  match: /\.js$/
  ext: [ext]
  compile: (path, filename, source, str, plunk, fn) ->
    reporter = new traceur.util.ErrorReporter()
    project = new traceur.semantics.symbols.Project(nconf.get("url:run"))
    
    #for fname, file of plunk.files when file.filename.match(extRegex)
    #  sourceFile = new traceur.syntax.SourceFile(file.filename.replace(extRegex, ".js"), file.content)
    #  project.addFile(sourceFile)
    
    project.addFile new traceur.syntax.SourceFile(filename, str)
      
    results = traceur.codegeneration.Compiler.compile(reporter, project)
    
    return fn(new Error("Unable to compile es6", + reporter)) if reporter.hadError()
    
    for file in results.keys() when file.name is filename
      tree = results.get(file)
      code = traceur.outputgeneration.TreeWriter.write(tree, false)
      return fn(null, "#{runtime.code}\n#{code}")
    
    return fn(new Error("Unable to parse file"))
      
      