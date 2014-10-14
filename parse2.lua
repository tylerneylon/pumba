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

The general usage pattern is as follows:

    gl, lo = exec_<rule>(tree, gl, lo)

where gl are the globals and lo are the locals.

Internally, it is expected that each exec rule make a deep copy of lo
if it wants to modify it so that the Lua stack coincides with the
executed stack.

In the future, I'm interested in exploring this modified model:

    lo = exec(tree, gl, lo)

The changes are:

* It is understood that gl is meant to modified in place; don't return it.
* A global exec function ensures that rule-specific exec functions work
  with a copy of lo.

The main downside to this is the inefficiency of making a copy of lo.
Instead, we could use metatables to delegate lookups. This can work
the way we want since __newindex is called on a derived table even when
the key being written to exists in base table.

--]]


------------------------------------------------------------------------------
-- Metaparse functions.
------------------------------------------------------------------------------

function parse_or_rule(str, rule_name, or_parsers)
  local tree = {name = rule_name, kind = 'or', kids={}}
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
  local tree = {name = rule_name, kind = 'seq', kids = {}}
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
-- General utility functions.
------------------------------------------------------------------------------

-- This is an easy-case deep copy function. Cases it doesn't handle:
--  * recursive structures
--  * metatables
function copy(obj)
  if type(obj) ~= 'table' then return obj end
  local res = {}
  for k, v in pairs(obj) do res[copy(k)] = copy(v) end
  return res
end


------------------------------------------------------------------------------
-- Tree execution functions.
------------------------------------------------------------------------------

-- I decided to split this into per-tree-name functions because this is more
-- like the ultimate structure of a pumba runtime system.

-- For the current type of expressions, all executions accept and return
-- gl and lo tables, for globals and locals. The purpose of this is to make it
-- easy to integrate an executed stack with Lua's call stack for locals, while
-- also maintaining and passing around global state that is still not global
-- from Lua's perspective.

-- Within each exec function, treating lo as read-only will keep it in line
-- with Lua's stack. Any modifications can be returned in a copy.

-- The special value lo.val will hold the value of the last-evaluated
-- expression.

-- Set up fn_of_tree so that fn_of_tree[rule_name] = exec_fn, where
-- exec_fn is the function that knows how to execute the given rule name.
-- We'll set up this table after we define the functions it will refer to.
local fn_of_tree

function exec_tree(tree, gl, lo)
  if tree.kind == 'or' then
    return exec_tree(tree.kids[1], gl, lo)
  end
  return fn_of_tree[tree.name](tree, gl, lo)
end

function exec_std_assign(tree, gl, lo)
  local var_name = tree.kids[1].value
  local expr_lo
  gl, expr_lo = exec_tree(tree.kids[3], gl, lo)
  local rvalue = expr_lo.val
  -- All assignments, except for temporary for-loop variables, are global.
  gl[var_name] = rvalue
  return gl, lo
end

function exec_inc_assign(tree, gl, lo)
  local var_name = tree.kids[1].value
  local expr_lo
  gl, expr_lo = exec_tree(tree.kids[3], gl, lo)
  local rvalue = expr_lo.val
  -- It is undecided what should happen if the variable does not exist.
  -- sc = scope
  local sc = lo[var_name] and lo or gl
  sc[var_name] = sc[var_name] + rvalue
  return gl, lo
end

-- This retrieves the value of a variable.
function exec_var(tree, gl, lo)
  local lo_copy = copy(lo)
  -- If there's a local variable of the same name,
  -- that takes precedence over the global one.
  lo_copy.val = lo[tree.value] or gl[tree.value]
  return gl, lo_copy
end

function exec_num(tree, gl, lo)
  local lo_copy = copy(lo)
  lo_copy.val = tonumber(tree.value)
  return gl, lo_copy
end

function exec_for(tree, gl, lo)
  local lo_copy = copy(lo)
  local var_name = tree.kids[2].value
  local min_lo, max_lo
  gl, min_lo = exec_tree(tree.kids[4], gl, lo)
  gl, max_lo = exec_tree(tree.kids[6], gl, lo)
  local min, max = min_lo.val, max_lo.val
  for v = min, max do
    lo_copy[var_name] = v
    exec_tree(tree.kids[8], gl, lo_copy)
  end
  return gl, lo
end

function exec_print(tree, gl, lo)
  local expr_lo
  gl, expr_lo = exec_tree(tree.kids[2], gl, lo)
  print(expr_lo.val)
  return gl, lo
end

fn_of_tree = {std_assign = exec_std_assign,
              inc_assign = exec_inc_assign,
              var        = exec_var,
              num        = exec_num,
              ['for']    = exec_for,
              ['print']  = exec_print}


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

function pr_line_values(line, tree, tail, gl, lo)
  print('')
  print('line:')
  print(line)

  print('')
  print('tree:')
  pr_tree(tree)

  print('')
  print('tail:')
  pr(tail)

  print('')
  print('gl:')
  pr(gl)

  print('')
  print('lo:')
  pr(lo)

  print('')
  print('exec value:')
  print(lo.val)
  print('')
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
local gl, lo = {}, {}
for line in f:lines() do

  local tree, tail = parse_statement(line)
  gl, lo = exec_tree(tree, gl, lo)

  -- Uncomment the following line to print out some
  -- interesting per-line values.
  --pr_line_values(line, tree, tail, gl, lo)

end
f:close()
