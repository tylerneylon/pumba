# What works

This document explains some of the incremental steps
taken to build pumba.

### The `parse1.lua` script

You can run

    ./parse1.lua 00.input

to parse and execute plus/times positive-integer
math expressions. The `parse1.lua` script is a kind
of hello-world of parser-executer scripts.

### The `parse2.lua` script

Run this script as `./parse2.lua 01.input`.

This script can parse a simple language based
on the following example:

    s = 0
    for i = 1 to 100: s += i
    print s

### The `parse3.lua` script

Run this as `./parse3.lua 01.input`.

This script is
an iteration of `parse2.lua` which puts more work into
metafunctions and data-fies much of the grammar and
execution work.

The general direction here is to move toward grammar
and execution specification as input.

### The `parse4.lua.md` script

Run this as `./parse4.lua.md 01.input`.

This is a standard Lua script; I added the `md` extension
so that github will render it as markdown, since it contains
markdown-formatted comments that are easier to read when
processed into html.

This script is the next
iteration of `parse3.lua` which moves the rule-specific
tree execution work into more data-like strings. This
is tricky, because it really is arbitrary code doing the
executing, but I want to set it up in a nice framework
that encourages and empowers code patterns that will
make life easier for both the language designer and
the language user.

That run framework is described in more detail in the
comments in
[the parse4 script](https://github.com/tylerneylon/pumba/blob/master/parse4.lua.md).

### The `parse5.lua.md` script

Run this as `./parse5.lua.md 02.input`.

This script parses a simple C-like language.
I'm getting experience with function definitions,
symbol tables, and rule specifications that may support
regular-expression-like operators.

### The `parse6.lua.md` script

Run this as `./parse6.lua.md 03.input`.

This script performs a simplified parse of a grammar specification.
The main reason I consider it simplified is that it doesn't handle
quoted strings very well. For example, regular expressions are parsed strangely
in that they are expected to not contain spaces and are expected to end with
a double quote followed by a space.

Theoretically, I think I could get a simple string syntax parsed with a
regular expression, but I'd rather dive into parsing modes at this point since
those are coming up soon, and I suspect working with strings may be easier with
them.

I also plan to require or-rules to be single-line and seq-rules to be multiline,
which was the case in project water and which eliminated some ambiguity which
was not useful. In particular, I don't plan to have this syntax be the usual
human-facing one, so ease-of-use - though still important - can be balanced
slightly in favor of easy-of-implementation at this point.
