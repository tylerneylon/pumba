--[[

# parse7.lua.md

--]]


------------------------------------------------------------------------------
-- Introduction.
------------------------------------------------------------------------------

--[[

*This file is designed to be read after being processed as markdown.*

Usage:

    lua parse7.lua.md 04.input

### Modes

This file adds a major feature to grammars called *modes*. Every mode can
have its own completely independent grammar, or it can be designed to interact
with other grammars. For example, the grammar parsed by this script includes a
`regex` rule that parses string literals. Rather than writing a regular
expression to parse these string literals, I decided to use a mode. Below are
the relevant rules.

    # This sequential rule is in the global mode:

    regex -->
      '"' -str

The `-str` item instructs the parser to enter the mode called `str` until that
mode exits.

    # These rules make up the str mode:

    phrase --> escaped_char | regular_char | end_char
    escaped_char -->
      '\\' "."
    regular_char -->
      "[^\"]"
    end_char -->
      '"' <pop>

Recall that `phrase` is the default rule parsed repeatedly until either an error
occurs or the string being parsed is exhausted.
The `str` mode parses small character sequences at a time: either an escaped
character, a non-escaped non-quote character, or an ending quote. Notice the
special `<pop>` item at the end of the `end_char` rule. This instructs the
parser to exit the current mode after parsing an end quote, effectively
completing the `regex` rule. The word *pop* is used because modes are treated as
a stack; this mechanic is explained below.

In a sense, modes allow a grammar to treat an entire subgrammar as a single
parse item. I imagine this being useful for conceptually different parse modes
such as strings, comments, or for switching languages.

### Code changes

Outside of modes, the biggest change from `parse6` to this script is the
addition of the `Parser`
class, which acts as a central place to store changing parser data and to
promote consistency of this data. Previous parsing scripts only included a
`rules` table, but now the `Parser` instance also includes an `all_rules` table
which is indexed by the parse mode.

--]]


------------------------------------------------------------------------------
-- Settings.
------------------------------------------------------------------------------

--[[

These global settings make debugging easier. I personally use these while
debugging the scripts themselves, although I can imagine their usefulness
extending into the production use of pumba by others developing new grammars.
I hope to further improve the print format used by each value so the user sees
exactly the useful pieces of data in a small but visually pleasant layout.

--]]

    -- This turns on or off printing from within the run framework.
    local do_run_dbg_print = false

    -- This turns on or off printing of good/bad rule parsing attempts.
    local do_mid_parse_dbg_print = false

    -- This turns on or off printing debug info about parsing.
    local do_post_parse_dbg_print = true

    -- These are experimental prints to help with debugging. I hope to iterate
    -- on these statements to maximize their usefulness.
    local do_print_extras = false


------------------------------------------------------------------------------
-- The `Parser` class.
------------------------------------------------------------------------------

--[[

Now we're ready to define the `Parser` class.

I expect there to only be a single instance, so an alternative design would be
to expose the same interface as a set of functions that may access the
same set of global variables instead of methods accessing instance variables.
I prefer the class interface for a couple reasons:

* It's cleaner to keep the scope of our grammar data as small as possible. We
  could pass the grammar around as a parameter to functions, but it feels more
  natural to me for the grammar to be held in instance variables of a class.
* Grammar-writers will have access to both the runtime system, currently
  called `R`, and the parsing api. I think the overall interface will produce
  more readable code if the entire api is made of method calls rather than a mix
  of functions and methods. It feels more consistent and organized.

The prototype table has two instance variables: `all_rules` and `rules`.

--]]

    local Parser = {all_rules = {}, rules = {}}

--[[

### `all_rules`

Each key in `all_rules` is a mode name, with `<global>` naming the default root
mode; other names must be identifier tokens, so that a name clash is avoided.
Each value in `all_rules` is a table mapping rule names to rule objects, which
we'll describe below.

### `rules`

The `rules` table is effectively a stack of rule tables
from `all_rules`. The topmost rule table takes priority over lower ones
when lookups are done in `rules`.

There are many use cases of this stack.
One use is to allow something like virtual grammar lookups, analogous to virtual
method calls between a superclass and subclass. As a specific example, suppose
we have a mode that parses a string literal. Then it could expect certain rules
to be defined previously in the stack that specify the escape character or the
type of ending delimiter. This flexibility makes the string-parsing mode more
reusable by other grammars.

A `Parser` instance is straightforward.
It begins life as an empty table with `Parser` as its metatable, and
with non-native key lookups delegated to `Parser` using the `__index`
metamethod.

--]]

    function Parser:new()
      assert(self)
      local parser = {}
      self.__index = self
      return setmetatable(parser, self)
    end

--[[

Next we get to the mode pushing and popping mechanics.

The global `Parser` instance is called `P`.
A new mode can be pushed by calling `P:push_mode(mode_name)`.
This updates the table `self.rules`, via which all rules are accessed during the
parse. In particular, a rule with name `rule_name` will always be looked up as
`self.rules[rule_name]`, and it's up to `P:push_mode` to ensure that
`self.rules` will give the correct value, taking into account the entire mode
stack.

If `old_rule` is an existing rule before the push, and the pushed mode doesn't
have its own definition of `old_rule`, then we want to keep using the pre-push
value for this rule. Conceptually, this is just like the old rule set being used
as the `__index` value for the new rule set.

However, there would be a problem if we directly set `__index` to point to the
previous rule table in the stack. In particular, a single mode may be on the
stack in multiple places. So we can't directly associate any delegation behavior
with a mode table. Instead, we'll create empty placeholder tables with custom
metatables that know to first attempt a lookup in the mode they represent, and
then perform a fallback lookup in the next-in-stack placeholder table.

This behavior requires the use of an anonymous `__index` function defined within
`P:push_mode`. The placeholder's metatable also has an `up` key to keep track of
the next-in-stack table in order to enable popping.

--]]

    function Parser:push_mode(mode_name)
      if do_print_extras then
        print('Parse mode ' .. mode_name .. ' pushed onto stack')
      end
      assert(self and mode_name)

      -- We can't alter the metatables of self.all_rules[mode_name] since a
      -- single mode may end up on the stack at multiple levels.
      local mode_rules = self.all_rules[mode_name]
      local up_rules = self.rules

      -- Define the metatable for the new placeholder rules table.
      local meta = {
        __index = function (tbl, key)
          -- print('lookup on self.rules (tbl=' .. tostring(tbl) ..
          --       ') with key ' .. key)
          local v = mode_rules[key]
          if v ~= nil then return v end
          return up_rules[key]
        end,
        up = up_rules
      }

      -- Create the empty placeholder table, set its metatable, and set `rules`.
      self.rules = setmetatable({}, meta)
    end

--[[

Popping a mode is relatively easy.
We only need to replace the `rules` table with the next-on-top placeholder
table. This will be the value of the `up` key in the current rule's table's
metatable.

--]]

    function Parser:pop_mode()
      if do_print_extras then
        print('popping a mode from the parse mode stack!')
      end
      assert(self)
      self.rules = getmetatable(self.rules).up
    end

    function Parser:parse(str)
      return self:parse_rule(str, 'phrase')
    end

    function Parser:parse_rule(str, rule_name)
      local last_char = rule_name:sub(#rule_name, #rule_name)
      if do_print_extras then
        io.write('parse_rule, rule_name = "' .. rule_name .. '" ')
        local str_start = string.format('%q', str:sub(1, 10)):gsub('\n', 'n')
        print(string.format('str begins %s', str_start))
      end
      if last_char == "'" then
        return parse_literal(str, rule_name:sub(2, #rule_name - 1))
      elseif last_char == '"' then
        return parse_regex(str, rule_name:sub(2, #rule_name - 1))
      elseif last_char == '*' or last_char == '?' then
        local rule = self.rules[rule_name:sub(1, #rule_name - 1)]
        return self:parse_multi_rule(str, rule, last_char)
      elseif rule_name:sub(1, 1) == '-' then
        local mode = rule_name:sub(2)
        return self:parse_mode_till_popped(str, mode)
      elseif rule_name == '<pop>' then
        self:pop_mode()
        return 'mode popped', str
      end

      -- Try to treat it as a basic rule name.

      -- TODO Add a way to inspect the mode name at each mode level in the rules
      --      stack.

      local rule = self.rules[rule_name]
      if rule == nil then
        -- TODO It would be useful to print out more info here. At least the
        --      current mode stack. Possibly also a stack of how we got here in
        --      the grammar tree.
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
        if subtree ~= 'mode popped' then
          tree.kids[#tree.kids + 1] = subtree
        end
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
      -- Ensure the mode exists.
      if self.all_rules[mode] == nil then self.all_rules[mode] = {} end
      -- Add each rule, ensuring the name field is consistent for each one.
      for rule_name, rule in pairs(new_rules) do
        rule.name = rule_name
        self.all_rules[mode][rule_name] = rule
      end
    end

    local P = Parser:new()


------------------------------------------------------------------------------
-- Rules.
------------------------------------------------------------------------------

--[[

### The global grammar

Below is the grammar I plan to set up, with global rules given first.
In the `mode_item` rule, I use the item `rule_name`, although, semantically,
that item is actually a mode name.

    phrase --> statement | empty_line
    empty_line -->
      '\n'
    statement --> rules_start | rule
    rules_start --> global_start | mode_start
    global_start -->
      '>' '\n'
    mode_start -->
      '>' rule_name '\n'
    rule -->
      rule_name '-->' rule_items
    rule_items --> or_items | seq_items
    or_items -->
      basic_item or_and_item* '\n'
    seq_items -->
      '\n' item item* '\n'
    basic_item --> literal | regex | rule_name
    or_and_item -->
      '|' basic_item
    item --> '<pop>' | mode_item | star_item | question_item | basic_item
    literal -->
      "'[^']*'"
    regex -->
      '"' -str
    rule_name -->
      "[A-Za-z_][A-Za-z0-9_]*"
    mode_item -->
      '-' rule_name
    star_item -->
      basic_item '*'
    question_item -->
      basic_item '?'

### Plan for future global grammar

In writing this out, I realized that the initial global rule set makes the most
sense as something small. In particular, parsing of rules belongs in a mode, and
by default, we won't be in that mode. As an example of why this makes sense, the
current rule setup may see an isolated rule without an introductory `>` phrase,
and still parse that rule. That's bad behavior. It also feels cleaner if the
global rule set is extremely small to begin with.

Eventually, it would be nice to allow till-newline comments in grammar specs.

### The `str` mode grammar for strings

TODO Turn off whitespace prefixes in `str` mode.

Below are the rules in the `str` mode. The `|:` token indicates to pop the mode
if none of the previous or-rule items match.

    phrase --> escaped_char | regular_char | end_char
    escaped_char -->
      '\\' "."
    regular_char -->
      "[^\"]"
    end_char -->
      '"' <pop>

--]]

    P:add_rules_to_mode('<global>', {
      phrase        = { kind = 'or',  items = {'statement', 'empty_line'} },
      empty_line    = { kind = 'seq', items = {"'\n'"} },
      statement     = { kind = 'or',  items = {'rules_start', 'rule'} },
      rules_start   = { kind = 'or',  items = {'global_start', 'mode_start'} },
      global_start  = { kind = 'seq', items = {"'>'", "'\n'"} },
      mode_start    = { kind = 'seq', items = {"'>'", 'rule_name', "'\n'"} },
      rule          = { kind = 'seq', items = {'rule_name',
                                               "'-->'",
                                               'rule_items'} },
      rule_items    = { kind = 'or',  items = {'or_items', 'seq_items'} },
      or_items      = { kind = 'seq', items = {'basic_item',
                                               'or_and_item*',
                                               "'\n'"} },
      seq_items     = { kind = 'seq', items = {"'\n'",
                                               'item',
                                               'item*',
                                               "'\n'"} },
      basic_item    = { kind = 'or',  items = {'literal',
                                               'regex',
                                               'rule_name'} },
      or_and_item   = { kind = 'seq', items = {"'|'", 'basic_item'} },
      item          = { kind = 'or',  items = {"'<pop>'",
                                               'mode_item',
                                               'star_item',
                                               'question_item',
                                               'basic_item'} },
      literal       = { kind = 'seq', items = {[["'[^']*'"]]} },
      regex         = { kind = 'seq', items = {[['"']], '-str'} },
      rule_name     = { kind = 'seq', items = {[["[A-Za-z_][A-Za-z0-9_]*"]]} },
      mode_item     = { kind = 'seq', items = {"'-'", 'rule_name'} },
      star_item     = { kind = 'seq', items = {'basic_item', "'*'"} },
      question_item = { kind = 'seq', items = {'basic_item', "'?'"} }
    })

    P:add_rules_to_mode('str', {
      phrase       = { kind = 'or',  items = {'escaped_char',
                                              'regular_char',
                                              'end_char'} },
      escaped_char = { kind = 'seq', items = {"'\\'", [["."]]} },
      regular_char = { kind = 'seq', items = {[["[^"]"]]} },
      end_char     = { kind = 'seq', items = {[['"']], '<pop>'} }
    })

    -- TODO NEXT Figure out how to indicate no whitespace prefix in certain
    --           places in the grammar. For example, in {star,qusetion}_item, as
    --           well as in the str mode.

    -- TODO Ensure this parser knows how to handle mode items such as '-str'.

    P:push_mode('<global>')


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
    -- exists; if it is new key at all levels, it's created at the current
    -- level.
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
      local meta = {__index = self.frame,
                    up = self.frame,
                    __newindex = frame_set}
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


------------------------------------------------------------------------------
-- Future work.
------------------------------------------------------------------------------

--[[

### The next parse script

I'd like the next parse script to be able to parse its own grammar.
Optionally, I'd like to be able to toggle whitespace prefixing on and off.

### Thoughts on future scripts

--]]

------------------------------------------------------------------------------
-- TODO Stuff to decide where it goes.
------------------------------------------------------------------------------

--[[

*TODO Clean up these preliminary notes on the `Parser` class.*

### Future functionality

One thing I'd like to be able to handle is an easy-to-notate and perhaps
intrarule change in whitespace handling. For example, in the list of items
that make up a seq-rule, we may have star items. A star item is a rule name
immediately followed by a `'?'` token, without any whitespace between the
two. There's currently no way to specify this lack of whitespace.

I don't think the bottom level is the best place to code this ability.
Instead, I'd like to try to make the bottom level enable this feature, and
require a higher layer to make this feature easy to use. In particular,
I can add a hook to allow a rule to modify the parser state. Ideally, the
hook would implicitly save the parser state and restore it once the rule
was done being parsed, whether it was successful or not. This could use
the same lightweight mechanism as is used for pushing or popping modes.
This design has the advantage of being easy to use correctly and difficult
to use incorrectly. In particular, I'd like to avoid allowing direct
access to the push/pop functionality that works behind the scenes.
I imagine this function may either be unnamed, in which case the syntax
would be minimal, or it may be named something like
`preparse`, which is still short, yet conveys a clear sense of when it
is rule. It excludes language about saving and loading of parsing state,
since it may be used independently of that functionality.

A design alternative would be to enable a one-off item name, such as `.`,
that would turn off whitespace between the two enclosing tokens. This
feels like a good interface, although I can imagine it being implemented
using the above low-level functionality.

### How modes can be pushed

**TODO** Clean up this bit.

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
      like `push_mode` and `parse_mode_till_popped`.

In the future I may consider renaming `P` and `R` to `parser` and `runner`, as
those are more descriptive names. I can also imagine eventually getting a
`T` or `tree` parameter, similar to that used in `parse5`.

--]]
