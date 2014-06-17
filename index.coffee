express = require("express")
nconf = require("nconf")
_ = require("underscore")._
validator = require("json-schema")
mime = require("mime")
url = require("url")
request = require("request")
path = require("path")
#ga = require("node-ga")
genid = require("genid")
lactate = require("lactate")
path = require("path")
fs = require("fs")


# Set defaults in nconf
require "./configure"


app = module.exports = express()
runUrl = nconf.get("url:run")

genid = (len = 16, prefix = "", keyspace = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789") ->
  prefix += keyspace.charAt(Math.floor(Math.random() * keyspace.length)) while len-- > 0
  prefix


#app.use ga("UA-28928507-4", safe: false)
#app.use require("./middleware/subdomain").middleware()
app.use require("./middleware/cors").middleware()
app.use express.urlencoded({limit: '2mb'})
app.use express.json({limit: '2mb'})
app.use lactate.static "#{__dirname}/public",
  'max age': 'one week'

LRU = require("lru-cache")
previews = LRU(512)
sourcemaps = LRU(512)

apiUrl = nconf.get("url:api")

coffee = require("coffee-script")
livescript = require("LiveScript")
less = require("less")
sass = require("sass")
scss = require("node-sass")
jade = require("jade")
markdown = require("marked")
stylus = require("stylus")
nib = require("nib")
traceur = require("traceur")

TRACEUR_RUNTIME = ""

fs.readFile traceur.RUNTIME_PATH, "utf8", (err, src) ->
  unless err then TRACEUR_RUNTIME = src


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
          
          
        js = answer.js + "\n//# sourceMappingURL=#{path}#{filename}.map"
        smap = answer.v3SourceMap
        
        fn null, js, smap
      catch err
        fn(err)
      
  traceur: 
    match: /\.js$/
    ext: ['es6.js']
    compile: (path, filename, source, str, plunk, fn) ->
      try
        answer = traceur.compile str,
          bare: true
          sourceMap: true
          experimental: true
          filename: source
        
        if answer.errors.length
          error = new Error("Error compiling #{filename}")
          error.data = answer.errors
          
          fn error
        else
          
          js = TRACEUR_RUNTIME + ";\n" + answer.js + "\n//# sourceMappingURL=#{path}#{filename}.map"
          smap = answer.sourceMap
          
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
      return fn(null, "") unless source
      
      try
        fn null, """
          <link rel="stylesheet" href="/markdown.css" type="text/css">
          
          #{markdown(str)}
        """
      catch err
        fn(err)
  
  typescript: require("./compilers/typescript")

renderPlunkFile = (req, res, next) ->
  plunk = req.plunk
  filename = req.params[0] or "index.html"
  file = plunk.files[filename]
  
  res.charset = "utf-8"

  res.set "Cache-Control", "no-cache"
  res.set "Expires", 0
  
  if file
    file.mime ||= mime.lookup(filename, "text/plain")
    
    res.set("Content-Type": if req.accepts(file.mime) then file.mime else "text/plain")

    
    if (etag = req.get("if-none-match")) and etag is file.etag then return res.send(304)
        
    return res.send(200, file.content)
    
  else
    render = (filename) ->
      extension = "." + path.basename(filename).split(".").slice(1).join(".")
      base = path.join path.dirname(filename), path.basename(filename, extension)
      type = mime.lookup(filename) or "text/plain"
      
      for name, compiler of compilers when filename.match(compiler.match)
        for ext in compiler.ext
          if found = plunk.files["#{base}.#{ext}"]
            compiler.compile req.dir, filename, found.filename, found.content, plunk, (err, compiled, sourcemap) ->
              if err
                console.log "[ERR] Compilation error:", err.message
                return res.json 500, err.data or "Compilation error"
              else
                if sourcemap
                  sourcemapFile = "#{filename}.map"
                  
                  smap = plunk.files[sourcemapFile] =
                    filename: sourcemapFile
                    content: sourcemap
                    source: "#{base}.#{ext}"
                    mime: "application/json"
                    run_url: plunk.run_url + sourcemapFile
                    etag: genid(16) + plunk.frozen_at
                  
                  res.set "SourceMap", req.dir + sourcemapFile
                  
                file = plunk.files[filename] =
                  filename: filename
                  content: compiled
                  source: "#{base}.#{ext}"
                  mime: mime.lookup(filename, "text/plain")
                  run_url: plunk.run_url + filename
                  etag: genid(16) + plunk.frozen_at
                
                found.children ||= []
                found.children.push(file)
                found.children.push(smap) if smap
                  
                res.set("Content-Type": if req.accepts(file.mime) then file.mime else "text/plain")
                res.set("ETag", file.etag)
                
                res.send 200, compiled
            return true
  
  test = [filename]
  test.push(file) for file in ["index.html", "example.html", "README.html", "demo.html", "readme.html"] when 0 > test.indexOf(file)
  
  for attempt in test
    return if render(attempt)
  
  # Control will reach here if no file was found
  console.log "[ERR] No suitable source file for: ", filename
  res.send(404)
  
app.get "/plunks/:id/*", (req, res, next) ->
  req_url = url.parse(req.url)
  unless req.params[0] or /\/$/.test(req_url.pathname)
    req_url.pathname += "/"
    return res.redirect(301, url.format(req_url))
  
  req.dir = "/plunks/#{req.params.id}/"
  
  request {url: "#{apiUrl}/plunks/#{req.params.id}?nv=1", json: true}, (err, response, body) ->
    return res.send(500) if err
    return res.send(response.statusCode) if response.statusCode >= 400
    
    req.plunk = body
    
    try
      unless req.plunk then res.send(404) # TODO: Better error page
      else renderPlunkFile(req, res, next)
    catch e
      console.trace "[ERR] Error rendering file", e
      res.send 500
        
app.get "/plunks/:id", (req, res) -> res.redirect(301, "/plunks/#{req.params.id}/")

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
    prev = previews.get(req.params.id)
    json.id = id
    json.run_url = "#{runUrl}/#{id}/"
    
    _.each json.files, (file, filename) ->
      if prev && ((prevFile = prev?.files[filename])?.content is file.content)
        json.files[filename] = prevFile
        json.files[child.filename] = child for child in prevFile.children
      
      else
        json.files[filename] =
          filename: filename
          content: file.content
          mime: mime.lookup(filename, "text/plain")
          run_url: json.run_url + filename
          etag: genid(16)
          children: []

    previews.set(id, json)
    
    #return res.redirect "/#{id}/"
    
    status = if prev then 200 else 201
    
    req.plunk = json
    req.dir = "/#{id}/"
    
    if req.is("application/x-www-form-urlencoded")
      res.header "X-XSS-Protection", 0
    
      renderPlunkFile(req, res, next)
    else
      res.json status, url: json.run_url



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