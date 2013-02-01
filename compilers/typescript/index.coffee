fs = require("fs")
TypeScript = require("typescript-wrapper")

libfile = fs.readFileSync(TypeScript._libdPath, "utf8")


###
Compiler for TypeScript

Code adapted from the following sources:
* https://github.com/damassi/TypeScript-Watcher/
* https://github.com/niutech/typescript-compile/

###

createFile = ->
  source: ""
  Write: (text) -> @source += text
  WriteLine: (text) -> @source += text + "\n"
  Close: ->
    
module.exports =
  match: /\.js$/
  ext: ["ts"]
  compile: (filename, source, str, fn) ->
        
    jsOutput = createFile()
    mapOutput = createFile()
    errOutput = createFile()
        
    
    compiler = new TypeScript.TypeScriptCompiler(errOutput)
    
    compiler.settings.mapSourceFiles = true
    compiler.settings.resolve = false
    
    compiler.parser.errorRecovery = true
    
    compiler.addUnit(libfile, "lib.d.ts")
    compiler.addUnit(str, source or "")
    
    compiler.typeCheck()
    
    compiler.emit (filename) ->
      console.log "Compiling", filename
      if filename.match(/\.map$/) then mapOutput
      else jsOutput
    
    console.log "Sourcemap", mapOutput.source
    
    fn null, jsOutput.source, mapOutput.source
