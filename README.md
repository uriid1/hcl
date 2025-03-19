# hcl
Http client in luaJIT

# Installation
```bash
bash deps.sh
```

# Usage
```
Usage: ./hcl.lua [options]
Options:
  -h HOST          Specify host (default: 0.0.0.0)
  -p PORT          Specify port (default: 443)
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
```
