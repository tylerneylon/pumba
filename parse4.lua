#!/usr/local/bin/lua
-- parse4.lua
--
-- Usage:
--   ./parse4.lua <input_file>
--
-- This script can parse the same simple language as parse2. The difference is
-- that this script is written so that the grammar is more like data than code.
-- This is a stepping stone toward an open compiler which parses grammar along
-- the way.
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
-- Metaparse variables.
------------------------------------------------------------------------------

-- rules[rule_name] = rule_data.
-- A rule has at least the keys {kind, items}, where kind is either 'or' or
-- 'seq', and the items are either rule names, a 'literal', or a "regex".
local rules = {}


------------------------------------------------------------------------------
-- Metaparse functions.
------------------------------------------------------------------------------

-- By default, we parse the 'statement' rule.
function parse(str)
  return parse_rule(str, 'statement')
end

function parse_rule(str, rule_name)
  if rule_name:sub(1, 1) == "'" then
    return parse_literal(str, rule_name:sub(2, #rule_name - 1))
  elseif rule_name:sub(1, 1) == '"' then
    return parse_regex(str, rule_name:sub(2, #rule_name - 1))
  end
  local rule = rules[rule_name]
  if rule.kind == 'or' then
    return parse_or_rule(str, rule)
  elseif rule.kind == 'seq' then
    return parse_seq_rule(str, rule)
  else
    error('Unknown rule kind: ' .. tostring(rule.kind))
  end
end

function parse_or_rule(str, rule)
  local tree = {name = rule.name, kind = 'or', kids={}}
  for _, subrule in ipairs(rule.items) do
    local subtree, tail = parse_rule(str, subrule)
    if subtree ~= 'no match' then
      tree.kids[#tree.kids + 1] = subtree
      return tree, tail
    end
  end
  return 'no match', str
end

function parse_seq_rule(str, rule)
  local tree = {name = rule.name, kind = 'seq', kids = {}}
  local subtree, tail = nil, str
  for _, subrule in ipairs(rule.items) do
    subtree, tail = parse_rule(tail, subrule)
    if subtree == 'no match' then return 'no match', str end
    tree.kids[#tree.kids + 1] = subtree
  end
  if #tree.kids == 1 then tree.value = tree.kids[1].value end
  return tree, tail
end

function parse_literal(str, lit_str)
  local re = '^%s*(' .. escaped_lit(lit_str) .. ')'
  local s, e, val = str:find(re)
  if s == nil then return 'no match', str end
  return {name = '<lit>', value = val}, str:sub(e + 1)
end

function parse_regex(str, full_re)
  local re_list = {}
  for re_item in full_re:gmatch('[^|]+') do
    re_list[#re_list + 1] = '^%s*(' .. re_item .. ')'
  end
  for _, re in ipairs(re_list) do
    local s, e, val = str:find(re)
    if s then return {name = '<re>', value = val}, str:sub(e + 1) end
  end
  return 'no match', str
end

function escaped_lit(lit_str)
  return lit_str:gsub('[^A-Za-z]', '%%%0')
end


------------------------------------------------------------------------------
-- Grammar as data.
------------------------------------------------------------------------------

rules = {
  ['statement']  = {kind = 'or',  items = {'assign', 'for', 'print'}},
  ['assign']     = {kind = 'or',  items = {'std_assign', 'inc_assign'}},
  ['std_assign'] = {kind = 'seq', items = {'var', "'='", 'expr'}},
  ['inc_assign'] = {kind = 'seq', items = {'var', "'+='", 'expr'}},
  ['expr']       = {kind = 'or',  items = {'var', 'num'}},
  ['var']        = {kind = 'seq', items = {'"[A-Za-z_][A-Za-z0-9_]*"'}},
  ['num']        = {kind = 'seq', items = {'"0|[1-9][0-9]*"'}},
  ['for']        = {kind = 'seq', items = {"'for'", 'var', "'='", 'expr',
                                           "'to'", 'expr', "':'", 'statement'}},
  ['print']      = {kind = 'seq', items = {"'print'", 'expr'}},
}

-- Add a 'name' key to each rule so that it can passed around as a
-- self-contained object.
for name, rule in pairs(rules) do rule.name = name end

-- What values are in scope in an exec block?
-- tree, gl, lo = a new stack deep copy (make it a shallow copy later)

--[[


Here's my current plan for the pattern of interally-used exec functions.

val = exec_fn(tree, global, frame, local)

The global, frame, and local tables all map variable names to values.

The global table is always a flat (metatable-free) table that anyone
can edit and see.

The frame table reveals keys set either as locals higher in the stack
or as globals. New keys added here are set as globals.

The local table is only visible within this exec_fn call, and to
recursively-called exec functions. Callees will see these values both
in the local and frame tables.

Here's how each can be implemented:

* `global` is a flat table. Easy.

* `local` is a stacked table where all assignments are only visible
  at this stack level or in recursive calls, while lookups can
  see closest-scope values. This means that the immediate value of
  `local` starts as an empty table, and failed index lookups are
  delegated to frame.

* `frame` is a stacked table, also empty at the immediate level.
  Lookups are delegated to the frame from the caller's stack level,
  which ends with the global table. Key assignments affect the highest-level
  where the key exists; if it doesn't exist anywhere, the assignment
  affects the global table.

The intended usage is, from Lua's perspective:

* For an assigment like "x = 3", implement it as "frame.x = 3".
* For an assigment like "local x = 3", implement it as "local.x = 3".

I expect the vast majority of rvalues to be from local and the vast
majority of lvalues to be from either frame or local. The global table is
sent in to support cases where the language might support explicit scoping
jumps to the global level. I could consider cleaning up the interface, eg,
by giving everyone a `scope` table with keys `global`, `frame`, and `local`,
although I'm not happy about that making the code more verbose.

Variable hoisting, as in JavaScript, is probably tricky to implement.
That's ok because it's weird.

How can closures work? It's difficult to anticipate the design decisions
between here and a full implementation of closures, but I'm guessing that
the user can make a table of upvalues (that is, of variables that would
normally disappear but are held by held by the function) from the frame
table. Lua's garbage collection plays nicely with this mechanic.

---

Ok, I am revising the above design a bit. We'll have in scope the following:

* `global` is a flat table as above.

* `frame` is a stacked table where rvalues look up through the stack and
  lvalues are assigned to either the nearest existing entry with the given
  key, or are placed in new keys at the current stack level if the key is
  new at every level. Intuitively, this matches Lua's behavior for an
  assigment like "x = 3".

The biggest change is that there is no `local` table. I realized that the
only job `local` performed differently than `frame` was to allow new local
variables to shadow existing higher-level variables of the same name. In
order to keep that functionality, we could use some other setup, such as
a new_local function that you call like so `new_local(var_name, value)`, where
`var_name` is a string; implementation-wise, this would be like calling
`rawset(frame, var_name, value)`.

It could be `P:new_local` so that it can have access to the frame and any
other related state for the current execution without internally using locals.
So `global` and `frame` would be `P.global` and `P.frame`.

--]]

--[[

TODO A future iteration can try to make the kid-reference syntax more intuitive.
     For example, maybe enable names like tree.kids.expr and tree.kids.var as
     part of a parsed `std_assign` string.

--]]

rules['std_assign'].run = [[
  R.frame[value(tree.kids[1])] = R:run(tree.kids[3])
]]

rules['inc_assign'].run = [[
  local var = value(tree.kids[1])
  R.frame[var] = R.frame[var] + R:run(tree.kids[3])
]]

rules['var'].run = [[
  return R.frame[tree.value]
]]

rules['num'].run = [[
  return tonumber(tree.value)
]]

rules['for'].run = [[
  local min, max = R:run(tree.kids[4]), R:run(tree.kids[6])
  R:push_scope()
  local var_name = value(tree.kids[2])
  R:new_local(var_name, min)
  for i = min, max do
    R.frame[var_name] = i
    R:run(tree.kids[8])
  end
  R:pop_scope()
]]

rules['print'].run = [[
  print(R:run(tree.kids[2]))
]]

------------------------------------------------------------------------------
-- Tree running functions.
------------------------------------------------------------------------------

-- This sets the given key-value pair at the closest level where the key
-- exists; if it is new key at all levels, it's created at the current level.
function frame_set(frame, key, val)
  if not frame.key or rawget(frame, key) then
    rawset(frame, key, val)
  else
    frame_set(getmetatable(frame).up, key, val)
  end
end

local Run = {}

function Run:new()
  local run = {}
  run.global = {}
  run.frame = run.global
  self.__index = self
  return setmetatable(run, self)
end

function Run:push_scope()
  local meta = {__index = self.frame, up = self.frame, __newindex = frame_set}
  self.frame = setmetatable({}, meta)
end

function Run:pop_scope()
  self.frame = getmetatable(self.frame).up
end

function Run:new_local(name, val)
  rawset(self.frame, name, val)
end

function Run:run(tree)
  -- TODO HERE Implement the value function and then this run function.
  -- This run function should basically wrap rules[tree.name].run in a
  -- Lua function definition, loadstring and then execute it with
  -- self->R and tree->tree as parameters.
  --
  -- Debug by often printing out the frame, with transparency into what's
  -- at each level.
end

function run(tree)
  local R = Run:new()
  return R:run(tree)
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

function exec(tree, gl, lo)
  if tree.kind == 'or' then
    return exec(tree.kids[1], gl, lo)
  end
  local rule = rules[tree.name]
  if rule.exec == nil then
    error('Expected rule "' .. tree.name .. '" to have an exec value.')
  end
end


-- Old exec functions are below.

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
--wrap_metaparse_fn('parse_rule')

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

  -- Turn these lines on or off to toggle printing variable values after each
  -- statement is executed.
  ---[[
  print('')
  print('gl:')
  pr(gl)

  print('')
  print('lo:')
  pr(lo)

  print('')
  print('exec value:')
  print(lo.val)
  --]]

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

  local tree, tail = parse(line)
  gl, lo = exec_tree(tree, gl, lo)

  -- Uncomment the following line to print out some
  -- interesting per-line values.
  --pr_line_values(line, tree, tail, gl, lo)

end
f:close()
