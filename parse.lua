#!/usr/local/bin/lua
-- parse.lua
--
-- Usage:
--   ./parse.lua <input_file>
--
-- This is a script to parse mathematical expressions
-- using only small positive integers, addition, and multiplication.
--


--[[

Here's the idea behind how we'll parse expressions.

expr -> sum
sum -> prod[ + prod]
prod -> num[ * num]
num -> "\d+"

On success, each parse_X function will return tree, tail, where tree is
an abstract syntax tree of the form {type, kids, value}, and tail is
the unparsed portion of the string.

On failure, parse_X returns 'no match', tail, where tail is the full
string given as input to parse_X.

--]]


------------------------------------------------------------------------------
-- Parse functions.
------------------------------------------------------------------------------

function parse_expr(expr_str)
  print('Got the expr_str ' .. expr_str)
end

function parse_sum(sum_str)
end

function parse_prod(prod_str)
end

function parse_num(num_str)
  first, last = num_str:find('^%d+')
  if not first then return 'no match', num_str end
  local value = tonumber(num_str:sub(first, last))
  return {type='num', value=value}, num_str:sub(last + 1)
end


------------------------------------------------------------------------------
-- Debug functions.
------------------------------------------------------------------------------

-- TODO Fill out this function or copy over another similar already done one.
function pr_val(val)
  if type(val) == 'table' then
    for k, v in pairs(val) do print(k, v) end
    return
  end
  print(val)
end


------------------------------------------------------------------------------
-- Main.
------------------------------------------------------------------------------

-- Check that they provided an input file name.
if not arg[1] then
  print('Usage:')
  print('  ' .. arg[0] .. ' <input_file>')
  os.exit(2)
end

local in_file = arg[1]
local f = assert(io.open(in_file, 'r'))
for line in f:lines() do
  -- Eventually this will just be:
  --parse_expr(line)
  local result, tail = parse_num(line)
  print('')
  print('result, tail :')
  pr_val(result)
  pr_val(tail)
end
f:close()

