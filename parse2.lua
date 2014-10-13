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
an abstract syntax tree of the form {name, (kids|value)}, and tail is
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
  local tree = {name = rule_name, kids={}}
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
  local tree = {name = rule_name, kids = {}}
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
  local re = '^%s*(' .. escaped_lit(lit_str) .. ')'
  return function(str)
    local s, e, val = str:find(re)
    if s == nil then return 'no match', str end
    return {name = name, value = val}, str:sub(e + 1)
  end
end

function parse_re(re_str, name)
  name = name or '<re>'
  local re_list = {}
  for re_item in re_str:gmatch('[^|]+') do
    re_list[#re_list + 1] = '^%s*(' .. re_item .. ')'
  end
  return function(str)
    for _, re in ipairs(re_list) do
      local s, e, val = str:find(re)
      if s then return {name = name, value = val}, str:sub(e + 1) end
    end
    return 'no match', str
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

parse_num = parse_re('0|[1-9][0-9]*', 'num')

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

-- I decided to split this into per-tree-name functions because this is more
-- like the ultimate structure of a pumba runtime system.

-- For the current type of expressions, we can have all executions
-- return a number and nothing else.

function exec_tree(tree)
  local fn_of_name = {sum = exec_sum, prod = exec_prod, num = exec_num}
  return fn_of_name[tree.name](tree)
end

-- The functions below here are name-specific.
-- They expect their input to have a given name.

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

-- This is designed for general Lua values. Anything goes.
-- The function pr_tree below is better for printing trees.
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

function pr_tree(tree, indent, this_indent)
  indent = indent or ''
  io.write(this_indent or indent)
  if tree.name == '<lit>' then
    print("'" .. tree.value .. "'")
    return
  end
  if tree.value then
    print(tree.name .. ' ' .. tree.value)
    return
  end
  if #tree.kids == 1 then
    io.write(tree.name .. ' - ')
    return pr_tree(tree.kids[1], indent, '')
  end
  -- At this point, the tree must have multiple kids to print.
  print(tree.name)
  for _, kid in ipairs(tree.kids) do
    pr_tree(kid, indent .. '  ')
  end
end

function first_line(str)
  next_newline = str:find('\n') or #str + 1
  return str:sub(1, next_newline - 1)
end

indent = ''

function wrap_metaparse_fn(metaparse_fn_name)
  local metaparse_fn = _G[metaparse_fn_name]
  _G[metaparse_fn_name] = function (str, rule_name, subparsers)
    indent = indent .. '  '
    print(indent .. rule_name .. ' attempting from ' .. first_line(str))
    local tree, tail = metaparse_fn(str, rule_name, subparsers)
    print(indent .. rule_name .. (tree == 'no match' and ' failed' or ' succeeded'))
    indent = indent:sub(1, #indent - 2)
    return tree, tail
  end
end

-- Turn this on or off to control how verbose parsing is.
--wrap_metaparse_fn('parse_or_rule')
--wrap_metaparse_fn('parse_seq_rule')


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
  print('')
  print('line:')
  print(line)

  local tree, tail = parse_statement(line)

  print('')
  print('tree:')
  pr_tree(tree)

  print('')
  print('tail:')
  pr(tail)

  --print('exec value:')
  --print(exec_tree(tree))
  --print('')
end
f:close()
