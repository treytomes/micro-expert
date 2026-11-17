# micro-expert

A little expert system for MiniScript 2: 54 facts about one imaginary family, nine rules
about what those facts imply, and a backward-chaining solver that answers a question
only by showing you the facts and rules that make the answer true.

```
Query: uncle-of(bill, ?p)
  uncle-of(bill, anna)  <- rule uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
    parent-of(george, anna)  <- fact
    sibling-of(bill, george)  <- rule sibling-of(?x, ?y) <- parent-of(?p, ?x), parent-of(?p, ?y), ?x != ?y
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
[docs/01-a-micro-expert-in-miniscript.md](docs/01-a-micro-expert-in-miniscript.md).

## Getting started

A plain clone does not carry the submodules or an interpreter, so use `--recurse-submodules`
or run `bootstrap` afterwards:

```
> git clone --recurse-submodules https://github.com/treytomes/micro-expert.git
> cd micro-expert
> bootstrap
> micro-expert
```

`bootstrap.bat` is safe to re-run, and it:

- checks out the four submodules: the agent skill at `.agents/skills/miniscript-2`, the
  VS Code extension at `vscode-miniscript`, and the parser and logger at `src/cli` and
  `src/logging`
- downloads `miniscript-win.zip` from the
  [MiniScript 2 releases page](https://github.com/JoeStrout/miniscript2/releases) into
  `3rd-party/`, unpacks it there, and removes the archive
- writes `.env` beside the runner if there is none, and leaves an existing one alone

By hand, the same two steps: `git submodule update --init`, then put the absolute path to
your interpreter in a `.env`:

```
MINISCRIPT_EXE_PATH=C:\path\to\miniscript.exe
ENTRY_POINT=./src/main.ms
```

`micro-expert.bat` reads that file, forwards every argument to the entry point, and passes
the script's exit code back.

## Running a proof

```
> micro-expert
[INF] micro-expert: micro-expert 0.1.0 starting
[INF] micro-expert: Command-line arguments (0): (none)
[INF] micro-expert: depth:      8
[INF] micro-expert: verbose:    0
[INF] micro-expert: log-level:  information
Query: uncle-of(bill, ?p)
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
Query: uncle-of(bill, ?p)
  uncle-of(bill, anna)  <- rule uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
    parent-of(george, anna)  <- fact
    sibling-of(bill, george)  <- rule sibling-of(?x, ?y) <- parent-of(?p, ?x), parent-of(?p, ?y), ?x != ?y
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
| `--log-level <TEXT>` | `debug`, `information`, `warning`, `error`, `fatal`; default `information` |
| `--help`, `-h` | Usage, generated from the same option declarations the parser uses |
| `--version`, `-v` | Version line |

`--depth 1` is a good sanity check: `uncle-of` is two rule levels above the facts
(`uncle-of` -> `sibling-of` -> facts), so it answers nothing and says what it would need.
`--log-level debug` prints all 54 facts as they load and all nine rules as they are
registered, which is the fastest way to see what the engine was actually given.

### When there is no answer

An empty answer set is not left blank: the run says so, then names the facts that would
allow an answer. Nothing here knows who Susan's parents are, so the query below reports the
shape of the fact that is missing:

```
> micro-expert
Query: parent-of(?p, susan)
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

The question lives at the bottom of `src/main.ms`:

```miniscript
runQuery fact("bill", "uncle-of", var("?p"))
```

Every predicate has the same shape - `relation(?x, ?y)` reads "?x is the relation of ?y" -
so `uncle-of(bill, ?p)` puts Bill where the uncle goes and asks who he is an uncle of: his
six nieces and nephews above, through his brothers George and Henry. Put the variable where
the unknown is: `fact(var("who"), "grandpa-of", "tim")` reads "?who is the grandpa of tim"
and answers `walter`, and `fact(var("x"), "grandma-of", var("y"))` lists every
grandmother/grandchild pair - seven of them, all Doris.

## Setting up your own facts and rules

The family is only data. `src/facts.ms` and `src/rules.ms` are the knowledge base, and
nothing else in the repo knows what a family is, so a new domain means rewriting those two
files and changing the query.

Both files expose a `build` function instead of a top-level array, and `src/main.ms` hands
its copy of the solver in:

```miniscript
import "facts"
import "rules"

// The arrays themselves, not the module maps that hold them.
facts = globals["facts"].build(triples)
rules = globals["rules"].build(triples)
```

That is not ceremony. A module that imports `triples.ms` gets its own copy of its classes,
and `isa` checks only agree inside one copy, so a facts file that imported `triples.ms`
directly would build triples the solver does not recognise.

A fact is one triple, written with the local `fact(subject, predicate, object)` shorthand:

```miniscript
fact("walter", "parent-of", "bill"),
fact("bill", "has-gender", "male"),
```

A rule is a head - the one triple it can prove - and a body of conditions that must all
hold first. Three steps to add one:

1. Write it in `src/rules.ms` with the local `rule(head, body)` helper, and put the Lisp
   form in the comment above it.
2. Add it to the array `build` returns.
3. Add a check to `test/relations.ms` that asserts both a positive and a negative case.

```miniscript
// (<- (grandchild-of ?x ?y) (parent-of ?p ?x) (parent-of ?y ?p)): ?y is a grandparent
// of ?x when ?y is a parent of ?x's parent.
grandchildOf = rule(
	fact(var("x"), "grandchild-of", var("y")),
	[fact(var("p"), "parent-of", var("x")), fact(var("y"), "parent-of", var("p"))])
```

## Running the tests

The suite needs the same interpreter your `.env` points at; `3rd-party/` is gitignored, so
there is no checked-in binary to fall back on.

```
> "%MINISCRIPT_EXE_PATH%" test\run.ms
112 passed, 0 failed
```

`micro-expert.bat` reads that variable out of `.env`; a plain shell does not, so `set` it
for the session or paste the path in its place. One caveat worth knowing: in this
interpreter an uncaught runtime error still exits `0`, so the `N passed, M failed` line is
the real signal, not the exit code.

The parser and the logger are their own repositories with their own suites (32 checks and
56 respectively), and the 112 here cover the program itself: display and parsing (12),
proofs and explanations (19), the missing-fact report (22), recursion and cycle handling
(13), and relations including the family rules (46).

## Repository layout

```
src/main.ms          options, logging, and the query at the bottom
src/triples.ms       the solver: terms, unification, search, proofs
src/rule.ms          the Rule class
src/facts.ms         the 54 facts
src/rules.ms         the nine rules
src/cli/             submodule: micro-cli, the argument parser
src/logging/         submodule: micro-logging, the logger
test/                the 112 checks and their runner
docs/                the long-form write-up
bootstrap.bat        submodules, interpreter, .env
micro-expert.bat     runs the entry point named in .env
```

The other two submodules are tooling rather than program code: `vscode-miniscript` is the
MiniScript 2 language extension, which also opens in VS Code on its own with `F5`, and
`.agents/skills/miniscript-2` is an agent skill describing the language for coding
assistants.

## License

MIT - see [LICENSE](LICENSE). Copyright © 2026 Trey Tomes.
