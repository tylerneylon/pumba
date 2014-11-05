# Lessons learned from project water

## There are two big pieces - the parser and the runner
*And therefore three languages used at a time in general.*

Some language environments, such as Java, already have a separation between a compiler and a
virtual machine. I'm using the term *runner* in place of *virtual machine* because I want to
think of it more as a module that could include being run essentially directly on a real
(nonvirtual) machine. Runner is also a shorter and friendlier term than virtual machine.

The parser for pumba (and for the theoretically finished project water) is a fixed piece, although
I hope the general idea of an open compiler catches on and is used in other projects in the future.

The runner is not fixed, although I can imagine there being a default. For now, LuaJIT is a good
starting default. Natural next choices include LLVM and DynASM. Despite LLVM's popularity, I'm
leaning toward DynASM because I like the idea that the entire parser/runner suite is small and
feels lightweight.

I care about runtime speed. If DynASM turns out to be slow, then this may be a trade-off worthy of
design consideration.
For example, perhaps a productionized version of pumba will make it easy to swap in LLVM as the
runner so that the final output is a traditional binary.

## It's reasonable to skip tokenization

It's conceptually simpler, and I don't feel that I had much extra
trouble working this way.

One thing that becomes more nuanced without a tokenizer is macro implementation.
I do not yet feel that I have fully considered this problem, although for user-level grammar
changes, it seems useful to provide one or two key hook rule names, such as `statement` and
`expression`, that are or rules which may be prepended to by users.

## Modes are useful

An open compiler immediately needs at least two modes to handle both grammar specification
and whatever language it's running.

A common case that illustrates why modes are good is the distinction between parsing a string
and the usual language itself. Rather than trying to write a single regular expression to catch
a string, it's simpler to set up a rule of arbitrary complexity which can parse escape sequences
on the fly. In this case, using a different mode makes it easy to turn off ignoring whitespace.

Another case is a complex comment structure, such as a version
of C's `/*` to `*/` delimiters that respected nested comments.

## Whitespace is a special case

For a while I tried to look for a general setting in which whitespace fit well, but nothing
clicked. For example, I tried to treat whitespace and infix operators similarly as a kind of
recursive prefix stack, where you could get prefixes of forms like these:

    A <token>
    A B A <token>
    A B A C A B A <token>
    etc.

However, after the first two levels, I can't think of any use cases for this pattern. (The second
pattern, `A B A`, makes sense when `A` is whitespace and `B` is an infix operator).

In the end, what has worked best is to have a single regular expression which is parsed before each
low-level object, which is always another regular expression (and these are project water's version
of tokens). This makes it easy to handle all the major cases, such as whitespace-insensitive
languages with whitespace-sensitive strings (aka just strings; they're all whitespace-sensitive),
or languages like Python that use whitespace for indentation but otherwise don't usually care much.

## Infix operators are tricky

TODO

## Debugging a language is tricky

TODO
