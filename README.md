# micro-expert

A little expert system for MiniScript 2: 54 facts about one imaginary family, fourteen rules
about what those facts imply, and a backward-chaining solver that answers a question
only by showing you the facts and rules that make the answer true.

```
? uncle-of(bill, ?p)
  uncle-of(bill, anna)  <- rule uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
    parent-of(george, anna)  <- fact
    sibling-of(bill, george)  <- rule sibling-of(?x, ?y) <- parent-of(?p, ?x), parent-of(?p, ?y), not-equal(?x, ?y)
      parent-of(walter, bill)  <- fact
      parent-of(walter, george)  <- fact
    ...
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

- check out the four submodules: the agent skill at `.agents/skills/miniscript-2`, the
  VS Code extension at `vscode-miniscript`, and the parser and logger at `src/cli` and
  `src/logging`
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
[INF] micro-expert: log-level:  information
Type a fact, a question, or a rule as 'head <- conditions'. /help lists the commands; /exit leaves.
? uncle-of(bill, ?p)
  uncle-of(bill, anna)
  uncle-of(bill, mark)
  uncle-of(bill, clara)
  uncle-of(bill, jack)
  uncle-of(bill, nina)
  uncle-of(bill, oliver)
[INF] micro-expert: micro-expert exiting with code 0
```

(timestamps trimmed for width; the fact and rule dump `--log-level debug` adds is left out)

That is the answer set. `--verbose` adds the proof tree behind each one:

```
> micro-expert --verbose
Verbose run: depth 8
? uncle-of(bill, ?p)
  uncle-of(bill, anna)  <- rule uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
    parent-of(george, anna)  <- fact
    sibling-of(bill, george)  <- rule sibling-of(?x, ?y) <- parent-of(?p, ?x), parent-of(?p, ?y), not-equal(?x, ?y)
      parent-of(walter, bill)  <- fact
      parent-of(walter, george)  <- fact
    ...
  ...
```

(timestamps and the header log lines trimmed again)

| Option | Meaning |
| --- | --- |
| `--depth <NUM>` | Maximum backward-chaining depth, default `8`; `0` is facts only |
| `--verbose` | Print the proof tree behind each answer |
| `--domain <DIR>` | Folder holding `facts.kb`, `rules.kb` and `schema.kb`, default `data` |
| `--facts <FILE>` | Facts file, in place of the domain's `facts.kb` |
| `--rules <FILE>` | Rules file, in place of the domain's `rules.kb` |
| `--schema <FILE>` | Schema file, in place of the domain's `schema.kb` |
| `--log-level <TEXT>` | `debug`, `information`, `warning`, `error`, `fatal`; default `information` |
| `--help`, `-h` | Usage, generated from the same option declarations the parser uses |
| `--version`, `-v` | Version line |

`--depth 1` is a good sanity check: `uncle-of` is two rule levels above the facts
(`uncle-of` -> `sibling-of` -> facts), so it answers nothing and says what it would need.
`--log-level debug` prints all 54 facts as they load and all fourteen rules as they are
registered, which is the fastest way to see what the engine was actually given.

### When there is no answer

An empty answer set is not left blank: the run says so, then names the facts that would
allow an answer. Nothing here knows who Susan's parents are, so the query below reports the
shape of the fact that is missing:

```
> micro-expert
? parent-of(?p, susan)
  no solution found at depth 8
  A solution would need one of these:
    a fact like parent-of(?p, susan)
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
? grandpa-of(?who, tim)
  grandpa-of(walter, tim)
```

Every predicate has the same shape - `relation(?x, ?y)` reads "?x is the relation of ?y" -
so `uncle-of(bill, ?p)` puts Bill where the uncle goes and asks who he is an uncle of: his
six nieces and nephews above, through his brothers George and Henry. Put the variable where
the unknown is: `grandpa-of(?who, tim)` reads "?who is the grandpa of tim" and answers
`walter`, and `grandma-of(?x, ?y)` lists every grandmother/grandchild pair - seven of them,
all Doris.

## A session at the prompt

The program is the session. One line has one meaning: a ground line
adds a fact, a line with a variable asks a question, a line with `<-` adds a rule, and a line
starting with `/` is a command for the session itself.

```
> micro-expert
Type a fact, a question, or a rule as 'head <- conditions'. /help lists the commands; /exit leaves.
? parent-of(?p, susan)
  no solution found at depth 8
  A solution would need one of these:
    a fact like parent-of(?p, susan)
  ?p = walter
  added parent-of(walter, susan)
  parent-of(walter, susan)
? grandparent(?x, ?y) <- parent-of(?x, ?p), parent-of(?p, ?y)
  added rule grandparent(?x, ?y) <- parent-of(?x, ?p), parent-of(?p, ?y)
? grandparent(?p, tim)
  grandparent(walter, tim)
  grandparent(doris, tim)
```

When a question has no answer, the session reads the same report and asks for the fact that
would let a rule reach one - never for the query's own shape while a rule can still use the
fact. The fact being filled is shown above its question with the values given so far in it,
the report reads that way too, and the variables a fact brings itself are asked for one at a
time:

```
? uncle-of(?p, susan)
  no solution found at depth 8
  A solution would need one of these:
    a fact like uncle-of(?p, susan)
    through rule uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
      parent-of(?p', susan)
      sibling-of(?p, ?p')
      has-gender(?p, male)  (checked once the facts above exist)
    (a name ending in ' is the rule's own variable, not one you asked about)
  parent-of(?p', susan)
  ?p' = george
  added parent-of(george, susan)
  sibling-of(?p, george)
  ?p = bill
  added sibling-of(bill, george)
  uncle-of(bill, susan)
  uncle-of(henry, susan)
```

Only the variables a fact brings itself are asked for, so `parent-of(?p', ?p)` asks for `?p'`
alone: `?p` is the variable the question named. When nothing else is left to fill -
`sibling-of(?p, george)` - the question's variable is asked for, since naming it is the only
way to complete the fact. A fact that would still be incomplete once its own variables are
filled is shown with what is left and not added, rather than writing the answer into the
knowledge base. The answers given are carried to the rest of that rule's facts, so `?p'` =
sam turns the check below it into `sibling-of(oliver, sam)` and the session offers to keep
that: a value given once is never asked for twice. A fact the session can already prove needs
nothing added either, so it drops out of the report rather than being listed as a gap.

Answering by fiat is still there when you want it: a whole fact typed where a value is asked
for is a fact, with the standing any typed fact has, and the question starts again from it -
so `uncle-of(oliver, walter)` typed at `?p' =` asserts the answer instead of deriving it.
A line that parses but still holds a variable is neither a fact nor a value, and is refused
rather than kept as a value.

A fact and a question are held to the same field types, so `has-age(?a, "27")` is refused
where it is typed: no fact could store a text age, and searching for one would only end in
a fact the same check refuses. A value that completes a refused fact ends the question
there rather than being asked for again.

A fact that needs no variable at all is offered with `add it? [y/N]` rather than assumed, and
a value left empty stops the asking with the report standing. `/undo` takes back the last
fact the session added - at the prompt, or in the middle of a question, which puts the
question again - so a wrong value does not stick for the rest of the run. Nothing is written back by
itself: the session adds to the arrays `src/main.ms` built, and `/save-*` is what puts a
component back on disk when you ask it to. A rule is read from the line `Rule.text` prints, and a line that
will not parse is refused with itself quoted. `--depth` bounds the session's search the way
it bounds a run, and `--verbose` prints the proof tree behind each answer here too.

| Command | Meaning |
| --- | --- |
| `/exit` | Leave the session |
| `/help` | List the commands |
| `/undo` | Take back the last fact the session added |
| `/facts` | List the facts the session holds |
| `/rules` | List the rules the session holds |
| `/save-facts [FILE]` | Write the facts to their file, or to the file named |
| `/load-facts [FILE]` | Replace the facts with a file's |
| `/save-rules [FILE]` | Write the rules to their file, or to the file named |
| `/load-rules [FILE]` | Replace the rules with a file's |
| `/save-schema [FILE]` | Write the schema to its file, or to the file named |
| `/load-schema [FILE]` | Replace the schema with a file's |

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
parent-of(walter, bill)
has-gender(bill, male)
has-age(bill, 54)
```

A rule is one line of `data/rules.kb`: a head - the one triple it can prove - and a body
of conditions that must all hold first. The body is a comma-delimited list, which is an
implied `and`, or `and(...)` around the same list:

```prolog
uncle-of(?x, ?y) => and(parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male))
uncle-of(?x, ?y) => parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
```

A condition is a fact or a constraint such as `not-equal(?x, ?y)`, `equal(?n, 18)` or
`less-than-or-equal(?n, 18)`. `and(...)` nests, an entry may
run over several lines inside its parentheses, and `or(...)` holds alternatives - any one
of them may hold instead, so a rule that could be written two ways is still one line:

```prolog
in-law-of(?x, ?y) => or(and(married-to(?x, ?p), sibling-of(?p, ?y)), and(sibling-of(?x, ?p), married-to(?p, ?y)))
```

`not(...)` holds a body that must have no proof, so a rule can ask for an absence; it takes
one condition, and `not(and(a, b))` negates several. `equal` is the one constraint that can
bind as well as check: a side that is still a variable takes the other side's value, so
`same-age-group-as` reaches the second age group through the first group's word. A
comparison is arithmetic rather than text: both sides have to be numbers, and a name never
passes for a zero. A constraint's
name is a shape a body checks, not a predicate a fact stores or a question asks, so
`less-than-or-equal(5, 3)` typed at the prompt is refused rather than kept as a fact. A number is
written as one, exponent and all - `1e3` is a thousand - and the digits are checked on
both sides of the `e`, so `1e` stays text.

```prolog
only-child-of(?x, ?y) => and(parent-of(?y, ?x), not(sibling-of(?x, ?q)))
age-group(?x, child) => and(has-age(?x, ?n), less-than-or-equal(?n, 18))
age-group(?x, adult) => and(has-age(?x, ?n), not(age-group(?x, child)))
same-age-group-as(?x, ?y) => and(age-group(?x, ?g), equal(?g, ?h), age-group(?y, ?h), not-equal(?x, ?y))
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
grandchild-of(?x, ?y) => and(parent-of(?p, ?x), parent-of(?y, ?p))
```

## Running the tests

The suite needs the same interpreter your `.env` points at; `3rd-party/` is gitignored, so
there is no checked-in binary to fall back on.

```
> "%MINISCRIPT_EXE_PATH%" test\run.ms
447 passed, 0 failed
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

1 passed, 0 failed, 446 skipped
##END {"passed":1,"failed":0,"skipped":446}
```

`--filter` takes a substring of a check's name, `--file` the name of a case module, and
`--json` the records; a check runs when it matches any of each that are given. The `##END`
line is the one the exit code cannot give you - see the caveat above - so it is what says
the suite reached the end. The VS Code extension's Testing panel passes exactly these
arguments, so its tree and its runs come from the suite rather than from a list kept
beside it.

The parser and the logger are their own repositories with their own suites (32 checks and 56 respectively), and the 447 here cover the program itself: display and parsing (22), the
knowledge data format (78), the predicate schema (25), the loaders (16), proofs and
explanations (21), the missing-fact report (34), recursion and cycle handling (13), relations
including the family rules (89), the session at the prompt (102), the repl library itself
(37), and the domain (10).

## Repository layout

```
src/main.ms          options, logging, and the session at the prompt
src/repl/repl.ms     the loop, the commands and the component save, with no domain in them
src/session.ms       the session's knowledge side: facts, rules, questions
src/triples.ms       the solver: terms, unification, search, proofs
src/rule.ms          the Rule class
src/knowledge.ms     the reader and writer for the facts, rules and schema data
src/facts.ms         loads the facts
src/rules.ms         loads the rules
src/schema.ms        loads the field types
src/domain.ms        places a domain's facts, rules and schema
data/facts.kb        the 54 facts, as text
data/rules.kb        the fourteen rules, as text
data/schema.kb       the field types, as text
examples/notes.ms    a whole host for the repl library that is not a knowledge base
src/cli/             submodule: micro-cli, the argument parser
src/logging/         submodule: micro-logging, the logger
test/                the 447 checks and their runner
docs/articles/       the long-form write-up
vscode-knowledge/    the .kb syntax-highlighting extension
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
data files; open it in VS Code and press `F5` the same way.

## License

MIT - see [LICENSE](LICENSE). Copyright © 2026 Trey Tomes.
