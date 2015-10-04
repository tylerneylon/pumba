#!/usr/local/bin/lua
--[[

# parse7.lua.md

*This file is designed to be read after being processed as markdown.*

Usage:

    ./parse7.lua.md 02.input

This file is a step toward adding modes to grammars and parsing.

It's not done yet.

-- TODO Update these comments once this file is fully implemented.

-- TODO NEXT Move down the rule initialization; add run code to pop into
             str mode for regex's; add rules for str mode.

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
-- Grammar data (to be replaced by a new version below).
------------------------------------------------------------------------------

    -- rules[rule_name] = rule_data.
    -- A rule has at least the keys {kind, items}, where kind is either 'or' or
    -- 'seq', and the items are either rule names, a 'literal', or a "regex".

    -- Later, runnable rules also receive `run` keys. A run key is required for
    -- `seq` rules but is optional for `or` rules.

    -- TODO Be able to parse modes.

    -- all_rules[<mode>] = {<rule_name> = {kind, items, name}}
    -- The global mode has the key '<global>'.
    local all_rules = {}

    -- Set up the global rules.

    all_rules['<global>'] =
      phrase = {kind = 'or', items = {'statement'}}
      statement = {kind = 'or', items = {'rules_start', 'rule'}},
      rules_start = {kind = 'seq', items = {[['>']], "'\n'"}},
      rule = {kind = 'seq', items = {'rule_name', "'-->'",
                                         'rule_items', "'\n'"}},
      rule_items = {kind = 'or', items = {'or_items', 'seq_items'}
      or_items = {kind = 'seq', items = {'basic_item', 'or_and_item*', "'\n'"}}
      seq_items = {kind = 'seq', items = {"'\n'", 'item', 'item*', "'\n'"}}
      basic_item = {kind = 'or', items = {'literal', 'regex', 'rule_name'}},
      or_and_item = {kind = 'seq', items = {"'|'", 'basic_item'}},
      item = {kind = 'or', items = {'star_item',
                                    'question_item',
                                    'basic_item'}},
      literal = {kind = 'seq', items = {[["'[^']*'"]]}},
      -- Future: Fix regular expression parsing in a future parseX script.
      regex = {kind = 'seq', items = {[[""[^ ]*" "]]}},
      rule_name = {kind = 'seq', items = {[["[A-Za-z_][A-Za-z0-9_]*"]]}},
      star_item = {kind = 'seq', items = {'basic_item', [['*']]}},
      question_item = {kind = 'seq', items = {'basic_item', [['?']]}}
    }

    -- Add a 'name' key to each rule so that it can be passed around as a
    -- self-contained object.
    for name, rule in pairs(all_rules['<global>']) do rule.name = name end

--[[

I'm working on the way modes will be pushed from a rule.

Intuitively, it makes sense that a rule can have two major methods: one is an
way to execute the parsed rule, another is a way to evaluate the rule as an
expression. I could theoretically combine these, but I think the overall
simplicity is greater if I keep them separate.

The result of an execution could be a parse tree. This way, an execution can be
a place to hook the parsing process and perform customized work. An alternative
design could be to pass in a writeable reference to the parse tree, so that it
could be changed, but also so that it could be safely ignored. Which choice is
better may emerge with more experience. For now I'll return the parse tree.

The result of an evaluation is conceptually a value in the language. For
example, the parsed string `3.141f` in C would have a value of type `float` and
the numeric value closest to 3.141 that can be represented in the corresponding
binary format. It's ultimately up to the language designer to choose exactly how
to represent values at this level.

I can also imagine having automated `src` and `prefix` methods that would act in
such a way that the concatenation of `prefix + src` for all parse trees would
give back exactly the original source code. The separation of `prefix` would
make it easier to use `src` as a way to perform secondary actions without
having to worry about preceding whitespace, which was a common case in project
water.

TODO: I decided now is a good time to start working with a Parser instance
      called `P`. This will be a good complement to the Runner `R`, and will be
      a convenient single parameter to pass into parse-aware functions.
      In particular, this will give me a good single place to call something
      like `push_mode` and `parse_till_mode_pop`.

In the future I may consider renaming `P` and `R` to `parser` and `runner`, as
those are more descriptive names. I can also imagine eventually getting a
`T` or `tree` parameter, similar to that used in `parse5`.

--]]

    all_rules['<global>'].regex.run = [[
      rules.push_mode('str')
      -- TODO HERE somehow parse until the mode is popped and return that
    ]]

    -- TODO Ensure that our parser will run this run code as expected and use
    --      the result to replace the effective parse tree.


------------------------------------------------------------------------------
-- The Parser class.
------------------------------------------------------------------------------

    local Parser = {all_rules = {}, rules = {}}

    function Parser:new()
      assert(self)
      local parser = {}
      self.__index = self
      return setmetatable(parser, self)
    end

    function Parser:push_mode(mode_name)
      assert(self and mode_name)
      -- We can't alter the metatables of self.all_rules[mode_name] since a
      -- single mode may end up on the stack at multiple levels.
      local mode_rules = self.all_rules[mode_name]
      local meta = {
        __index = function (tbl, key)
          local v = mode_rules[key]
          if v ~= nil then return v end
          return self.rules[key]
        end,
        up = self.rules
      }
      self.rules = setmetatable({}, meta)
    end

    function Parser:pop_mode()
      assert(self)
      self.rules = getmetatable(self.rules).up
    end

    function Parser:parse(str)
      return self:parse_rule(str, 'phrase')
    end

    function Parser:parse_rule(str, rule_name)
      local last_char = rule_name:sub(#rule_name, #rule_name)
      --print('parse_rule, rule_name = "' .. rule_name .. '"')
      if last_char == "'" then
        return parse_literal(str, rule_name:sub(2, #rule_name - 1))
      elseif last_char == '"' then
        return parse_regex(str, rule_name:sub(2, #rule_name - 1))
      elseif last_char == '*' or last_char == '?' then
        local rule = self.rules[rule_name:sub(1, #rule_name - 1)]
        return self:parse_multi_rule(str, rule, last_char)
      end

      -- Try to treat it as a basic rule name.
      local rule = self.rules[rule_name]
      if rule == nil then
        print('Error in internal grammar! missing rule: ' .. rule_name)
        os.exit(1)
      end
      if rule.kind == 'or' then
        return self:parse_or_rule(str, rule)
      elseif rule.kind == 'seq' then
        return self:parse_seq_rule(str, rule)
      else
        error('Unknown rule kind: ' .. tostring(rule.kind))
      end
    end

    function Parser:parse_or_rule(str, rule)
      local tree = {name = rule.name, kind = 'or', kids={}}
      for _, subrule in ipairs(rule.items) do
        local subtree, tail = self:parse_rule(str, subrule)
        if subtree ~= 'no match' then
          tree.kids[#tree.kids + 1] = subtree
          return tree, tail
        end
      end
      return 'no match', str
    end

    function Parser:parse_seq_rule(str, rule)
      local tree = {name = rule.name, kind = 'seq', kids = {}}
      local subtree, tail = nil, str
      for _, subrule in ipairs(rule.items) do
        subtree, tail = self:parse_rule(tail, subrule)
        if subtree == 'no match' then return 'no match', str end
        tree.kids[#tree.kids + 1] = subtree
      end
      if #tree.kids == 1 then tree.value = tree.kids[1].value end
      return tree, tail
    end

    function Parser:parse_multi_rule(str, rule, last_char)
      local tree_kind = (last_char == '*' and 'star' or 'question')
      local tree = {name = last_char .. rule.name, kind = tree_kind, kids = {}}
      local subtree, tail = nil, str
      while true do
        subtree, tail = self:parse_rule(tail, rule.name)
        if subtree == 'no match' then break end
        tree.kids[#tree.kids + 1] = subtree
        if last_char == '?' then break end  -- A ? rule takes at most one match.
      end
      return tree, tail
    end

    function Parser:parse_mode_till_popped(str, mode)
      local rules_when_done = self.rules
      self:push_mode(mode)
      local tree = {name = '<mode:' .. mode .. '>', kind = 'seq', kids = {}}
      repeat
        tree.kids[#tree.kids + 1], str = self:parse(str)
      until self.rules == rules_when_done
      return tree, str
    end

    function Parser:add_rules_to_mode(mode, new_rules)
      for rule_name, rule in pairs(new_rules) do
        rule.name = rule_name
        self.all_rules[mode].rule_name = rule
      end
    end

    local P = Parser:new()


------------------------------------------------------------------------------
-- Rules.
------------------------------------------------------------------------------

--[[

Here is the grammar I plan to set up, with global rules given first:

    phrase --> statement
    statement --> rules_start | rule
    rules_start -->
      '>' "'\n'"
    rule -->
      rule_name '-->' rule_items
    rule_items --> or_items | seq_items
    or_items -->
      basic_item or_and_item* "'\n'"
    seq_items -->
      "'\n'" item item* "'\n'"
    basic_item --> literal | regex | rule_name
    or_and_item -->
      '|' basic_item
    item --> star_item | question_item | basic_item
    literal -->
      "'[^']*'"
    regex -->
      '"' -str
    rule_name -->
      "[A-Za-z_][A-Za-z0-9_]*"
    star_item -->
      basic_item '*'
    question_item -->
      basic_item '?'

In writing this out, I realized that the initial global rule set makes the most
sense as something small. In particular, parsing of rules belongs in a mode, and
by default, we won't be in that mode. As an example of why this makes sense, the
current rule setup may see an isolated rule without an introductory `>` phrase,
and still parse that rule. That's bad behavior. It also feels cleaner if the
global rule set is extremely small to begin with.

Eventually, it would be nice to allow till-newline comments in grammar specs.

TODO Turn off whitespace prefixes in `str` mode.

Below are the rules in the `str` mode. The `|:` token indicates to pop the mode
if none of the previous or-rule items match.

    phrase --> escaped_char | regular_char |:
    escaped_char -->
      '\\' "."
    regular_char -->
      "[^\"]"

--]]

    P.add_rules_to_mode('<global>', {
      phrase      = { kind = 'or',  items = {'statement'} },
      statement   = { kind = 'or',  items = {'rules_start', 'rule'} },
      rules_start = { kind = 'seq', items = {"'>'", "'\n'"} }
      -- TODO HERE continue transferring the just-above comment rules here
    })

------------------------------------------------------------------------------
-- Metaparse functions.
------------------------------------------------------------------------------

    -- These functions may live outside of any Parser instance as they depend
    -- on nothing beyond the string and regex or literal handed to them. In
    -- contrast, parse methods in Parser care about the current context of
    -- named rules.

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

    -- This function is useful to allow explicit shadowing of a global with a
    -- local of the same name.
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
    local P = Parser:new()

    local statement_num = 1
    while not is_empty(src) do

      local tree, tail = P:parse(src)

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
