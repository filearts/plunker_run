express = require("express")
nconf = require("nconf")
_ = require("underscore")._
validator = require("json-schema")
mime = require("mime")
url = require("url")
request = require("request")
path = require("path")



# Set defaults in nconf
require "./configure"


app = module.exports = express()
runUrl = nconf.get("url:run")

genid = (len = 16, prefix = "", keyspace = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789") ->
  prefix += keyspace.charAt(Math.floor(Math.random() * keyspace.length)) while len-- > 0
  prefix


app.use require("./middleware/cors").middleware()
app.use express.bodyParser()


LRU = require("lru-cache")
previews = LRU(512)
sourcemaps = LRU(512)

apiUrl = nconf.get("url:api")

coffee = require("coffee-script")
livescript = require("LiveScript")
iced = require("iced-coffee-script")
less = require("less")
sass = require("sass")
scss = require("node-sass")
jade = require("jade")
markdown = require("marked")
stylus = require("stylus")
nib = require("nib")
traceur = require("traceur")

compilers = 
  scss:
    match: /\.css$/
    ext: ['scss']
    compile: (path, filename, source, str, plunk, fn) ->
      try
        scss.render(str, fn)
      catch err
        fn(err)

  sass:
    match: /\.css$/
    ext: ['sass']
    compile: (path, filename, source, str, plunk, fn) ->
      try
        fn(null, sass.render(str))
      catch err
        fn(err)

  less: 
    match: /\.css$/
    ext: ['less']
    compile: (path, filename, source, str, plunk, fn) ->
      try
        less.render(str, fn)
      catch err
        fn(err)

  stylus: 
    match: /\.css/
    ext: ['styl']
    compile: (path, filename, source, str, plunk, fn) ->
      try
        stylus(str)
          .use(nib())
          .import("nib")
          .render(fn)
      catch err
        fn(err)      
  coffeescript: 
    match: /\.js$/
    ext: ['coffee']
    compile: (path, filename, source, str, plunk, fn) ->
      try
        answer = coffee.compile str,
          bare: true
          returnObject: true
          sourceMap: true
          filename: source
          sourceFiles: [path+source]
          generatedFile: path+filename
          
          
        js = answer.js + "\n//@ sourceMappingURL=#{path}#{filename}.map"
        smap = answer.v3SourceMap
        
        fn null, js, smap
      catch err
        fn(err)
      
  livescript: 
    match: /\.js$/
    ext: ['ls']
    compile: (path, filename, source, str, plunk, fn) ->
      try
        fn(null, livescript.compile(str))
      catch err
        fn(err)      
      
  icedcoffee: 
    match: /\.js$/
    ext: ['iced']
    compile: (path, filename, source, str, plunk, fn) ->
      try
        fn(null, iced.compile(str, runtime: "inline"))
      catch err
        fn(err)

  jade: 
    match: /\.html$/
    ext: ['jade']
    compile: (path, filename, source, str, plunk, fn) ->
      render = jade.compile(str, pretty: true)
      try
        fn(null, render({}))
      catch err
        fn(err)
      
  markdown: 
    match: /\.html$/
    ext: ['md',"markdown"]
    compile: (path, filename, source, str, plunk, fn) ->
      try
        fn(null, markdown(str))
      catch err
        fn(err)
  
  typescript: require("./compilers/typescript")
  
  traceur: require("./compilers/traceur")

renderPlunkFile = (req, res, next) ->
  plunk = req.plunk
  filename = req.params[0] or "index.html"
  file = plunk.files[filename]
  
  res.set "Cache-Control", "no-cache"
  res.set "Expires", 0
  
  if file
    res.set("Content-Type": if req.accepts(file.mime) then file.mime else "text/plain")
    return res.send(200, file.content)
    
  else if sourcemap = sourcemaps.get("#{req.dir}#{filename}")
    res.set "Content-Type", "application/json"
    res.send 200, sourcemap
    
    console.log "[**] Served sourcemap", "#{req.dir}#{filename}"
    
  else
    render = (filename) ->
      extension = "." + path.basename(filename).split(".").slice(1).join(".")
      base = path.basename(filename, extension)
      type = mime.lookup(filename) or "text/plain"
      
      for name, compiler of compilers when filename.match(compiler.match)
        for ext in compiler.ext
          if found = plunk.files["#{base}.#{ext}"]
            compiler.compile req.dir, filename, found.filename, found.content, plunk, (err, compiled, sourcemap) ->
              if err
                console.log "[ERR] Compilation error:", err.message
                return res.send 500, err.message or "Compilation error"
              else
                if sourcemap
                  sourcemap_id = "#{req.dir}#{filename}.map"
                  sourcemaps.set sourcemap_id, sourcemap
                  
                  res.set "SourceMap", sourcemap_id
                  
                res.set "Content-Type", if req.accepts(type) then type else "text/plain"
                res.send 200, compiled
            return true
            
    test = [filename]
    test.push(file) for file in ["index.html", "example.html", "demo.html", "readme.html"] when 0 > test.indexOf(file)
      
    for filename in test
      return if render(filename)
    
    # Control will reach here if no file was found
    console.log "[ERR] No suitable source file for: ", filename
    res.send(404)

app.get "/plunks/:id/*", (req, res, next) ->
  req_url = url.parse(req.url)
  unless req.params[0] or /\/$/.test(req_url.pathname)
    req_url.pathname += "/"
    return res.redirect(301, url.format(req_url))
  
  req.dir = "/plunks/#{req.params.id}/"
  
  request.get "#{apiUrl}/plunks/#{req.params.id}?nv=1", (err, response, body) ->
    return res.send(500) if err
    return res.send(response.statusCode) if response.statusCode >= 400
    
    try
      req.plunk = JSON.parse(body)
    catch e
      return res.send(500)
    
    unless req.plunk then res.send(404) # TODO: Better error page
    else renderPlunkFile(req, res, next)

app.get "/plunks/:id", (req, res) -> res.redirect(301, "/#{req.params.id}/")

app.post "/:id?", (req, res, next) ->
  json = req.body
  schema = require("./schema/previews/create")
  {valid, errors} = validator.validate(json, schema)
  
  # Despite its awesomeness, validator does not support disallow or additionalProperties; we need to check plunk.files size
  if json.files and _.isEmpty(json.files)
    valid = false
    errors.push
      attribute: "minProperties"
      property: "files"
      message: "A minimum of one file is required"
  
  unless valid then return next(new Error("Invalid json: #{errors}"))
  else
    id = req.params.id or genid() # Don't care about id clashes. They are disposable anyway
    json.id = id
    json.run_url = "#{runUrl}/#{id}/"

    _.each json.files, (file, filename) ->
      json.files[filename] =
        filename: filename
        content: file.content
        mime: mime.lookup(filename, "text/plain")
        run_url: json.run_url + filename

    
    previews.set(id, json)
    
    status = if req.params.id then 200 else 201
    
    res.json(status, json)



app.get "/:id/*", (req, res, next) ->
  unless req.plunk = previews.get(req.params.id) then res.send(404) # TODO: Better error page
  else
    req_url = url.parse(req.url)
    
    unless req.params[0] or /\/$/.test(req_url.pathname)
      req_url.pathname += "/"
      return res.redirect(301, url.format(req_url))
    
    req.dir = "/#{req.params.id}/"
  
    renderPlunkFile(req, res, next)

app.get "*", (req, res) ->
  res.send(404, "Preview does not exist or has expired.")