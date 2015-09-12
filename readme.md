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

Here are a few example cases you can try out:

    ./parse1.lua 00.input  # parse and evaluate simple math expressions

    ./parse2.lua 01.input  # parse and run a simple for loop

    # parse3.lua does the same work as parse2.lua with cleaner code.

    # parse4.lua.md does the same work, but is further re-organized,
    #               and is written with reader-friendly markdown comments.

    ./parse5.lua.md 02.input  # parse and run a small subset of C

More detailed explanations of the progress in each of these scripts is
explained in
[what_works.md](https://github.com/tylerneylon/pumba/blob/master/what_works.md).

## What is in progress

I've set up `03.input` as a grammar for the subset of C in `02.input`.
I plan to make `parse6.lua.md` as the next iteration which can parse the
grammar. The eventual goal is to add run strings within the grammar, and
then to include the C code just after this.

### Future ideas

Here are some ideas for future directions:

- [ ] Write out a nice formal grammar for a C or JavaScript subset.
- [ ] Carefully delineate the feature set for new languages specified in pumba.
- [x] Make a list of lessons learned from creating project water.
- [ ] Learn how to work with DynASM.
- [x] Take a step forward from `01.input` and write a grammar and parser for that.

## Notes from Project Water

I've also written up some
[lessons learned from the original project water](https://github.com/tylerneylon/pumba/blob/master/lessons_from_water.md).

