#!/usr/local/bin/lua
--[[

# parse5.lua

*This file is designed to be read after being processed as markdown.*

Usage:

    ./parse5.lua.md 02.input

This script can parse a simple C-like language. I'm writing this to help learn
how to define functions and work with a symbol table.

Here is an informal description of the grammar:

    statement -> fn_def | fn_call

    fn_def -> type word '(' ')' '{' statement* '}'

    fn_call -> word '(' (expr[, expr]*)? ')' ';'

    type -> 'void'

    word -> "[A-Za-z_][A-Za-z0-9_]*"

    expr -> string

    string -> "\"[^\"]*\""

To focus on the running framework, I simplified the grammar of function call
parameters to simply `expr*` even though this is not how a typical
parameter list syntax would work.

--]]


------------------------------------------------------------------------------
-- Settings.
------------------------------------------------------------------------------

    -- This turns on or off printing from within the run framework.
    local do_run_dbg_print = false

    -- This turns on or off printing of good/bad rule parsing attempts.
    local do_mid_parse_dbg_print = false

    -- This turns on or off printing debug info about parsing.
    local do_post_parse_dbg_print = false

------------------------------------------------------------------------------
-- Grammar data.
------------------------------------------------------------------------------

    -- rules[rule_name] = rule_data.
    -- A rule has at least the keys {kind, items}, where kind is either 'or' or
    -- 'seq', and the items are either rule names, a 'literal', or a "regex".

    -- Later, runnable rules also receive `run` keys. A run key is required for
    -- `seq` rules but is optional for `or` rules.

    local rules = {
      ['statement'] = {kind = 'or',  items = {'fn_def', 'fn_call'}},
      ['fn_def']    = {kind = 'seq',
                       items = {'type', 'word', "'('", "')'", "'{'",
                                'statement*', "'}'"}},
      ['fn_call']   = {kind = 'seq',
                       items = {'word', "'('", 'expr*', "')'", "';'"}},
      ['type']      = {kind = 'seq', items = {"'void'"}},
      ['word']      = {kind = 'seq', items = {'"[A-Za-z_][A-Za-z0-9_]*"'}},
      ['expr']      = {kind = 'or',  items = {'string'}},
      ['string']    = {kind = 'seq', items = {'""[^"]*""'}}
    }

    -- Add a 'name' key to each rule so that it can be passed around as a
    -- self-contained object.
    for name, rule in pairs(rules) do rule.name = name end

    rules['fn_def'].run = [[
      local body_trees = tree.kids[6].kids
      R.frame[value(tree.kids[2])] = {kind = 'fn', body = body_trees}
    ]]

    rules['fn_call'].run = [[
      local fn_name = value(tree.kids[1])
      if fn_name == 'printf' then
        R:dbg_print('in printf')
        for _, expr_tree in ipairs(tree.kids[3].kids) do
          io.write(R:run(expr_tree))
        end
      else
        local fn = R.frame[fn_name]
        for _, statement_tree in ipairs(fn.body) do
          R:run(statement_tree)
        end
      end
    ]]

    rules['string'].run = [[
      R:dbg_print('in string run code, tree.value=' .. tostring(tree.value))
      local s = tree.value
      return s:sub(2, #s - 1):gsub('\\n', '\n')
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
      elseif rule_name:sub(#rule_name, #rule_name) == '*' then
        local rule = rules[rule_name:sub(1, #rule_name - 1)]
        return parse_star_rule(str, rule)
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

    function parse_star_rule(str, rule)
      local tree = {name = '*' .. rule.name, kind = 'star', kids = {}}
      local subtree, tail = nil, str
      while true do
        subtree, tail = parse_rule(tail, rule.name)
        if subtree == 'no match' then break end
        tree.kids[#tree.kids + 1] = subtree
      end
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
      local run  = {}
      run.global = {}
      run.frame  = run.global
      run.ind    = '..'  -- Used in debug printing.
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

    function Run:dbg_print(str)
      if not do_run_dbg_print then return end
      if str:sub(1, 1) == '}' then self.ind = self.ind:sub(3) end
      print(self.ind .. str)
      if str:sub(1, 1) == '{' then self.ind = '..' .. self.ind end
    end

    function Run:run(tree)
      self:dbg_print('{ run ' .. tree.name)

      local run_tree, code = run_code(tree)
      code = 'local R, tree = ...\n' .. code
      local fn = loadstring(code, '<' .. run_tree.name .. '>')
      local v = fn(self, run_tree)

      self:dbg_print('} run ' .. tree.name)
      return v
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

    -- Returns true if and only if str is either empty or all whitespace.
    function is_empty(str)
      return not not str:find('^%s*$')
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
      _G[metaparse_fn_name] = function (str, rule_name)
        indent = indent .. '  '
        print(indent .. rule_name .. ' attempting from ' .. first_line(str))
        local tree, tail = metaparse_fn(str, rule_name)
        print(indent .. rule_name .. (tree == 'no match' and ' failed' or ' succeeded'))
        indent = indent:sub(1, #indent - 2)
        return tree, tail
      end
    end

    -- Turn this on or off to control how verbose parsing is.
    --wrap_metaparse_fn('parse_or_rule')
    --wrap_metaparse_fn('parse_seq_rule')

    if do_mid_parse_dbg_print then
      wrap_metaparse_fn('parse_rule')
    end

    function pr_line_values(line, tree, tail)
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
    local src = f:read('*a')
    f:close()
    local R = Run:new()

    local statement_num = 1
    while not is_empty(src) do

      local tree, tail = parse(src)

      if tree == 'no match' then
        print('Parse failed at this point:')
        print(src)
        break
      end

      if do_parse_dbg_print then
        pr_line_values(src, tree, tail)
      end

      R:run(tree)

      statement_num = statement_num + 1
      src = tail

    end
