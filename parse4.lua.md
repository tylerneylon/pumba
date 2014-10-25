#!/usr/local/bin/lua
--[[

# parse4.lua

*This file is designed to be read after being processed as markdown.*

Usage:

    ./parse4.lua.md <input_file>

This script can parse the same simple language as `parse2.lua`. The difference is
that this script is written so that both the grammar specification and the
corresponding code are provided more like data than code.



Here is an informal description of the grammar:

    statement -> assign | for | print

    assign     -> std_assign | inc_assign
    std_assign -> var  '=' expr
    inc_assign -> var '+=' expr

    expr       -> var | num
    var        -> "[A-Za-z_][A-Za-z0-9_]*"
    num        -> "[1-9][0-9]*"

    for       -> 'for' var '=' expr 'to' expr ':' statement

    print     -> 'print' expr

## How the grammar is formally specified

The grammar is kept in a global table called `rules`.
Each `rules` key is a rule name, and each value is a table
giving the details of the rule.
Below are the keys used by each rule:

| key     | meaning                                       |
|---------|-----------------------------------------------|
| `name`  | name of the rule - same as the `rules` key    |
| `kind`  | either `or` or `seq`                          |
| `items` | an array of metarules to parse; details below |
| `run`   | code to run the parsed tree; details below    |

## Metarules

There are three types of metarules:

1. Any standard token is treated as the name of a rule given
   in the `rules` table.
2. Anything inside single quotes `'like_this'` is considered a
   direct string literal to be matched character-for-character.
3. Anything inside double quotes `"like this"` is considered a
   pumba pattern, which is a regular expression with only
   limited support for the `|` special character.

## Parse function style

On success, the `parse(str)` function returns `tree, tail`, where `tree` is an
abstract syntax tree of the form `{name, kind, (kids|value)}`, and `tail` is the
unparsed portion of the string.

On failure, `parse(str)` returns `'no match', tail`, where `tail` is the full string
given as input.

## Run function style

The high-level execution is run as:

    R:run(tree)

where R is a run state set up as

    R = Run:new()

and is designed to be used for many consecutive trees.

## API for run code

Run code has access to several parameters and functions
listed here.

The `R` table itself is the run state of the current program.
This table is meant to encapsulate the entire state of the program,
including any representation of a stack, heap, symbol table, etc.
How this interacts with a finish compiled program will evolve as
pumba itself evolves.

Here is a list of the currently existing functions or tables and
how to use each one.

### `R.frame` and `R.global`

This table holds the entire run stack and provides support for
nested variable scopes. Here are the primary typical operations you
can perform with `R.frame`:

* `x = R.frame[varname]` - This is a lookup of whatever variable is
  in the current scope with name `varname`. This returns `nil` without
  error if no such variable is in scope.
* `R.frame[varname] = x` - This assigns `x` to `varname` at whatever
  scope `varname` currently exists. If `varname` is new, it is created
  as a new variable at the local scope.

There are two cases not handled by these defaults:

1. Explicitly create or read from a global. This can be performed
   via `R.global[varname] = x` for creating/setting a value, or via
   `x = R.global[varname]` for reading a value.

2. Create a new local that shadows an existing same-name variable
   that's outside the current local frame. This can be performed
   via `R:new_local(varname, x)`, which assigns value `x` to the
   local variable `varname`.

### `R:push_scope` and `R:pop_scope`

These functions push and pop the current scope of all variables.
An example illustrates how these work:

    R = Run:new()
    R.frame.x = 3
    R.frame.y = 5

    R:push_scope()

    print(R.frame.x)  --> 3
    print(R.frame.y)  --> 5

    R:new_local('x', 7)
    R.frame.y = 9

    print(R.frame.x)  --> 7
    print(R.frame.y)  --> 9

    R:pop_scope()

    print(R.frame.x)  --> 3
    print(R.frame.y)  --> 9

--]]


------------------------------------------------------------------------------
-- Grammar data.
------------------------------------------------------------------------------

    -- rules[rule_name] = rule_data.
    -- A rule has at least the keys {kind, items}, where kind is either 'or' or
    -- 'seq', and the items are either rule names, a 'literal', or a "regex".

    -- Later, runnable rules also receive `run` keys. A run key is required for
    -- `seq` rules but is optional for `or` rules.

    local rules = {
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

--[[

####TODO

A future iteration can try to make the kid-reference syntax more intuitive.
For example, maybe enable names like `tree.kids.expr` and `tree.kids.var` as
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
-- Tree running functions.
------------------------------------------------------------------------------

    -- This sets the given key-value pair at the closest level where the key
    -- exists; if it is new key at all levels, it's created at the current level.
    function frame_set(frame, key, val)
      if frame[key] == nil or rawget(frame, key) ~= nil then
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
      local run_tree, code = run_code(tree)
      code = 'local R, tree = ...\n' .. code
      local fn = loadstring(code, '<' .. run_tree.name .. '>')
      return fn(self, run_tree)
    end

    -- In the future, I'm guessing this function will have to be both better-
    -- defined and more sophisticated. Intuitively, I want it to pull out the
    -- string that became this tree, but without a whitespace prefix.
    function value(tree)
      if tree.value then return tree.value end
      return value(tree.kids[1])
    end

    -- This function is meant to be called as in:
    -- run_tree, code = run_code(tree)
    -- The returned code may be wrapped and executed on the returned run_tree.
    function run_code(tree)
      if rules[tree.name].run then
        return tree, rules[tree.name].run
      end
      if tree.kind =='or' then
        return run_code(tree.kids[1])
      end
      error('Encountered non-or rule with no run code: ' .. tree.name)
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
    local R = Run:new()

    --local gl, lo = {}, {}
    local statement_num = 1
    for line in f:lines() do

      local tree, tail = parse(line)
      R:run(tree)

      -- Uncomment the following line to print out some
      -- interesting per-line values.
      --pr_line_values(line, tree, tail, gl, lo)

      statement_num = statement_num + 1

    end
    f:close()
