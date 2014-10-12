#!/usr/local/bin/lua
-- parse2.lua
--
-- Usage:
--   ./parse2.lua <input_file>
--
-- This script can parse a simple
-- imperative language.
--


--[[

TODO
 * The current code does not correctly parse all lines. Fix that.
 * Add the exec style functions, and update comments accordingly.

Here is an informal description of the grammar:

statement -> assign | for | print

assign     -> std_assign | inc_assign
std_assign -> var '=' expr
inc_assign -> var '+=' expr

expr       -> var | num
var        -> "[A-Za-z_][A-Za-z0-9_]*"
num        -> "[1-9][0-9]*"

for       -> 'for' var '=' expr 'to' expr ':' statement

print     -> 'print' expr

## Parse function style:

On success, each parse_X function will return tree, tail, where tree is
an abstract syntax tree of the form {type, (kids|value)}, and tail is
the unparsed portion of the string.

On failure, parse_X returns 'no match', tail, where tail is the full
string given as input to parse_X.

## Exec function style:

<TODO>

--]]


------------------------------------------------------------------------------
-- Metaparse functions.
------------------------------------------------------------------------------

function parse_or_rule(str, rule_name, or_parsers)
  local tree = {type = rule_name, kids={}}
  for _, subparse in ipairs(or_parsers) do
    local subtree, tail = subparse(str)
    if subtree ~= 'no match' then
      tree.kids[#tree.kids + 1] = subtree
      return tree, tail
    end
  end
  return 'no match', str
end

function parse_seq_rule(str, rule_name, seq_parsers)
  local tree = {type = rule_name, kids = {}}
  local subtree, tail = nil, str
  for _, subparse in ipairs(seq_parsers) do
    subtree, tail = subparse(tail)
    if subtree == 'no match' then return 'no match', str end
    tree.kids[#tree.kids + 1] = subtree
  end
  return tree, tail
end

function parse_lit(lit_str, name)
  name = name or '<lit>'
  local re = '%s*(' .. escaped_lit(lit_str) .. ')'
  return function(str)
    local s, e, val = str:find(re)
    if s == nil then return 'no match', str end
    return {type = name, value = val}, str:sub(e + 1)
  end
end

function parse_re(re_str, name)
  name = name or '<re>'
  local re = '%s*(' .. re_str .. ')'
  return function(str)
    local s, e, val = str:find(re)
    if s == nil then return 'no match', str end
    return {type = name, value = val}, str:sub(e + 1)
  end
end

function escaped_lit(lit_str)
  return lit_str:gsub('[^A-Za-z]', '%%%0')
end


------------------------------------------------------------------------------
-- Parse functions.
------------------------------------------------------------------------------

-- As a near-future step, it might be nice to factor all of these out so they
-- mainly rely on a single parsing mechanism.

function parse_statement(str)
  local or_parsers = {parse_assign, parse_for, parse_print}
  return parse_or_rule(str, 'statement', or_parsers)
end

function parse_assign(str)
  local or_parsers = {parse_std_assign, parse_inc_assign}
  return parse_or_rule(str, 'assign', or_parsers)
end

function parse_std_assign(str)
  local seq_parsers = {parse_var, parse_lit('='), parse_expr}
  return parse_seq_rule(str, 'std_assign', seq_parsers)
end

function parse_inc_assign(str)
  local seq_parsers = {parse_var, parse_lit('+='), parse_expr}
  return parse_seq_rule(str, 'inc_assign', seq_parsers)
end

function parse_expr(str)
  local or_parsers = {parse_var, parse_num}
  return parse_or_rule(str, 'expr', or_parsers)
end

parse_var = parse_re('[A-Za-z_][A-Za-z0-9_]*', 'var')

parse_num = parse_re('[1-9][0-9]*', 'num')

function parse_for(str)
  local seq_parsers = {parse_lit('for'), parse_var, parse_lit('='), parse_expr,
                       parse_lit('to'), parse_expr, parse_lit(':'), parse_statement}
  return parse_seq_rule(str, 'for', seq_parsers)
end

function parse_print(str)
  local seq_parsers = {parse_lit('print'), parse_expr}
  return parse_seq_rule(str, 'print', seq_parsers)
end


------------------------------------------------------------------------------
-- Tree execution functions.
------------------------------------------------------------------------------

-- I decided to split this into per-tree-type functions because this is more
-- like the ultimate structure of a pumba runtime system.

-- For the current type of expressions, we can have all executions
-- return a number and nothing else.

function exec_tree(tree)
  local fn_of_type = {sum = exec_sum, prod = exec_prod, num = exec_num}
  return fn_of_type[tree.type](tree)
end

-- The functions below here are type-specific.
-- They expect their input to have a given type.

function exec_sum(sum_tree)
  local s = 0
  for _, subtree in ipairs(sum_tree.kids) do
    s = s + exec_tree(subtree)
  end
  return s
end

function exec_prod(prod_tree)
  local p = 1
  for _, subtree in ipairs(prod_tree.kids) do
    p = p * exec_tree(subtree)
  end
  return p
end

function exec_num(num_tree)
  return num_tree.value
end


------------------------------------------------------------------------------
-- Debug functions.
------------------------------------------------------------------------------

function pr(obj, indent)
  indent = indent or ''
  if type(obj) ~= 'table' then
    print(indent .. tostring(obj))
    return
  end
  for k, v in pairs(obj) do
    io.write(indent)
    if type(v) == 'table' then
      print(k .. ':')
      pr(v, '  ' .. indent)
    else
      print(string.format('%-6s = ', k) .. tostring(v))
    end
  end
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
  print('line:')
  print(line)
  local tree, tail = parse_statement(line)
  print('')
  print('tree:')
  pr(tree)
  print('tail:')
  pr(tail)
  --print('exec value:')
  --print(exec_tree(tree))
  print('')
end
f:close()
