#!/usr/bin/env coffee

http   = require 'http'
https  = require 'https'
url    = require 'url'
path   = require 'path'
fs     = require 'fs'
util   = require 'util'
stream = require 'stream'
coffee = require 'coffee-script'
jade   = require 'jade'
less   = require 'less'

log = (text) ->
  date = new Date
  date_text = "#{date.getFullYear()}-#{date.getMonth()+1}-#{date.getDate()} " +
              "#{date.getHours()}:#{date.getMinutes()}:#{date.getSeconds()} " +
              "(GMT#{-date.getTimezoneOffset()/60})"
  console.log "\n[#{date_text}] #{text}"

notFound = (req, res) ->
  log "#{req.parsed.pathname} - 404"
  res.writeHead 404, 'Content-Type': 'text/html'
  res.write '404 Not Found!'
  res.end()
  return

serverError = (req, res, error) ->
  log "#{req.parsed.pathname} - 500 - #{util.inspect req.error}"
  res.writeHead 500, 'Content-Type': 'text/html'
  res.write '500 Server Error!'
  res.end()
  return

class StringReader extends stream.Stream
  constructor: () -> @readable = true
  setEncoding: ->
  pause: ->
  resume: ->
  destroy: ->

processCoffee = (inputStream, req, res) ->
  outputStream = new StringReader
  data = ''
  inputStream.on 'data', (chunk) -> data += chunk
  inputStream.on 'end', ->
    outputStream.emit 'data', coffee.compile(data)
    outputStream.emit 'end'
  outputStream

processLess = (inputStream, req, res) ->
  outputStream = new StringReader
  data = ''
  inputStream.on 'data', (chunk) -> data += chunk
  inputStream.on 'end', ->
    less.render data, (e, compiledData) ->
      outputStream.emit 'data', compiledData
      outputStream.emit 'end'
  outputStream

processJade = (inputStream, req, res) ->
  outputStream = new StringReader
  data = ''
  inputStream.on 'data', (chunk) -> data += chunk
  inputStream.on 'end', ->
    outputStream.emit 'data', jade.compile(data)()
    outputStream.emit 'end'
  outputStream

checkStatic = (urlPattern, fileNamePattern = '$&') ->
  (req, res) ->
    return false unless req.method.toUpperCase() is 'GET'
    return false unless urlPattern.test(req.parsed.pathname)
    filename = path.join(__dirname, req.parsed.pathname.toString().replace(urlPattern, fileNamePattern))
    return false unless fs.existsSync(filename)
    req.filename = filename
    true

serveStatic = (contentType, processors) ->
  (req, res) ->
    res.writeHead 200, 'Content-Type': contentType
    stream = fs.createReadStream(req.filename)
    for processor in processors
      stream = processor(stream, req, res)
    stream.pipe(res)
    return

checkCourseraApi = (req, res) ->
  return false unless req.method.toUpperCase() is 'GET'
  matches = /^\/coursera\/([\da-z]+).json$/.exec req.parsed.pathname
  if matches isnt null
    req.userid = matches[1]
    return true
  false

serveCourseraApi = (req, res) ->
  https.get "https://www.coursera.org/maestro/api/user/profile?user-id=#{req.userid}", (profileRes) ->
    data = ''
    profileRes.on 'data', (chunk) -> data += chunk
    profileRes.on 'end', ->
      profile = JSON.parse data
      https.get "https://www.coursera.org/maestro/api/topic/list_my?user_id=#{profile.id}", (topicsRes) ->
        data = ''
        topicsRes.on 'data', (chunk) -> data += chunk
        topicsRes.on 'end', ->
          topics = JSON.parse data
          res.writeHead 200, 'Content-Type': 'text/json'
          res.write JSON.stringify
            name:    profile.display_name
            photo:   profile.photo
            courses: topics.map (topic) ->
              name:     topic.name
              photo:    topic.photo
              url:      topic.social_link
              duration: parseInt(/(\d+) weeks/.exec(topic.courses[0].duration_string)[1], 10) * 7
              start:
                year:  parseInt(topic.courses[0].start_year, 10)
                month: parseInt(topic.courses[0].start_month, 10)
                day:   (if topic.courses[0].start_day is null then null else parseInt(topic.courses[0].start_day, 10))
          res.end()
  return

routes = new Array

rootUrl = /^\/$/
routes.push
  check: checkStatic rootUrl, '/assets/index.jade'
  handle: serveStatic 'text/html', Array(processJade)

jsUrl = /^(\/\w+)*(\/[\w-.]+)\.js$/
routes.push
  check: checkStatic jsUrl, '/assets$1$2.coffee'
  handle: serveStatic 'text/javascript', Array(processCoffee)
routes.push
  check: checkStatic jsUrl, '/assets$1$2.js'
  handle: serveStatic 'text/javascript', Array()
routes.push
  check: checkStatic jsUrl, '/vendor$1$2.coffee'
  handle: serveStatic 'text/javascript', Array(processCoffee)
routes.push
  check: checkStatic jsUrl, '/vendor$1$2.js'
  handle: serveStatic 'text/javascript', Array()

cssUrl = /^(\/\w+)*(\/[\w-.]+)\.css$/
routes.push
  check: checkStatic cssUrl, '/assets$1$2.less'
  handle: serveStatic 'text/css', Array(processLess)
routes.push
  check: checkStatic cssUrl, '/assets$1$2.css'
  handle: serveStatic 'text/css', Array()
routes.push
  check: checkStatic cssUrl, '/vendor$1$2.less'
  handle: serveStatic 'text/css', Array(processLess)
routes.push
  check: checkStatic cssUrl, '/vendor$1$2.css'
  handle: serveStatic 'text/css', Array()

routes.push
  check: checkCourseraApi
  handle: serveCourseraApi

server = http.createServer (req, res) ->
  req.parsed = url.parse(req.url, true)
  for route in routes
    if route.check(req, res)
      try
        route.handle(req, res)
        log "#{req.method.toUpperCase()} '#{req.parsed.pathname}' - #{res.statusCode}"
        return
      catch error
        req.error = error
        serverError(req, res)
        return
  notFound(req, res)
  return
port = 3000
server.listen(port)
log "Server started at port #{port}!"
