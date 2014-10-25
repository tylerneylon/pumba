# pumba

*a compiler project*

The plan for this project is to create a compiler
with some nice features that I haven't seen in other compilers.

It is currently at a ridiculously early stage.

Earlier, I worked on a toy compiler called
[Project Water](https://github.com/tylerneylon/water).
I felt that that project achieved its goal of helping me
understand first-hand what it's like to build the foundation
of an open compiler.
The goal of the present repo is to iterate on that project
and build something that is more complete and I hope a bit
more elegant than what I started with in Project Water.

## What works so far

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

## What is in progress

I haven't decided exactly what to do next. Here are some ideas:

- [ ] Write out a nice formal grammar for a C or JavaScript subset.
- [ ] Carefully delineate the feature set for new languages specified in pumba.
- [ ] Make a list of lessons learned from creating project water.
- [ ] Learn how to work with DynASM.
- [ ] Take a step forward from `01.input` and write a grammar and parser for that.
