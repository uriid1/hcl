#!/bin/bash

luarocks install luasocket --lua-version 5.1 --local --tree $PWD
luarocks install luasec --lua-version 5.1 --local --tree $PWD
luarocks install lua-zlib --lua-version 5.1 --local --tree $PWD
