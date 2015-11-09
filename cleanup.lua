#!/usr/local/bin/lua
--[[

cleanup.lua

A script to help clean up .lua.md files by removing some comment markers that
just add visual clutter in the processed markdown.

--]]

usage = [[
cleanup.lua <lua.md_filename>

Opens the given <name>.lua.md file and writes the clean version to <name>.md.
Will overwrite <name>.md if it already exists.
]]

-- Check the command line arguments.
if not arg[1] then
  print('Usage:')
  print(usage)
  os.exit(2)  --> 2 indicates a problem with the arguments.
end

-- Read in the file.
local infile = arg[1]
local _, _, basename = infile:find('^(.*)%.lua%.md$')
if not basename then
  print('Error: expected the input file to end in ".lua.md"')
  os.exit(2)  --> 2 indicates a problem with the arguments.
end
local f = assert(io.open(infile, 'rb'))
local text = f:read('*a')  -- '*a' --> read the entire file
f:close()

-- Clean up the text.
-- Remove all multiline comment start and end markers that begin a line.
-- The start of this pattern, '%f[^\n%z]', essentially indicates to only support
-- matches at the beginning of lines, including possibly the first line.
text = text:gsub('%f[^\n%z]%-%-%[=*%[ *\n', '')
text = text:gsub('%f[^\n%z]%-%-%]=*%] *\n', '')

-- Write to the output file.
local outfile = basename .. '.md'
f = io.open(outfile, 'wb')
f:write(text)
f:close()
