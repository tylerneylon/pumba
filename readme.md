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

## What is in progress

Up next I plan to copy `parse3` over to `parse4`
and make the execution portion more data-like than
code-like.
