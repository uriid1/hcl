#!/usr/bin/env luajit

---------------------------
-- HTTP Client in LuaJIT
-- by uriid1
-- 2025
---------------------------

package.path = package.path .. ';share/lua/5.1/?.lua'
package.cpath = package.cpath .. ';lib/lua/5.1/?.so'

local socket = require("socket")
local url = require("socket.url")
local mime = require("mime")
local ssl = require("ssl")
local zlib = require("zlib")
local os = require("os")
local io = require("io")
local arg = arg or {...}

local version = 0.1

-- Default settings
local settings = {
  host = "0.0.0.0",
  port = 80,
  method = "GET",
  path = "/",
  body = "",
  headers = {},
  timeout = 30,
  verbose = false,
  auth = nil,
  output = nil,
  body_only = false,
  follow_redirects = false,
  max_redirects = 5,
  cookie_file = nil,
  cookie_save = nil,
  upload_file = nil,
  decompress = true
}

local USAGE_TEXT = [[
Options:
  -h HOST          Specify host (default: 0.0.0.0)
  -p PORT          Specify port (default: 80)
  -m METHOD        HTTP method (default: GET)
  -P PATH          Request path (default: /)
  -d BODY          Request body
  -H 'Name: Value' Add custom header (can be used multiple times)
  -t TIMEOUT       Connection timeout in seconds (default: 30)
  -v               Verbose mode
  -A 'user:pass'   Basic authentication
  -o FILE          Save response to file
  -b               Save only body to file (no HTTP headers)
  -r               Follow redirects
  -R NUM           Maximum number of redirects (default: 5)
  -c FILE          Use cookie file
  -C FILE          Save cookies to file
  -f FILE          Upload file
  -z               Don't decompress gzipped responses
  -help            Show this help message
  -version         Show script version
]]

local function printUsage()
  io.write("Usage: " .. arg[0] .. " [options]\n")
  io.write(USAGE_TEXT)

  os.exit(1)
end

local function log(text)
  io.write(text, "\n")
end

local i = 1
while i <= #arg do
  local opt = arg[i]

  if opt == "-h" and i < #arg then
    settings.host = arg[i+1]
    i = i + 2
  elseif opt == "-p" and i < #arg then
    settings.port = tonumber(arg[i+1])
    i = i + 2
  elseif opt == "-m" and i < #arg then
    settings.method = arg[i+1]
    i = i + 2
  elseif opt == "-P" and i < #arg then
    settings.path = arg[i+1]
    i = i + 2
  elseif opt == "-d" and i < #arg then
    settings.body = arg[i+1]
    i = i + 2
  elseif opt == "-H" and i < #arg then
    local header = arg[i+1]
    local name, value = header:match("([^:]+):%s*(.*)")
    if name and value then
      settings.headers[name] = value
    end
    i = i + 2
  elseif opt == "-t" and i < #arg then
    settings.timeout = tonumber(arg[i+1])
    i = i + 2
  elseif opt == "-v" then
    settings.verbose = true
    i = i + 1
  elseif opt == "-A" and i < #arg then
    settings.auth = arg[i+1]
    i = i + 2
  elseif opt == "-o" and i < #arg then
    settings.output = arg[i+1]
    i = i + 2
  elseif opt == "-b" then
    settings.body_only = true
    i = i + 1
  elseif opt == "-r" then
    settings.follow_redirects = true
    i = i + 1
  elseif opt == "-R" and i < #arg then
    settings.max_redirects = tonumber(arg[i+1])
    i = i + 2
  elseif opt == "-c" and i < #arg then
    settings.cookie_file = arg[i+1]
    i = i + 2
  elseif opt == "-C" and i < #arg then
    settings.cookie_save = arg[i+1]
    i = i + 2
  elseif opt == "-f" and i < #arg then
    settings.upload_file = arg[i+1]
    i = i + 2
  elseif opt == "-z" then
    settings.decompress = false
    i = i + 1
  elseif opt == "-help" then
    printUsage()
  elseif opt == '-version' then
    io.write("Version: " .. version, "\n")
    os.exit(1)
  else
    log("Unknown option: " .. opt)

    printUsage()
  end
end

local function readFile(filepath)
  local file = io.open(filepath, "rb")

  if not file then
    log("Error: Could not open file " .. filepath)

    os.exit(1)
  end

  local content = file:read("*all")

  file:close()

  return content
end

local function writeFile(filepath, content)
  local file = io.open(filepath, "wb")

  if not file then
    log("Error: Could not open file " .. filepath .. " for writing")

    os.exit(1)
  end

  file:write(content)
  file:close()
end

local function genBoundary()
  math.randomseed(os.time())

  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  local boundary = "---------------------------"

  for _ = 1, 16 do
    local random_index = math.random(1, #chars)

    boundary = boundary .. chars:sub(random_index, random_index)
  end

  return boundary
end

local function prepareMultipartBody(filepath, boundary)
  local filename = filepath:match("([^/\\]+)$")
  local fileContent = readFile(filepath)

  local body = ""
  body = body .. "--" .. boundary .. "\r\n"
  body = body .. "Content-Disposition: form-data; name=\"file\"; filename=\"" .. filename .. "\"\r\n"
  body = body .. "Content-Type: application/octet-stream\r\n\r\n"
  body = body .. fileContent .. "\r\n"
  body = body .. "--" .. boundary .. "--\r\n"

  return body
end

-- Decode chunked transfer encoding
local function decodeChunked(data)
  local result = ""
  local pos = 1

  while pos <= #data do
    -- Find the end of the chunk size line
    local chunkSizeEnd = data:find("\r\n", pos)

    if not chunkSizeEnd then
      break
    end

    -- Extract and parse the chunk size (in hex)
    local chunkSizeHex = data:sub(pos, chunkSizeEnd - 1)
    local chunkSize = tonumber(chunkSizeHex, 16)

    -- If chunk size is 0, we've reached the end
    if chunkSize == 0 then
      break
    end

    -- Skip past the CRLF after the chunk size
    pos = chunkSizeEnd + 2

    -- Extract the chunk data
    local chunkData = data:sub(pos, pos + chunkSize - 1)
    result = result .. chunkData

    -- Move past this chunk and the CRLF that follows it
    pos = pos + chunkSize + 2
  end

  return result
end

-- Decompress gzipped content
local function decompressGzip(data)
  local success, result = pcall(function()
    local stream = zlib.inflate()
    local chunks = {}
    local chunk = stream(data)

    if chunk and #chunk > 0 then
      table.insert(chunks, chunk)
    end

    return table.concat(chunks)
  end)

  if success and result and #result > 0 then
    return result
  end

  log("Warning: Failed to decompress gzipped content")

  return data
end

local function parseHttpResponse(response)
  local headers = {}
  local statusCode = 0

  local headersEnd = response:find("\r\n\r\n")

  if not headersEnd then
    headersEnd = response:find("\n\n")
    if headersEnd then
      headersEnd = headersEnd + 1
    else
      -- No clear header/body separation, assume it's all headers
      headersEnd = #response
    end
  else
    headersEnd = headersEnd + 3
  end

  local headersText = response:sub(1, headersEnd)
  local body = response:sub(headersEnd + 1)

  -- Parse status line
  local statusLine = headersText:match("^([^\r\n]+)")
  if statusLine then
    statusCode = tonumber(statusLine:match("HTTP/%d%.%d (%d+)"))
  end

  -- Parse headers
  for name, value in headersText:gmatch("([^:\r\n]+):%s*([^\r\n]*)") do
    headers[name:lower()] = value
  end

  -- Handle chunked transfer encoding
  if headers["transfer-encoding"] and
    headers["transfer-encoding"]:lower() == "chunked"
  then
    body = decodeChunked(body)
  end

  -- Handle gzip content encoding
  if headers["content-encoding"] and
    headers["content-encoding"]:lower() == "gzip"
    and settings.decompress
  then
    body = decompressGzip(body)
  end

  return {
    status_code = statusCode,
    status_line = statusLine,
    headers = headers,
    body = body,
    raw_headers = headersText
  }
end

-- Make an HTTP request
local function makeRequest(settings)
  -- Prepare request headers
  local reqHeaders = {
    ["Host"] = settings.host,
    ["Connection"] = "close"
  }

  -- Add custom headers
  for name, value in pairs(settings.headers) do
    reqHeaders[name] = value
  end

  -- Handle file upload
  if settings.upload_file then
    local boundary = genBoundary()

    settings.body = prepareMultipartBody(settings.upload_file, boundary)

    reqHeaders["Content-Type"] = "multipart/form-data; boundary=" .. boundary
  end

  -- Add Content-Length if body is present
  if settings.body and #settings.body > 0 then
    reqHeaders["Content-Length"] = #settings.body

    -- Add default Content-Type for non-GET requests if not specified
    if settings.method ~= "GET" and not reqHeaders["Content-Type"] then
      reqHeaders["Content-Type"] = "application/json"
    end
  end

  -- Add Basic Authentication
  if settings.auth then
    local encoded = mime.b64(settings.auth)

    reqHeaders["Authorization"] = "Basic " .. encoded
  end

  -- Add cookies from file
  if settings.cookie_file then
    local cookie_content = readFile(settings.cookie_file)

    reqHeaders["Cookie"] = cookie_content
  end

  -- Build request
  local request = settings.method .. " " .. settings.path .. " HTTP/1.1\r\n"

  -- Add headers
  for name, value in pairs(reqHeaders) do
    request = request .. name .. ": " .. value .. "\r\n"
  end

  -- Add empty line to separate headers from body
  request = request .. "\r\n"

  -- Add body if present
  if settings.body and #settings.body > 0 then
    request = request .. settings.body
  end

  -- Print request in verbose mode
  if settings.verbose then
    log("<<<< REQUEST <<<<")
    log(request)
    log("<<<<<<<<<<<<<<<<<<")
  end

  -- Create socket
  local client = socket.tcp()

  client:settimeout(settings.timeout)

  -- Connect to server
  local success, err = client:connect(settings.host, settings.port)
  if not success then
    log("Error connecting to " .. settings.host .. ":" .. settings.port .. ": " .. err)

    os.exit(1)
  end

  -- Wrap socket in SSL if using port 443
  if settings.port == 443 then
    local params = {
      mode = "client",
      protocol = "any",
      verify = "none",
      options = "all"
    }

    client = ssl.wrap(client, params)
    success, err = client:dohandshake()
    if not success then
      log("SSL handshake failed: " .. err)

      os.exit(1)
    end
  end

  -- Send request
  local bytes, err = client:send(request)
  if not bytes then
    log("Error sending request: " .. err)

    os.exit(1)
  end

  -- Receive response
  local response = ""
  local chunk
  local err
  local partial

  repeat
    chunk, err, partial = client:receive(8192)

    if chunk then
      response = response .. chunk
    elseif partial and #partial > 0 then
      response = response .. partial
    end
  until not chunk and err == "closed"

  -- Close connection
  client:close()

  -- Parse response
  local parsed = parseHttpResponse(response)

  -- Save cookies if requested
  if settings.cookie_save then
    local cookies = {}
    for name, value in pairs(parsed.headers) do
      if name:lower() == "set-cookie" then
        table.insert(cookies, value)
      end
    end

    if #cookies > 0 then
      writeFile(settings.cookie_save, table.concat(cookies, "\n"))
    end
  end

  -- Print response in verbose mode
  if settings.verbose then
    log(">>>> RESPONSE >>>>")
    log(parsed.raw_headers)

    if parsed.headers["content-encoding"] and not settings.decompress then
      log("[Compressed content not displayed in verbose mode]")
    else
      log(parsed.body)
    end
    log(">>>>>>>>>>>>>>>>>>>>")
  end

  -- Handle redirects
  if settings.follow_redirects and
    settings.max_redirects > 0 and
    (
      parsed.status_code == 301 or
      parsed.status_code == 308
    )
  then
    local location = parsed.headers["location"]
    if location then
      log("\nFollowing redirect to: " .. location .. "\n")

      -- Parse the redirect URL
      local redirectUrl = url.parse(location)
      local newSettings = {}

      -- Copy current settings
      for k, v in pairs(settings) do
        newSettings[k] = v
      end

      -- Update settings for the redirect
      if redirectUrl.host then
        -- Absolute URL
        newSettings.host = redirectUrl.host
        newSettings.path = redirectUrl.path or "/"

        if redirectUrl.port then
          newSettings.port = tonumber(redirectUrl.port)
        elseif redirectUrl.scheme == "https" then
          newSettings.port = 443
        else
          newSettings.port = 80
        end
      else
        -- Relative URL
        newSettings.path = location
      end

      -- Always use GET for redirects
      newSettings.method = "GET"
      newSettings.body = ""
      newSettings.max_redirects = settings.max_redirects - 1

      -- Follow the redirect
      return makeRequest(newSettings)
    end
  end

  return parsed
end

---------------------------------------
-- main
---------------------------------------
local response = makeRequest(settings)
-- response.body
-- response.headers
-- response.raw_headers
-- response.status_code
-- response.status_line

if settings.output then
  local content
  if settings.body_only then
    content = response.body
  else
    content = response.raw_headers .. "\r\n" .. response.body
  end

  writeFile(settings.output, content)

  log("Response saved: " .. settings.output)

  os.exit(1)
end
