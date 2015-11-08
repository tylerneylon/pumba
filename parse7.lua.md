--[[

# parse7.lua.md

--]]


------------------------------------------------------------------------------
-- Introduction.
------------------------------------------------------------------------------

--[[

This is a literate implementation of a dynamic parser that is a step toward an
open compiler. It is at once a valid Lua program and a valid markdown file. It's
meant to be read by humans who'd like to learn how the program works in a manner
similar to how they'd read an article.

The actual Lua program is given in code blocks between paragraphs. Some example
or comment code blocks are also present; these examples are distinguished by a
double-hyphen prefix. All other code is live and seen by Lua when you run this
script.

Here is how you can see this program in action by running
it from the shell:

    -- Example shell usage:
    -- 
    -- lua parse7.lua.md 04.input

This file is just one step in a project of large scope. I won't usually comment
my files so carefully, but I wanted to get some practice with literate
programming, and I thought this particular step was interesting.

### Modes

This file adds a major feature to grammars called *modes*. Every mode can
have its own completely independent grammar, or it can be designed to interact
with other grammars. For example, the grammar parsed by this script includes a
`regex` rule that parses string literals. Rather than writing a regular
expression to parse these string literals, I decided to use a mode. Below are
the relevant rules.

    -- Example grammar: a sequential rule in the global mode:
    -- 
    -- regex -->
    --   '"' -str

The `-str` item instructs the parser to enter the mode called `str` until that
mode exits.

    -- Example: These rules make up the str mode:
    -- 
    -- phrase --> escaped_char | regular_char | end_char
    -- escaped_char -->
    --   '\\' "."
    -- regular_char -->
    --   "[^\"]"
    -- end_char -->
    --   '"' <pop>

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
    -- Because this script doesn't use the run framework, this boolean currently
    -- doesn't change any behavior.
    local do_run_dbg_print = false

    -- This turns on or off printing of good/bad rule parsing attempts.
    local do_mid_parse_dbg_print = false

    -- This turns on or off printing debug info about parsing.
    local do_post_parse_dbg_print = true

    -- This turns on or off printing of the input and output to each top-level
    -- phrase parse. This is most useful when working with small phrase strings.
    local do_dbg_print_each_phrase_parse = false


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

### The prototype and instance variables

The prototype table has two instance variables: `all_rules` and `rules`.

--]]

    local Parser = {all_rules = {}, rules = {}}

--[[

#### `all_rules`

Each key in `all_rules` is a mode name, with `<global>` naming the default root
mode; other names must be identifier tokens, so that a name clash is avoided.
Each value in `all_rules` is a table mapping rule names to rule objects, which
we'll describe below.

#### `rules`

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

### `new()`

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

### `push_mode()`

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
      assert(self and mode_name)

      if do_mid_parse_dbg_print then
        print((indent or '') .. 'push_mode ' .. mode_name)
      end

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

### `pop_mode()`

Popping a mode is relatively easy.
We only need to replace the `rules` table with the next-on-top placeholder
table. This will be the value of the `up` key in the current rule table's
metatable.

--]]

    function Parser:pop_mode()
      assert(self)

      if do_mid_parse_dbg_print then
        print(indent .. 'pop_mode')
      end

      self.rules = getmetatable(self.rules).up
    end

--[[

### `parse()`

The primary entry point to the parser is the `parse` method, which accepts a
string input with the source, and on success returns a `tree, tail` result.
A single call to this method parses a single `phrase` in the current mode of the
parser. The expected usage is that this method will be called on the source
repeatedly until there is no source left to parse, or until an error is
reported. An error is reported by returning a tree value of `no match`, as a
string. Most of this work is delegated across several parsing functions.

--]]

    function Parser:parse(str)
      return self:parse_rule(str, 'phrase')
    end

--[[

### `parse_rule()`

The `parse_rule` method is the main dispatcher of rule parsing to more specific
functions. It accepts the source string along with any string containing a valid
item value, and attempts to parse that item from the prefix of the source.

Until now, the word *item* has been used informally to describe a single element
on the right side of a grammar rule. It's a good time to be more precise.

The following are all the valid types of items. These descriptions mostly match
both the vision and the implementation, but where they differ, I'll describe the
vision rather than the implementation.

* A *subrule* is named with an identifier that starts with a letter or
  underscore, and continues with alphanumeric or underscore characters,
  containing no other characters. This item is matched using the rule it names.
* A *literal* is a single quote `'`-delimited string. It matches exactly the
  characters inside the single quotes. For now, `parse_rule` does not respect
  any escaped characters in a literal, and simply trims off the first and last
  characters, expected to both be `'`.
* A *string pattern*, similar to a regular expression, delimited by double
  quote `"` characters. The pattern matching is based on Lua's internal system,
  and is essentially the same as regular expressions except that parenthesized
  subexpressions cannot be followed by any of the `+*?` operators, and there is
  no `|` or operator.
* An *optional* or *repeated* item, which is any valid item followed by a `?` or
  `*` character. If the last character is `?`, then 0 or 1 of the item are
  matched. If it's `*`, then 0 or more are matched.
* A *mode parse* item, which is the character `-` followed by a mode name. This
  item pushes the new mode, then repeatedly parses the `phrase` rule in the
  resulting mode stack until the mode is popped, or a parse error occurs.
* A *special case* `<pop>` item, which parses nothing, but pops the current mode
  and returns a special case tree value indicating that this action was taken.
  In a correctly-designed grammar, this return value will never be seen at a top
  level parse call, and only be used internally, within the parse of a single
  top-level `phrase` rule.

Each of these cases are handled by more specific functions defined below.

This function contains the first *reference point*. These are places in the code
where I have specific improvement ideas. The details of all reference points are
listed at the bottom of this file in the *reference points* sections.

--]]

    function Parser:parse_rule(str, rule_name)
      local last_char = rule_name:sub(#rule_name, #rule_name)

      -- Handle item types: literal, optional, repeated, mode, or <pop>.

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

      local rule = self.rules[rule_name]
      if rule == nil then
        -- Reference point A.
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

--[[

### `parse_or_rule()` and `parse_seq_rule()`

These are the first methods that explicitly build a `tree` object as a return
value. Each tree will always have at least these keys:

| Key  |  Meaning                                                            |
| ---- | ------------------------------------------------------------------- |
| name | the name of the grammar rule that was parsed                        |
| kind | either `'seq'` or `'or'`                                            |
| kids | all subtrees in order for a seq-rule; a single item for an or-rule  |

Each individual item is attempted to be parsed using `parse_rule`.
Parse failures provide the string `'no match'` instead of a tree object as the
first return value.

An or rule has a complete match as soon as *any* subrule is parsed successfully.

--]]

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

--[[

A seq rule only succeeds when *all* of its subrules can be parsed in order from
the given source string `str`.

--]]

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

--[[

### `parse_multi_rule()`

This method parses optional rules that end with a `?` character, and repeated
rules that end with `*` character. As above, `parse_rule` is used to parse the
rule name after this last special character has been removed.

This method is interesting in that it can successfully match an empty string,
and thus can't fail to find a match.

--]]

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

--[[

### `parse_mode_till_popped()`

This function pushes a new mode and repeatedly parses the `phrase` rule until
the new mode is popped. For now, the code ignores the possibility of parse
failures.

--]]

    function Parser:parse_mode_till_popped(str, mode)
      local rules_when_done = self.rules
      self:push_mode(mode)
      local tree = {name = '<mode:' .. mode .. '>', kind = 'seq', kids = {}}
      repeat
        -- Reference point B.
        tree.kids[#tree.kids + 1], str = self:parse(str)
      until self.rules == rules_when_done
      return tree, str
    end

--[[

### `add_rules_to_mode()`

A simplistic way to add a rule to a `Parser` instance would be something like
this:

    -- if P.all_rules[mode_name] == nil then P.all_rules[mode_name] = {} end
    -- P.all_rules[mode_name][rule_name] = {..rule data..}

This could theoretically work, but it requires the user to repeat a non-short
code pattern for a common and conceptually simple operation. It makes the
interface easier to use incorrectly. So this operation is handled through the
`add_rules_to_mode()` method. As a bonus, the method also ensures that each
rule has a consistently-set `name` key.

We haven't seen any rule definitions yet, although previous methods have used
the `rule.items` table and the `rule.kind` string. Some concrete rule data will
be given below.

--]]

    function Parser:add_rules_to_mode(mode, new_rules)
      -- Ensure the mode exists.
      if self.all_rules[mode] == nil then self.all_rules[mode] = {} end
      -- Add each rule, ensuring the name field is consistent for each one.
      for rule_name, rule in pairs(new_rules) do
        rule.name = rule_name
        self.all_rules[mode][rule_name] = rule
      end
    end

--[[

Now we're ready to create a `Parser` instance, which we'll call `P`.

--]]

    local P = Parser:new()


------------------------------------------------------------------------------
-- Metaparse functions.
------------------------------------------------------------------------------

--[[

These functions may live outside of any Parser instance as they depend
on nothing beyond the string and regex or literal handed to them. In
contrast, parse methods in `Parser` care about the current context of
named rules.

The next two functions are the only leaf-parsers. The current code 
allows arbitrary space characters before any literal or regular expression. This
is not always what we want. For example, in the string-parsing mode, we don't
want to silenly parse space characters; they should be explicitly parsed as
belonging to the grammar's items.

Similar to `Parser`'s parsing methods, these functions accept a source string
and return a `tree`, `tail` pair. The `tree` has the following keys.

| Key  |  Meaning                                                            |
| ---- | ------------------------------------------------------------------- |
| name | either `'lit'` for a literal, or `'re'` for a regular expression    |
| val  | the matched substring of the source, excluding any leading spaces   |

### `parse_literal()`

Lua's standard string library includes pattern-based string matching functions.
The `parse_literal` function uses `string.find`, which finds a pattern instead
of a literal substring. We use the pattern capabilities to skip over leading
spaces, and then to capture in `val` only the portion matching exactly the
argument `lit_str`. This requires us to escape `lit_str` to avoid treating any
regular-expressiony characters in it as special; this is done with the
soon-to-be-defined `escaped_lit` function.

TODO Carefully clean up the commented-out lines here. *Carefully* means to
     consider keeping prints that may be useful for future debugging.

--]]

    function parse_literal(str, lit_str)
      --print('parse_literal(' .. str .. ', ' .. lit_str .. ')')
      local re = '^ *(' .. escaped_lit(lit_str) .. ')'
      --print('re=' .. re)
      local s, e, val = str:find(re)
      --print('s, e, val = ', s, e, val)
      if s == nil then return 'no match', str end
      return {name = '<lit>', value = val}, str:sub(e + 1)
    end

--[[

### `parse_regex()`

This function accepts a string input `full_re` of the form `p1|p2|p3` where the
substrings `p1`, `p2`, and so on are all standard Lua search patterns. As a
reminder, Lua doesn't directly support the `|` character as an *or* operator,
but instead treats it as a literal character. This function adds back some of
that functionality by supporting top-level-only *or* clauses. Similar to
`parse_literal()`, it returns a `tree` object with `name` and `value` keys; or
the `'no match'` string if the given `full_re` doesn't match a prefix of `str`.

--]]

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

--[[

### `escaped_lit()`

This function returns an edited string that, when used as a Lua pattern, returns
literal matches for the input string `lit_str`. The replacement string `'%%%0'`
in the `gsub` call causes Lua to replace every non-alphabetic character with a
`%`-escaped copy of that character. It would be bad to escape alphabetic
characters - an example would be `%a` - because many of those are treated as
character classes, where as something like `%.` will simply match a literal `.`
character.

--]]

    function escaped_lit(lit_str)
      return lit_str:gsub('[^A-Za-z]', '%%%0')
    end


------------------------------------------------------------------------------
-- Rules.
------------------------------------------------------------------------------

--[=[

Now we're ready to define the grammar that this script will parse. This script
is specifically designed to parse the file `04.input`, which contains a sample
grammar for a C-like language. The format of `04.input` is very similar to the
grammar comments immediately below, which can be used as both an example of
the syntax being parsed as well as a human-friendly yet formal version of the
grammar this script can parse.

As a reminder, the top-most rule is called `phrase`,
regular expressions are enclosed in double quotes, and literal string matches
are enclosed in single quotes. Single-line rules are **or** rules, and can't
produce leaf elements in the resulting parse tree. Two-line rules are **seq**
rules - short for *sequence* rules - and may or may not result in leaf items in
the parse tree.

### The global grammar

This script's grammar contains both a global mode and a `str` mode for string
parsing. Here are the rules for the global mode:

    -- phrase --> statement | empty_line
    -- empty_line -->
    --   '\n'
    -- statement --> rules_start | rule
    -- rules_start --> global_start | mode_start
    -- global_start -->
    --   '>' '\n'
    -- mode_start -->
    --   '>' rule_name '\n'
    -- rule -->
    --   rule_name '-->' rule_items
    -- rule_items --> or_items | seq_items
    -- or_items -->
    --   basic_item or_and_item* '\n'
    -- seq_items -->
    --   '\n' item item* '\n'
    -- basic_item --> literal | regex | rule_name
    -- or_and_item -->
    --   '|' basic_item
    -- item --> '<pop>' | mode_item | star_item | question_item | basic_item
    -- literal -->
    --   "'[^']*'"
    -- regex -->
    --   '"' -str
    -- rule_name -->
    --   "[A-Za-z_][A-Za-z0-9_]*"
    -- mode_item -->
    --   '-' rule_name
    -- star_item -->
    --   basic_item '*'
    -- question_item -->
    --   basic_item '?'

### The `str` mode grammar for strings

Below are the rules in the `str` mode. This mode is invoked by the `regex` rule
from the global mode, and is exited when the special `<pop>` item is
encountered.

The item `'\\'` matches a single backslash. The item `"."` matches any single
character. And the item `"[^\"]"` matches any non-quote character.

    -- phrase --> escaped_char | regular_char | end_char
    -- escaped_char -->
    --   '\\' "."
    -- regular_char -->
    --   "[^\"]"
    -- end_char -->
    --   '"' <pop>

The `regular_char` rule avoids matching backslashes
because the previous `escaped_char` rule will
capture them. Unless, of course, the entire source data ended with a
backslash, in which case `escaped_char` would fail to parse the `"."` item. This
unusual case reveals a bug in the grammar, but one which is not critical since
this is not production code.

Now we're ready for actual code that will add this rule set to our `Parser`
instance `P`. This data directly reflects the rules we've just seen.
In some cases, I've used Lua's double-square-bracket `[[string]]` syntax 
in order to reduce the number of escape characters needed. This syntax has no
escape sequences whatsoever.

--]=]

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

--[[

At this point we've set up data for the two modes `<global>` and `str`. This
data lives in `P.all_rules`, but is not yet accessible from `P.rules`, where
parse rules are found at parse time. In order to make the global mode active, we
need to push it onto the parser's mode stack. As a design decision, this action
could have been taken within
`Parser:new`, but leaving it out makes the name `<global>` less hard-coded and
thus leaves the `Parser` class somewhat more elegant.

--]]

    P:push_mode('<global>')


------------------------------------------------------------------------------
-- Tree running functions.
------------------------------------------------------------------------------

--[[

One long-term goal of this project is to be able to specify at once both a
grammar and a set of behaviors for the resulting parse tree. Internally, these
two behaviors are captured by the `Parser` class and the `Run` class - which may
eventually be renamed to `Runner` for consistency. The code in this section
specifies the `Run` class but is *not used* in this script. It exists for its
future use in the more complete open compiler implementations.

Since this code is not used, these literate comments will not cover it in
detail. To understand its place in the big picture, though, it's useful to know
that the main entry point to a `Run` instance `R` is the method `R:run()` called
with a `tree` that was returned by `P:parse()`. The tree elements
themselves will eventually have a key called `run` whose value is a string of
Lua code that will be executed by `R:run()`.

--]]

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

--[[

This section contains short, generally useful functions. The `copy()` function
provides a deep copy of a table, and the `is_empty()` function indicates if a
string is empty, treating all-whitespace strings as empty.

--]]

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

--[[

This section contains functions to help a grammar debug their own grammar. The
output of these functions may also eventually be useful in the creation of clear
and actionable error statements to code writers.

The output of these functions is controlled by the boolean values listed above
in the *settings* section. I like to keep configuration parameters near the top
of a script for easier access.


TODO vvv   Remove these temp notes.

    functions: pr, pr_tree, print_metaparse_info, wrap_metaparse_fn,
               pr_line_values

    call graph:

    pr_line_values -> pr, pr_tree
    do_post_parse_dbg_print -> pr_tree
    do_dbg_print_each_phrase_parse -> pr_line_values

TODO ^^^

### `pr()`

This function can prettily print any primitive Lua type and tables. It's used by
the `pr_tree` function below, although not extensively. It's nice to have a
function like this handy for general debugging.

--]]

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

--[[

### `pr_tree()`

This function produces a clear breakdown of a parse tree into both the rule
names and the corresponding sections of source text parsed into those rules.

As an example, suppose we have these source lines:

    -- fn_call -->
    --   word '(' end_of_fn_call

Calling `P:parse()` will return a parse tree. If we call `pr_tree()` on that
return value, the output looks like this:

    -- phrase - statement - rule
    --   rule_name fn_call
    --   '-->'
    --   rule_items - seq_items
    --     '\n'
    --     item - basic_item - rule_name word
    --     *item
    --       item - basic_item - literal '('
    --       item - basic_item - rule_name end_of_fn_call
    --     '\n'

The above example strings have been prefixed with double hyphens to help
visually distinguish them from running code.

--]]

    function pr_tree(tree, indent, this_indent)
      indent = indent or ''
      io.write(this_indent or indent)
      if tree.name == '<lit>' then
        print("'" .. tree.value:gsub('\n', '\\n') .. "'")
        --print("'--------'")
        return
      end
      if tree.value then
        print(tree.name .. ' ' .. tree.value:gsub('\n', '\\n'))
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

--[[

### `first_line()` and `print_metaparse_info()`

The next two functions work together to print out intermediate parsing progress
as it happens. As a simple exmaple, the very first line of `04.input` consists
of exactly two characters: a `>` and a newline. These will be parsed into the
tree below.

    -- phrase - statement - rules_start - global_start
    --   '>'
    --   '\n'

If a grammar writer is having difficulty getting a section of source code to be
parsed correctly, they may find it useful to see each parse rule attempt and
whether or not it succeeded. This output is produced by the
`print_metaparse_info()` function, which in turn depends on `first_line()` to
produce a short prefix of the code being parsed. This output is off by default
and turned on with the `do_mid_parse_dbg_print` boolean. The output for our
simple example tree is shown here:

    -- phrase attempting from >\n
    --   statement attempting from >\n
    --     rules_start attempting from >\n
    --       global_start attempting from >\n
    --         '>' attempting from >\n
    --         '>' succeeded
    --         '\n' attempting from \n
    --         '\n' succeeded
    --       global_start succeeded
    --     rules_start succeeded
    --   statement succeeded
    -- phrase succeeded

TODO Also mention which functions are used by which settings booleans.

--]]

    function first_line(str)
      next_newline = str:find('\n') or #str + 1
      return str:sub(1, next_newline):gsub('\n', '\\n')  -- Improve readability.
    end

    indent = ''

    function print_metaparse_info(fn_name, fn, str, rule_name)
      indent = indent .. '  '
      rule_name = rule_name:gsub('\n', '\\n')  -- Improve readability.
      print(indent .. rule_name .. ' attempting from ' .. first_line(str))
      local tree, tail = fn()
      local outcome_str = (tree == 'no match' and 'failed' or 'succeeded')
      print(indent .. rule_name .. ' ' .. outcome_str)
      indent = indent:sub(1, #indent - 2)
      return tree, tail
    end

--[[

Unlike most of the code so far, this next section actually runs a few statements
rather than simply defining variables or functions. This is how
the `do_mid_parse_dbg_pring` boolean takes effect. When it's on, the
`P.parse_rule()` method is replaced with a wrapper version that prints out
metaparse information via the above `print_metaparse_info()` function.

--]]

    if do_mid_parse_dbg_print then
      local orig_parse_rule = P.parse_rule
      P.parse_rule = function (self, str, rule_name)
        local function fn () return orig_parse_rule(self, str, rule_name) end
        return print_metaparse_info('parse_rule', fn, str, rule_name)
      end
    end

--[[

### `pr_line_values()`

The next function is activated by the `do_dbg_print_each_phrase_parse` boolean,
and is used to print out a summary of the parsing progress after each top-level
phrase is parsed. In this function the `line` refers to the source before the
latest phrase was parsed, the `tree` is the phrase's parse tree, and the `tail`
is the source that remains after the phrase.

--]]

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

--[[

TODO HERE

--]]

    -- Check that they provided an input file name.
    if not arg[1] then
      print('Usage:')
      print('  lua ' .. arg[0] .. ' <input_file>')
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

      if do_dbg_print_each_phrase_parse then
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

TODO: Clean up the placement/expression of this future work item:
TODO Add a way to inspect the mode name at each mode level in the rules stack.

TODO Turn off whitespace prefixes in `str` mode.

### Plan for future global grammar

In writing this out, I realized that the initial global rule set makes the most
sense as something small. In particular, parsing of rules belongs in a mode, and
by default, we won't be in that mode. As an example of why this makes sense, the
current rule setup may see an isolated rule without an introductory `>` phrase,
and still parse that rule. That's bad behavior. It also feels cleaner if the
global rule set is extremely small to begin with.

Eventually, it would be nice to allow till-newline comments in grammar specs.

TODO Be able to correctly handle mistakes in `str` mode such as the source
     ending with a single backslash.

    -- TODO NEXT Figure out how to indicate no whitespace prefix in certain
    --           places in the grammar. For example, in {star,qusetion}_item, as
    --           well as in the str mode.

TODO In the debug print-outs, be able to easily distinguish between a real
     newline character and a simulated one.

## Reference points

This section refers to commented reference points within the code above.
As an example, *Point D* can be found by searching for *Reference point D* in
this file.

### Point A

In `Parser:parse_rule()`, this would be a good place to add more error
information, such as the current mode stack and possibly a trace of how we got
there in the grammar tree.

### Point B

In `Parser:parse_mode_till_popped()`, this is a good place to detect parse
failures and to propagate those out to the caller.

--]]
