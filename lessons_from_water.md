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

I tried many ideas to set up an elegant infix-operator notation.

Infix notation is so common that I don't think grammar-writers should have to jump through
hoops to specify general expressions with precedence of operators. Programmers already think
clearly in terms of a general idea of an expression, and that is built on top of various
*n*-ary functions which are interpreted in a certain order based on the operators and their
positions in the syntax.

This convenience is to be balanced with the simplicity of both the core grammar api itself, and
how much work the lowest layers of grammar have to perform in order to expose the convenient
version of the interface.

In the end, my favorite core syntax for performing this was to accept a core syntax like this:

    infix_item@regular_item

which is shorthand for:

    space infix_item space regular_item

The language-designer-facing syntax can then be:

    item+infix

which translates to:

    item infix@item | item

Similarly,

    item*infix

translates to:

    item+infix | Empty

To be honest, I'd really like the language-designer to have an easier time specifying
precedence of operators from here, so I may continue to work on this syntax. Always keep in
mind, though, that my goal is *not* simply to make life easy for the language-specifier, but to
keep the entire system, top to bottom, as simple as possible. I feel that design philosophy
results in superior long-term usage.

## Debugging a language is tricky

Writing an open compiler means creating tools for a set of users
you don't usually have to design for - language creators.

There seem to be two primary steps in formally specifying a
language. First you must specify the grammar, and second you
must indicate how the resulting abstract syntrax tree is run.

Project water used a `dbg` module with color-coded output that
could be toggled independently. The major categories of output
were:

category | description
---------|-------------
tree     | the parse tree as it is parsed
parse    | key parse calls with their parameters
public   | public parse calls
error    | errors
phrase   | every phrase (top-level tree) parsed
run      | strings sent to the run-time engine

When some code was not being parsed as a language creator
expected, they could turn on a subset of the above streams
to see at a lower level where their expectations differred
from the compiler's behavior.

Another aspect of helping language creators was to ease
the presentation of a user's syntax errors to that user.
This is a case where both the compiler and the language
designer would be technically doing the right thing, and
the end-user the wrong thing, yet we still care
about making life easy for the end-user.
(It's kind of funny that the default assumption in
developer culture in this case is to not care beyond
some minimal error report.)

Here is a key comment on the `parse_info` variable
used to present more useful error information to
end-users:

```
# parse_info stores parse attempt data so we can display human-friendly error
# information that simplifies debugging grammars and syntax errors alike.
#
# parse_info.attempts         = [list of parse_attempt Objects]
# parse_info.main_attempt     = the parse_attempt we suspect was intended
# parse_info.code             = the code string being parsed
# parse_info.phrase_start_pos = the last pos where a phrase parse began
#
# attempt.stack     = list of rule names in the attempt, phrase-first
# attempt.start_pos = byte index of where parse stack began parsing
# attempt.fail_pos  = byte index of where the last stack token mismatched
```

TODO Refine this stuff on `parse_info`.
I'm not sure that comment actually matches the latest code
in project water. Also, it may belong in its own section
of this file.
