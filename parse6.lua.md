#!/usr/local/bin/lua
--[[

# parse6.lua.md

*This file is designed to be read after being processed as markdown.*

Usage:

    ./parse6.lua.md 03.input

This file is a first step toward parsing grammars. It is able to parse the
simple grammar of `03.input`, and prints out the resulting parse tree.

In working on this script, I realized that the current setup would already
benefit from parse modes in order to nicely parse strings. I'm also getting
some experience to help decide which syntax elements can work at this low
level versus which may fit better at a higher level of abstraction.
For example, I suspect that star-subrules and question-mark-subrules
can fit at this low level --
these are subrules, aka items, on the right side of a rule definition,
that may expand to either zero-or-more or zero-or-one instances of a
given subrule. However, I think it's more net work to allow both
or-rules and seq-rules to be one-liners than it is to force them to
be syntactically different at this level. More specifically, I'm
leaning toward forcing or-rules to be one-liners and seq-rules to
be multiline and indent-based.

--]]


------------------------------------------------------------------------------
-- Settings.
------------------------------------------------------------------------------

    -- This turns on or off printing from within the run framework.
    local do_run_dbg_print = false

    -- This turns on or off printing of good/bad rule parsing attempts.
    local do_mid_parse_dbg_print = false

    -- This turns on or off printing debug info about parsing.
    local do_post_parse_dbg_print = true

------------------------------------------------------------------------------
-- Grammar data.
------------------------------------------------------------------------------

    -- rules[rule_name] = rule_data.
    -- A rule has at least the keys {kind, items}, where kind is either 'or' or
    -- 'seq', and the items are either rule names, a 'literal', or a "regex".

    -- Later, runnable rules also receive `run` keys. A run key is required for
    -- `seq` rules but is optional for `or` rules.

    local rules = {
      ['statement'] = {kind = 'or', items = {'rules_start', 'rule'}},
      ['rules_start'] = {kind = 'seq', items = {[['>']], "'\n'"}},
      ['rule'] = {kind = 'seq', items = {'rule_name', "'-->'",
                                         'rule_items', "'\n'"}},
      -- This rule is designed so that single-subrules will be treated as
      -- or-rules by default. The advantage of that would be the automatic
      -- delegation of method calls to the subrule. However, since I now plan to
      -- use simpler syntax to differentiate between or-rules and seq-rules,
      -- this concern will no longer be relevant.
      ['rule_items'] = {kind = 'or',
                        items = {'multi_or_items',
                                 'seq_items',
                                 'single_or_item'}},
      ['single_or_item'] = {kind = 'seq', items = {'rule_name'}},
      ['multi_or_items'] = {kind = 'seq',
                            items = {'basic_item',
                                     'or_and_item',
                                     'or_and_item*'}},
      ['seq_items'] = {kind = 'or', items = {'multi_seq_items',
                                             'single_seq_item'}},
      ['multi_seq_items'] = {kind = 'seq', items = {'item', 'item*'}},
      ['single_seq_item'] = {kind = 'or', items = {'literal', 'regex'}},
      ['or_and_item'] = {kind = 'seq', items = {"'|'", 'basic_item'}},
      ['literal'] = {kind = 'seq', items = {[["'[^']*'"]]}},
      -- Future: Fix regular expression parsing in a future parseX script.
      ['regex'] = {kind = 'seq', items = {[[""[^ ]*" "]]}},
      ['rule_name'] = {kind = 'seq', items = {[["[A-Za-z_][A-Za-z0-9_]*"]]}},
      ['item'] = {kind = 'or', items = {'star_item', 'basic_item'}},
      ['basic_item'] = {kind = 'or', items = {'literal', 'regex', 'rule_name'}},
      ['star_item'] = {kind = 'seq', items = {'basic_item', [['*']]}}
    }

    -- Add a 'name' key to each rule so that it can be passed around as a
    -- self-contained object.
    for name, rule in pairs(rules) do rule.name = name end


------------------------------------------------------------------------------
-- Metaparse functions.
------------------------------------------------------------------------------

    -- By default, we parse the 'statement' rule.
    function parse(str)
      return parse_rule(str, 'statement')
    end

    function parse_rule(str, rule_name)
      --print('parse_rule, rule_name = "' .. rule_name .. '"')
      if rule_name:sub(1, 1) == "'" then
        return parse_literal(str, rule_name:sub(2, #rule_name - 1))
      elseif rule_name:sub(1, 1) == '"' then
        return parse_regex(str, rule_name:sub(2, #rule_name - 1))
      elseif rule_name:sub(#rule_name, #rule_name) == '*' then
        local rule = rules[rule_name:sub(1, #rule_name - 1)]
        return parse_star_rule(str, rule)
      end
      local rule = rules[rule_name]

      if rule == nil then
        print('Error in internal grammar! missing rule: ' .. rule_name)
        os.exit(1)
      end

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
      --print('parse_literal(' .. str .. ', ' .. lit_str .. ')')
      local re = '^ *(' .. escaped_lit(lit_str) .. ')'
      --print('re=' .. re)
      local s, e, val = str:find(re)
      --print('s, e, val = ', s, e, val)
      if s == nil then return 'no match', str end
      return {name = '<lit>', value = val}, str:sub(e + 1)
    end

    function parse_regex(str, full_re)
      local re_list = {}
      for re_item in full_re:gmatch('[^|]+') do
        re_list[#re_list + 1] = '^ *(' .. re_item .. ')'
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

    function print_metaparse_info(fn_name, fn, str, rule_name)
      indent = indent .. '  '
      --io.write(indent .. fn_name .. ': ')
      print(indent .. rule_name .. ' attempting from ' .. first_line(str))
      local tree, tail = fn()
      print(indent .. rule_name .. (tree == 'no match' and ' failed' or ' succeeded'))
      indent = indent:sub(1, #indent - 2)
      return tree, tail
    end

    function wrap_metaparse_fn(metaparse_fn_name)
      local metaparse_fn = _G[metaparse_fn_name]
      _G[metaparse_fn_name] = function (str, rule)
        local fn = function() return metaparse_fn(str, rule) end
        return print_metaparse_info(metaparse_fn_name, fn, str, rule.name)
      end
    end

    -- Turn this on or off to control how verbose parsing is.
    --wrap_metaparse_fn('parse_or_rule')
    --wrap_metaparse_fn('parse_seq_rule')

    if do_mid_parse_dbg_print then
      local original_parse_rule = parse_rule
      parse_rule = function (str, rule_name)
        local fn = function () return original_parse_rule(str, rule_name) end
        return print_metaparse_info('parse_rule', fn, str, rule_name)
      end
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
      elseif do_post_parse_dbg_print then
        pr_tree(tree)
      end

      if do_parse_dbg_print then
        pr_line_values(src, tree, tail)
      end

      -- R:run(tree)

      statement_num = statement_num + 1
      src = tail

    end
