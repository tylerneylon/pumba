# pumba

*a compiler project*

The plan for this project is to create a compiler
with some nice features that I haven't seen in other compilers.

It is currently at a ridiculously early stage.

## What works so far

### The `parse1.lua` script

You can run

    ./parse1.lua 00.input

to parse and execute plus/times positive-integer
math expressions. The `parse1.lua` script is a kind
of hello-world of parser-executer scripts.

## What is in progress

### The `parse2.lua` script

The plan for this script is to be able to parse a
simple language with commands like the following:

    s = 0
    for i = 1 to 100: s += i
    print s
