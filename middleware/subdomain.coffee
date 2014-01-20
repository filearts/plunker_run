nconf = require("nconf")

host = nconf.get("host")
hostEsc = host.replace(/[-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g, "\\$&")
plunkRe = new RegExp("^([0-9a-zA-Z]+)\.plunk\.#{hostEsc}$")
previewRe = new RegExp("^([0-9a-zA-Z]+)\.#{hostEsc}$")
recapitalize = (id) ->
  id.replace /([a-z]/, ""

module.exports.middleware = (config = {}) ->
  (req, res, next) ->
    # Rewrite plunk previews to the expected path
    if matches = req.headers.host.match(plunkRe)
      req.url = "/plunks/#{matches[1]}#{req.url}"
      console.log "Rewrote url to", req.url
      
    # Rewrite temporary previews to the expected path
    else if matches = req.headers.host.match(previewRe)
      req.url = "/#{matches[1]}#{req.url}"
      console.log "Rewrote url to", req.url
    
    
    next()