# micro-expert

A little expert system for MiniScript 2: 54 facts about one imaginary family, sixteen rules
about what those facts imply, and a backward-chaining solver that answers a question
only by showing you the facts and rules that make the answer true.

```
? is-uncle-of(bill, ?p)
  is-uncle-of(bill, anna)  => rule is-uncle-of(?x, ?y) => is-parent-of(?p, ?y), is-sibling-of(?x, ?p), has-gender(?x, male)
    is-parent-of(george, anna)  => fact
    is-sibling-of(bill, george)  => rule is-sibling-of(?x, ?y) => is-parent-of(?p, ?x), is-parent-of(?p, ?y), not-equal(?x, ?y)
      is-parent-of(walter, bill)  => fact
      is-parent-of(walter, george)  => fact
    ...
  is-uncle-of(bill, anna)
  ...
```

Nothing is stored about uncles. The engine derives each answer from the facts you assert
and the rules you write, and hands back the tree of steps that got there: every leaf is a
fact, every branch names the rule it used. No weights, no API key, no network.

The full story - why a rules engine in 2026, how backward chaining and unification work
here, and where an LLM fits in front of it - is in
[docs/articles/01-a-micro-expert-in-miniscript.md](docs/articles/01-a-micro-expert-in-miniscript.md).

## Getting started

A plain clone does not carry the submodules or an interpreter, so use `--recurse-submodules`
or run `bootstrap` afterwards:

```
> git clone --recurse-submodules https://github.com/treytomes/micro-expert.git
> cd micro-expert
> bootstrap        (bootstrap.sh on Linux)
> micro-expert     (micro-expert.sh on Linux)
```

`bootstrap.bat`, and `bootstrap.sh` for Linux, are safe to re-run, and both:

- check out the five submodules: the agent skill at `.agents/skills/miniscript-2`, the
  VS Code extension at `vscode-miniscript`, and the parser, logger and repl library at
  `src/cli`, `src/logging` and `src/repl`
- download the build for the platform - `miniscript-win.zip` or
  `miniscript-linux.tar.gz`, from the
  [MiniScript 2 releases page](https://github.com/JoeStrout/miniscript2/releases) - into
  `3rd-party/`, unpack it there, and remove the archive
- write `.env` beside the runner if there is none, and leave an existing one alone

By hand, the same two steps: `git submodule update --init`, then put the absolute path to
your interpreter in a `.env`:

```
MINISCRIPT_EXE_PATH=C:\path\to\miniscript.exe
ENTRY_POINT=./src/main.ms
```

The interpreter `bootstrap.sh` unpacks on Linux has no extension, so there the second line
reads:

```
MINISCRIPT_EXE_PATH=/path/to/micro-expert/3rd-party/miniscript-linux/miniscript
ENTRY_POINT=./src/main.ms
```

`micro-expert.bat` and `micro-expert.sh` read that file, forward every argument to the
entry point, and pass the script's exit code back.

## Running a proof

```
> micro-expert
[INF] micro-expert: micro-expert 0.2.0 starting
[INF] micro-expert: Command-line arguments (0): (none)
[INF] micro-expert: depth:      8
[INF] micro-expert: verbose:    0
[INF] micro-expert: nlp:        0
[INF] micro-expert: log-level:  information
Type a fact, a question or a rule as 'head => conditions', or a value to see how it reads. /help lists the commands; /exit leaves.
? is-uncle-of(bill, ?p)
  is-uncle-of(bill, anna)
  is-uncle-of(bill, mark)
  is-uncle-of(bill, clara)
  is-uncle-of(bill, jack)
  is-uncle-of(bill, nina)
  is-uncle-of(bill, oliver)
[INF] micro-expert: micro-expert exiting with code 0
```

(timestamps trimmed for width; the fact and rule dump `--log-level debug` adds is left out)

A run also asks ipwho.is where the session is and adds that place's facts under the `session`
subject before the first question, so `? has-location(session, ?p)` answers with nothing typed
first; a machine with no network logs a warning within seconds and starts without them.

An answer is the fact that proves it. `--nlp` says each one instead: a predicate is named in
sections joined by dashes, and the sentence is that name with the dashes opened to spaces, so
`has-uncle(oliver, zed)` is said `oliver has uncle zed`.

```
> micro-expert --nlp
? is-uncle-of(bill, ?p)
  bill is uncle of anna
  bill is uncle of mark
  bill is uncle of clara
  bill is uncle of jack
  bill is uncle of nina
  bill is uncle of oliver
```

The name is where the words are - there is no second table saying what a predicate means -
which is why the shipped family names its predicates as verbs and the prepositions they need:
`has-age`, `married-to`, `is-uncle-of`, so an answer reads `bill is uncle of anna`. The
report, `/facts` and `/rules` keep the fact form either way, since each of them is something
to write back or read as data.

`--verbose` prints the proof tree before each answer, and `--nlp` says every line of it: the
facts by the same dashes-to-spaces rule, and the rule behind them as the sentences of its head
and of each condition - a constraint such as `not-equal(?x, ?y)` is the one thing left as
written, since it has no sentence to be said in.

```
> micro-expert --verbose --nlp
Verbose run: depth 8
? is-uncle-of(bill, ?p)
  bill is uncle of anna  => rule ?x is uncle of ?y => ?p is parent of ?y, ?x is sibling of ?p, ?x has gender male
    george is parent of anna  => fact
    bill is sibling of george  => rule ?x is sibling of ?y => ?p is parent of ?x, ?p is parent of ?y, not-equal(?x, ?y)
      walter is parent of bill  => fact
      walter is parent of george  => fact
    ...
  bill is uncle of anna
  ...
```

(timestamps and the header log lines trimmed again)

| Option | Meaning |
| --- | --- |
| `--depth <NUM>` | Maximum backward-chaining depth, default `8`; `0` is facts only |
| `--verbose` | Print the proof tree before each answer |
| `--nlp` | Say answers, and the trees above them, as sentences |
| `--domain <DIR>` | Folder holding `facts.kb`, `rules.kb` and `schema.kb`, default `data` |
| `--facts <FILE>` | Facts file, in place of the domain's `facts.kb` |
| `--rules <FILE>` | Rules file, in place of the domain's `rules.kb` |
| `--schema <FILE>` | Schema file, in place of the domain's `schema.kb` |
| `--log-level <TEXT>` | `debug`, `information`, `warning`, `error`, `fatal`; default `information` |
| `--help`, `-h` | Usage, generated from the same option declarations the parser uses |
| `--version`, `-v` | Version line |

`--depth 1` is a good sanity check: `is-uncle-of` is two rule levels above the facts
(`is-uncle-of` -> `is-sibling-of` -> facts), so it answers nothing and says what it would need.
`--log-level debug` prints all 54 facts as they load and all sixteen rules as they are
registered, which is the fastest way to see what the engine was actually given.

### When there is no answer

An empty answer set is not left blank: the run says so, then names the facts that would
allow an answer. Nothing here knows who Susan's parents are, so the query below reports the
shape of the fact that is missing:

```
> micro-expert
? is-parent-of(?p, susan)
  no solution found at depth 8
  A solution would need one of these:
    a fact like is-parent-of(?p, susan)
```

A query aimed at a derived relation lists each rule that could conclude it and the facts its
body would still need underneath, and `--depth` bounds that report the same way it bounds
the search.

The report is painted for a terminal: `no solution found` in red, a rule path in olive, the
facts in aqua with their variables dimmed, all through the interpreter's bundled `vt`
module. Paint is all it is - the plain text underneath is what the checks read - and setting
`NO_COLOR` turns every escape code off, for a run you mean to redirect. The logger reads
that variable the same way.

The facts are shown as you would write them, with one thing worth knowing: a rule's own
variable that would read the same as the query's is printed primed, so `?p'` is the rule's
`?p` and plain `?p` is the variable the question asked about - the report's last line says
so. A condition whose variables the facts above it would bind is tagged
`(checked once the facts above exist)` rather than listed as something to add: write down
the untagged lines, and the search decides the rest.

Each condition of a rule body is judged against what the conditions before it settled, so a
body whose conditions can each be met on their own but never all at once still has its rule
listed - with the facts its conditions would need as one set - rather than being dropped as
if no rule could conclude the query.

Ask it at the prompt:

```
? is-grandpa-of(?who, tim)
  is-grandpa-of(walter, tim)
```

Every predicate has the same shape - `relation(?x, ?y)` reads "?x is the relation of ?y" -
so `is-uncle-of(bill, ?p)` puts Bill where the uncle goes and asks who he is an uncle of: his
six nieces and nephews above, through his brothers George and Henry. Put the variable where
the unknown is: `is-grandpa-of(?who, tim)` reads "?who is the grandpa of tim" and answers
`walter`, and `is-grandma-of(?x, ?y)` lists every grandmother/grandchild pair - seven of them,
all Doris.

## A diagram of the facts

`src/mermaid.ms` turns a fact list into a [Mermaid](https://mermaid.js.org) flowchart, for a
renderer outside the program: a Markdown fence on GitHub, a docs site, the Mermaid preview in
VS Code. The schema decides the shapes. A predicate whose object field is text names another
entity, so a fact of it is drawn as an edge between two nodes; every other object is a value
that belongs to its subject, so it goes on that node's label rather than standing in the graph
as a node called `male`.

At the prompt, `/mermaid` prints what the session holds, including the facts added since it
started:

```
? /mermaid
flowchart TD
  walter["Walter<br/>male · 1948-03-14"]
  doris["Doris<br/>female · 1950-06-02"]
  bill["Bill<br/>male · 1972-01-30"]
  ...
  walter ---|married to| doris
  walter -->|is parent of| bill
  doris -->|is parent of| bill
  ...
```

With a name, it writes the diagram to that file instead of printing it, and draws the same
diagram beside it as an SVG: `sample` becomes `sample.mmd` and `sample.svg`, while a name that
already has an extension is used as it is.

```
? /mermaid sample
  wrote 40 lines to sample.mmd
  drew sample.svg
```

The `.mmd` is the Mermaid text above. The `.svg` is the same diagram laid out here rather than
by Mermaid - one row per generation, a box per node, a line per relation, an arrowhead only
where a rule does not give the relation both ways - so a picture needs no renderer installed and
no network. A relation's label is placed along its line at the first spot clear of every box and
every label already written; the document is written in three passes - every line, then every
box, then every label - so nothing is drawn after the labels to cross them; and each label
carries a white halo, so the line it sits on breaks around the words instead of through them.
A relation drawn along a row writes its label in the corridor under that row - twice inside it
before once above it - since a label above its own row reads as belonging to whatever is above. Both writes go through the repl library's temp-file-and-swap, so a write that fails
part way leaves the file it was replacing as it was.

A script calls the module with its own facts, types and rules - it holds no classes, so the copy
each module gets cannot reach it:

```miniscript
import "mermaid"
import "schema"
import "facts"
import "rules"

types = globals["schema"].build()
facts = globals["facts"].build(triples, null, types)
rules = globals["rules"].build(triples)
print globals["mermaid"].build(facts, types, rules).join(char(10))
```

`build(facts, types, rules)` answers the diagram a line at a time: `facts` is what to draw,
`types` is what the schema loaded, and `rules` is what the rules loaded. Types may be `null`,
which draws every object as a node, and rules may be left out, which keeps every arrow.
`svg(facts, types, rules)` answers the same diagram as one SVG document.

What the rules are for is the one thing a fact cannot say about itself. A rule whose head is its
own one condition with the fields swapped - `married-to(?y, ?x) => married-to(?x, ?y)` - is the
knowledge base saying a relation reads the same both ways, so a fact of that predicate is drawn
with a plain link rather than an arrow. `facts.kb` stores a marriage once, one way round, and
the reverse is what that rule adds; without a rule saying so the edge keeps its arrow, since a
stored fact does have a direction.

The rest is what the renderer needs rather than what a reader does. A name's spaces and
punctuation become underscores in its id, an id that would start with a digit gets `n_` in front
of it, and two names that spell the same id are numbered apart, so `New York` and `New_York`
stay two nodes. A quote inside a name is written `#quot;` rather than ending the label. A
predicate the schema does not name is drawn as an edge, the reading the schema itself takes of a
name it does not type, and a fact that still holds a variable is skipped: a diagram has no name
to write for `?x`.

## A session at the prompt

The program is the session. One line has one meaning: a ground line
adds a fact, a line with a variable asks a question, a line with `=>` adds a rule, and a line
starting with `/` is a command for the session itself.

```
> micro-expert --nlp
Type a fact, a question or a rule as 'head => conditions', or a value to see how it reads. /help lists the commands; /exit leaves.
? is-parent-of(?p, susan)
  no solution found at depth 8
  A solution would need one of these:
    a fact like is-parent-of(?p, susan)
  ?p = walter
  added is-parent-of(walter, susan)
  walter is parent of susan
? is-grandparent-of(?x, ?y) => is-parent-of(?x, ?p), is-parent-of(?p, ?y)
  added rule is-grandparent-of(?x, ?y) => is-parent-of(?x, ?p), is-parent-of(?p, ?y)
? is-grandparent-of(?p, tim)
  walter is grandparent of tim
  doris is grandparent of tim
```

When a question has no answer, the session reads the same report and asks for the fact that
would let a rule reach one - never for the query's own shape while a rule can still use the
fact. The fact being filled is shown above its question with the values given so far in it,
the report reads that way too, and the variables a fact brings itself are asked for one at a
time:

```
? is-uncle-of(?p, susan)
  no solution found at depth 8
  A solution would need one of these:
    a fact like is-uncle-of(?p, susan)
    through rule is-uncle-of(?x, ?y) => is-parent-of(?p, ?y), is-sibling-of(?x, ?p), has-gender(?x, male)
      is-parent-of(?p', susan)
      is-sibling-of(?p, ?p')
      has-gender(?p, male)  (checked once the facts above exist)
    (a name ending in ' is the rule's own variable, not one you asked about)
  is-parent-of(?p', susan)
  ?p' = george
  added is-parent-of(george, susan)
  is-sibling-of(?p, george)
  ?p = bill
  added is-sibling-of(bill, george)
  bill is uncle of susan
  henry is uncle of susan
```

Only the variables a fact brings itself are asked for, so `is-parent-of(?p', ?p)` asks for `?p'`
alone: `?p` is the variable the question named. When nothing else is left to fill -
`is-sibling-of(?p, george)` - the question's variable is asked for, since naming it is the only
way to complete the fact. A fact that would still be incomplete once its own variables are
filled is shown with what is left and not added, rather than writing the answer into the
knowledge base. The answers given are carried to the rest of that rule's facts, so `?p'` =
sam turns the check below it into `is-sibling-of(oliver, sam)` and the session offers to keep
that: a value given once is never asked for twice. A fact the session can already prove needs
nothing added either, so it drops out of the report rather than being listed as a gap.

Answering by fiat is still there when you want it: a whole fact typed where a value is asked
for is a fact, with the standing any typed fact has, and the question starts again from it -
so `is-uncle-of(oliver, walter)` typed at `?p' =` asserts the answer instead of deriving it.
A line that parses but still holds a variable is neither a fact nor a value, and is refused
rather than kept as a value.

A fact and a question are held to the same field types, so `has-age(?a, "27")` is refused
where it is typed: no fact could store a text age, and searching for one would only end in
a fact the same check refuses. A value that completes a refused fact ends the question
there rather than being asked for again.

A boolean and a list of values are a choice rather than a word to remember. When the schema
types a field `boolean`, or names the values it takes - `male|female` - the prompt lists
them numbered, and takes either the number or the value itself:

```
? has-gender(zed, ?g)
  no solution found at depth 8
  A solution would need one of these:
    a fact like has-gender(zed, ?g)
  1) male
  2) female
  ?g = 2
  added has-gender(zed, female)
  zed has gender female
```

The list is the schema's, so it follows the domain: another domain's `a|b|c` field is
offered with its three words. A word outside the list is refused at the prompt and asked
for again, rather than completing a fact the schema would refuse and ending the question
with it. A text field keeps the plain prompt, since there is nothing to choose from, and a
number field keeps it too - but the digits typed there are the number they spell, so
`has-age(?n, 24)` completes a fact the schema takes, rather than refusing `"24"` as an age.

A field can also be typed `date`, `time` or `datetime`, and then a fact stores one as text
in the one shape the type fixes - `2019-04-01`, `09:30:00`, `2019-04-01 09:30:00`. A value
written any other way, or a day the calendar does not have, is refused like any other misfit.
`src/temporal.ms` can read a fitting value into a `DateTime`, which formats it, moves it by
seconds, orders it against another of its kind and measures the span to one, so a script
working with a stored fact has the value and not only its text.

`unique(...)` around a field's type says how many values the pair takes, so
`has-birthdate(text, unique(date))` is one birthdate per person: setting a second one corrects the
first rather than sitting beside it, and the corrected fact stands where the old one stood,
since search tries facts in the order they are held. The check is against the facts rather
than the value - 17 fits an age wherever it stands - so the same one is applied by the facts
loader to a whole file, which is why `data/schema.kb` is read before `data/facts.kb`.
`unique(text)` in the subject position is the other direction: one subject per object. A
predicate a rule concludes is never added, so it cannot carry `unique(...)`: a schema line
that marks one is refused when the program starts, and `/load-schema`, `/load-rules` and a
typed rule line refuse it too, so the prompt is not a way around the check.

```
? has-gender(zed, male)
  added has-gender(zed, male)
? has-gender(zed, female)
  replaced has-gender(zed, male) with has-gender(zed, female)
```

A fact can also be taken out by name, wherever it stands, which is more than `/undo`'s last
change reaches:

```
? /retract has-birthdate(tim, 2002-04-05)
  retracted has-birthdate(tim, 2002-04-05)
```

It works at a value prompt too, the way `/undo` does - a fact taken out there puts the
question again from the knowledge base it left - and a name the session does not hold says
so without ending the question.

A fact that needs no variable at all is offered with `add it? [y/N]` rather than assumed, and
a value left empty stops the asking with the report standing. `/undo` takes back the last
change - an added fact, a value that replaced one, or a retraction - at the prompt, or in the
middle of a question, which puts the question again, so a wrong value does not stick for the
rest of the run. Nothing is written back by
itself: the session adds to the arrays `src/main.ms` built, and `/save-*` is what puts a
component back on disk when you ask it to. A rule is read from the line `Rule.text` prints, and a line that
will not parse is refused with itself quoted. `--depth` bounds the session's search the way
it bounds a run, `--verbose` prints the proof tree before each answer here too, and `--nlp` says
the answers and those trees in words.

| Command | Meaning |
| --- | --- |
| `/exit` | Leave the session |
| `/help [NAME]` | List the commands, or print one command's line |
| `/undo` | Take back the last change: an added fact, a replacement, or a retraction |
| `/retract <FACT>` | Take a stored fact out, wherever it stands |
| `/facts` | List the facts the session holds |
| `/rules` | List the rules the session holds |
| `/mermaid [FILE]` | Draw the facts as a Mermaid flowchart, or write the diagram and its picture to a file |
| `/depth` | Say how deep the search goes |
| `/save-facts [FILE]` | Write the facts to their file, or to the file named |
| `/load-facts [FILE]` | Replace the facts with a file's |
| `/save-rules [FILE]` | Write the rules to their file, or to the file named |
| `/load-rules [FILE]` | Replace the rules with a file's |
| `/save-schema [FILE]` | Write the schema to its file, or to the file named |
| `/load-schema [FILE]` | Replace the schema with a file's |

A save or load takes its file from the line, and a path with a space in it is quoted -
`'my notes.kb'` - since what follows a command that declares parameters is split into words.

The session paints from the same style table as the report - a bold prompt, olive additions,
green answers - so `NO_COLOR` turns the whole run plain, prompt included.

## Setting up your own facts and rules

The family is only data. `data/facts.kb` holds the facts, `data/rules.kb` the rules, and
`data/schema.kb` the type of each predicate's fields, and nothing else in the repo knows
what a family is. Those three files are a domain: rewrite them, in `data/` or in a folder
of their own, and the engine answers questions about invoices or network devices instead
of aunts.

Both are loaded through a `build` function instead of a top-level array, and `src/main.ms`
hands its copy of the solver in:

```miniscript
import "facts"
import "rules"

// The arrays themselves, not the module maps that hold them.
facts = globals["facts"].build(triples)
rules = globals["rules"].build(triples)
```

That is not ceremony. A module that imports `triples.ms` gets its own copy of its classes,
and `isa` checks only agree inside one copy, so a loader that imported `triples.ms`
directly would build triples the solver does not recognize. The data sidestep it another
way: both files are text, and `src/knowledge.ms` parses them with the copy it is handed.

A domain folder holds the three files by those names, and `--domain` reads them from
there. One component can be replaced with `--facts`, `--rules` or `--schema`, which wins
over the folder's file of that name while the folder supplies the other two:

```
> micro-expert --domain domains/invoices
> micro-expert --domain domains/invoices --facts ~/draft-facts.kb
```

With no option the folder is `data/`. At the prompt, `/save-facts`, `/save-rules` and
`/save-schema` write a component back to the file it came from, or to a file named, and
`/load-facts`, `/load-rules` and `/load-schema` read one back in its place; a bare name
gets `.kb`. A save writes a temp file and swaps it in when it is whole, so a save that
fails part way through leaves the file it was writing as it was; the only file it removes
is the temp file it wrote itself.

A fact is one triple per line, `predicate(subject, object)`:

```prolog
is-parent-of(walter, bill)
has-gender(bill, male)
has-birthdate(bill, 1972-01-30)
```

A predicate is named in lower case, in sections joined by dashes, each section letters and
numbers, and the first section starting with a letter: `is-parent-of`, `has-1-child`,
`married-to`. A line that names one another way is refused where it is read, in a data file
and at the prompt alike - a rule's head and its conditions included - and the schema's lines
are held to the same shape, so the knowledge base holds only names a result can say, and the
name is where the words of that result come from.

A rule is one line of `data/rules.kb`: a head - the one triple it can prove - and a body
of conditions that must all hold first. The body is a comma-delimited list, which is an
implied `and`, or `and(...)` around the same list:

```prolog
is-uncle-of(?x, ?y) => and(is-parent-of(?p, ?y), is-sibling-of(?x, ?p), has-gender(?x, male))
is-uncle-of(?x, ?y) => is-parent-of(?p, ?y), is-sibling-of(?x, ?p), has-gender(?x, male)
```

A condition is a fact or a constraint such as `not-equal(?x, ?y)`, `equal(?n, 18)` or
`less-than-or-equal(?n, 18)`. `and(...)` nests, an entry may
run over several lines inside its parentheses, and `or(...)` holds alternatives - any one
of them may hold instead, so a rule that could be written two ways is still one line:

```prolog
is-in-law-of(?x, ?y) => or(and(married-to(?x, ?p), is-sibling-of(?p, ?y)), and(is-sibling-of(?x, ?p), married-to(?p, ?y)))
```

`not(...)` holds a body that must have no proof, so a rule can ask for an absence; it takes
one condition, and `not(and(a, b))` negates several. `equal` is the one constraint that can
bind as well as check: a side that is still a variable takes the other side's value, so
`shares-age-group-with` reaches the second age group through the first group's word. A
comparison is arithmetic rather than text: both sides have to be numbers, and a name never
passes for a zero. A constraint's
name is a shape a body checks, not a predicate a fact stores or a question asks, so
`less-than-or-equal(5, 3)` typed at the prompt is refused rather than kept as a fact. A number is
written as one, exponent and all - `1e3` is a thousand - and the digits are checked on
both sides of the `e`, so `1e` stays text.

The seven built-in constraint names, and what each one does with a field that is still a
variable, are in [docs/constraints.md](docs/constraints.md).

```prolog
has-age(?x, ?n) => and(has-birthdate(?x, ?b), years-since(?b, ?n))
is-only-child-of(?x, ?y) => and(is-parent-of(?y, ?x), not(is-sibling-of(?x, ?q)))
belongs-to-age-group(?x, child) => and(has-age(?x, ?n), less-than-or-equal(?n, 18))
belongs-to-age-group(?x, adult) => and(has-age(?x, ?n), not(belongs-to-age-group(?x, child)))
shares-age-group-with(?x, ?y) => and(belongs-to-age-group(?x, ?g), equal(?g, ?h), belongs-to-age-group(?y, ?h), not-equal(?x, ?y))
```

Facts and rules share the parser, so a fact may be added to `data/facts.kb` the same way a
rule is added below.

To add a rule:

1. Add its line to `data/rules.kb`.
2. Add a check to `test/relations.ms` that asserts both a positive and a negative case.
3. If it names a predicate `data/schema.kb` does not type, add its line there, so the
   prompt can refuse a value no rule could use. Every predicate the rules name is typed,
   not only the ones that store facts.

For example, grandparenthood from the child's side:

```prolog
grandis-child-of(?x, ?y) => and(is-parent-of(?p, ?x), is-parent-of(?y, ?p))
```

## Running the tests

The suite needs the same interpreter your `.env` points at; `3rd-party/` is gitignored, so
there is no checked-in binary to fall back on.

```
> "%MINISCRIPT_EXE_PATH%" test\run.ms
1152 passed, 0 failed
```

`micro-expert.bat` and `micro-expert.sh` read that variable out of `.env`; a plain shell
does not, so `set` it for the session or paste the path in its place. One caveat worth knowing: in this
interpreter an uncaught runtime error still exits `0`, so the `N passed, M failed` line is
the real signal, not the exit code.

A test runner asks for part of the suite instead, and `test/harness.ms` gives it a line
per check to read:

```
> "%MINISCRIPT_EXE_PATH%" test\run.ms --json --file session.ms --filter "a rule line parses"
PASS  a rule line parses
##TEST {"name":"a rule line parses","status":"pass","file":"session.ms","line":31}

1 passed, 0 failed, 1151 skipped
##END {"passed":1,"failed":0,"skipped":1151}
```

`--filter` takes a substring of a check's name, `--file` the name of a case module, and
`--json` the records; a check runs when it matches any of each that are given. The `##END`
line is the one the exit code cannot give you - see the caveat above - so it is what says
the suite reached the end. The VS Code extension's Testing panel passes exactly these
arguments, so its tree and its runs come from the suite rather than from a list kept
beside it.

The parser, the logger and the repl library are their own repositories with their own suites
(32, 56 and 52 checks). Each is run from its own folder - `src/cli`, `src/logging`, `src/repl` -
by the same interpreter, and this suite imports none of them. It keeps one check about the
repl library, and that one is about this repository rather than the library: `examples/notes.ms`
is a whole program written on the library and nothing else, and `test/repl.ms` is what says so.
The 1152 cover the program itself: display and parsing (71), the knowledge data format (141),
the predicate schema (48), the date and time types (79), the loaders (21), proofs and
explanations (23), the missing-fact report (34), recursion and cycle handling (13), relations
including the family rules (104), the session at the prompt (202), the notebook's cells (30),
the notes example on the repl library (1), the command line (6), the domain (10), the Mermaid
diagram (49), the id generator (21), the location module (23), the declared writer (29), the geocode mapping (22), the Open-Meteo mapping (22), and the API layer's argument split,
parameter engine, both services' and ipwho.is's reply classes, and .env reader (203).

## Repository layout

```
src/main.ms          logging, and the session at the prompt
src/options.ms       the option table a run declares
src/session.ms       the session's knowledge side: facts, rules, questions
src/engine.ms        the domain's three files read into that session
src/notebook.ms      that session served to a notebook's cells
src/triples.ms       the solver: terms, unification, search, proofs
src/rule.ms          the Rule class
src/knowledge.ms     the reader and writer for the facts, rules and schema data
src/temporal.ms      the date, time and datetime types, and the calendar behind them
src/facts.ms         loads the facts
src/rules.ms         loads the rules
src/schema.ms        loads the field types
src/domain.ms        places a domain's facts, rules and schema
src/mermaid.ms       the facts as a Mermaid flowchart
data/facts.kb        the 54 facts, as text
data/rules.kb        the sixteen rules, as text
data/schema.kb       the field types, as text
examples/notes.ms    a whole host for the repl library that is not a knowledge base
examples/explore.msnb  a MiniScript notebook that loads the family knowledge base
src/cli/             submodule: micro-cli, the argument parser
src/logging/         submodule: micro-logging, the logger
src/repl/            submodule: micro-repl, the loop and its commands
test/                the 1152 checks and their runner
docs/articles/       the long-form write-up
docs/kb-grammar.md   the .kb grammar, its constraints and its schema
docs/constraints.md  the seven built-in constraints, one by one
vscode-knowledge/    the .kb highlight extension and the .kbnb notebook
bootstrap.bat        submodules, interpreter, .env
bootstrap.sh         the same for Linux
micro-expert.bat     runs the entry point named in .env
micro-expert.sh      the same for Linux
build-ext.bat        builds the MiniScript 2 extension into a .vsix
build-ext.sh         the same for Linux
build-kb-ext.bat     builds the knowledge extension into a .vsix
build-kb-ext.sh      the same for Linux
```

The other two submodules are tooling rather than program code: `vscode-miniscript` is the
MiniScript 2 language extension, which also opens in VS Code on its own with `F5`, and
`.agents/skills/miniscript-2` is an agent skill describing the language for coding
assistants. `vscode-knowledge` is a small extension of our own that highlights the `.kb`
data files and opens a `.kbnb` notebook, one cell at a time against the engine; open it in
VS Code and press `F5` the same way.

## License

MIT - see [LICENSE](LICENSE). Copyright © 2026 Trey Tomes.
