# Introduction

micro-expert is a small expert system written in MiniScript 2. It holds a knowledge base of facts
and rules, and it answers questions by proving them from that knowledge base. Nothing about the
answer is stored in advance: the engine derives it when you ask, and it can show you the exact
facts and rule applications that make it true.

The project ships with one domain: an imaginary family of fifteen people, described by 54 facts
and reasoned about with sixteen rules. That family is only data. The engine itself knows nothing
about parents, uncles, or ages, and it can answer questions about any domain you can express as
triples.

## The three pieces

A domain is three text files.

| File | What it holds | Example |
| --- | --- | --- |
| `facts.kb` | Ground statements, one triple per line | `is-parent-of(walter, bill)` |
| `rules.kb` | What follows from the facts, one rule per line | `is-uncle-of(?x, ?y) => ...` |
| `schema.kb` | The type of each predicate's two fields | `has-birthdate(text, unique(date))` |

A **fact** is a triple `predicate(subject, object)`. Read it as "subject is the predicate of
object", so `is-parent-of(walter, bill)` is "walter is parent of bill" and
`has-gender(bill, male)` is "bill has gender male". The predicate name carries the words; there is
no second table saying what it means.

A **rule** has a head — the one triple it can prove — and a body of conditions that must all hold
first:

```prolog
is-uncle-of(?x, ?y) => and(is-parent-of(?p, ?y), is-sibling-of(?x, ?p), has-gender(?x, male))
```

Read the arrow as "proves": `?x` is an uncle of `?y` when `?p` is a parent of `?y`, `?x` is a
sibling of `?p`, and `?x` has gender male. The `?` names are variables, shared across the head and
the body.

A **question** is the same triple shape with variables where you want answers. `?` is also the
program's prompt character, so a session looks like this — the first `?` on each line is the prompt:

```text
? is-uncle-of(bill, ?p)
  bill is uncle of anna
  bill is uncle of mark
  ...
```

The **schema** is a table rather than knowledge. It says what kind of value each field takes —
`text`, `number`, `date`, a fixed list such as `male|female`, and so on — so the prompt can refuse
`has-age(tim, twenty)` where it is typed instead of storing a fact no rule could ever use. The
solver never reads the schema; the prompt and the facts loader do.

## Why it exists

Large language models are good at language and bad at guaranteeing an answer. A rules engine is the
opposite: it cannot read a sentence, but every answer it gives is deterministic, reproducible, and
accompanied by a proof. That trade-off is the point.

| | micro-expert | A language model |
| --- | --- | --- |
| Input | triples you assert | natural language, images, files |
| Answer | same facts and question give the same answer | sampled; can vary run to run |
| "Why?" | the exact proof tree, every step a fact or a rule | a narrative that reads like an explanation |
| A wrong answer | traces to a bad fact or a missing rule | surfaces unpredictably, and confidently |
| Cost per query | local, microseconds, no tokens | network, latency, money |
| Changing behavior | edit one fact or rule | retrain, re-prompt, or hope |

The project exists to make the auditability concrete and small enough to read. The whole engine is
a few files of MiniScript; the knowledge is diffable text; adding a rule is a five-line change with
a test beside it. It is also a worked example of the architecture that makes an LLM useful without
making it the authority: the model can turn a sentence into triples, and the engine decides what is
actually true.

The long-form essay, [A Micro Expert in MiniScript](../articles/01-a-micro-expert-in-miniscript.md),
covers the history, the design, and that hybrid architecture in depth.

## How an answer is found

The solver uses **backward chaining**. To prove a goal, it:

1. unifies the goal with every fact, and each match is an answer;
2. unifies the goal with the head of every rule, which is a lead rather than an answer;
3. proves each condition in that rule's body the same way, carrying bindings forward;
4. substitutes the final bindings into the goal, and keeps the tree of steps that got there.

Because the search is goal-directed, a question about uncles never touches ages, and a question
about ages never wakes the sibling rule.

Three details keep that loop honest:

- **Fresh variables.** Before a rule is used, its variables are renamed apart (`?x` becomes
  `?x_3`), so one use of a rule cannot capture another's bindings. That is what lets
  `is-uncle-of(bill, anna)` and `is-uncle-of(bill, george)` be derived in one search.
- **Depth.** `--depth` bounds how many rule levels the search may descend. `0` means facts only.
  The default is `8`. `is-uncle-of` needs two rule levels (uncle, then sibling), so `--depth 1`
  answers nothing and says which fact would change that.
- **Cycles.** A symmetric rule such as `married-to(?y, ?x) => married-to(?x, ?y)` can call itself
  forever. The search remembers the chain of goals on the current branch and refuses to re-enter a
  goal it is already inside, comparing goals with variables renamed away.

Every derivation is kept. Ask `is-sibling-of(bill, george)` and one answer comes back carrying two
derivations, one through Walter and one through Doris, because both are true. `--verbose` shows
both; chapter 2 walks through the tree.

## Build and run

There is no compile step. "Build" here means fetching the submodules and the MiniScript 2
interpreter that runs the scripts.

### Prerequisites

- Git, with submodule support.
- Windows or Linux. The bootstrap scripts download the matching MiniScript 2 command-line build;
  the interpreter is not checked in (`3rd-party/` is gitignored), and nothing else is installed.

### Bootstrap

From a clone that does not have the submodules or an interpreter:

```text
git clone --recurse-submodules https://github.com/treytomes/micro-expert.git
cd micro-expert
bootstrap.bat
```

On Linux, run `./bootstrap.sh` instead. Either script is safe to re-run, and each one:

- checks out the five submodules: the agent skill at `.agents/skills/miniscript-2`, the VS Code
  extension at `vscode-miniscript`, and the parser, logger, and repl library at `src/cli`,
  `src/logging`, and `src/repl`;
- downloads `miniscript-win.zip` or `miniscript-linux.tar.gz` from the
  [MiniScript 2 releases page](https://github.com/JoeStrout/miniscript2/releases) into
  `3rd-party/`, unpacks it there, and removes the archive;
- writes `.env` beside the runner if there is none, and leaves an existing one alone.

### The `.env` file

`micro-expert.bat` and `micro-expert.sh` read `.env`, forward every argument to the entry point, and
pass the script's exit code back. The two lines are:

```conf
MINISCRIPT_EXE_PATH=C:\path\to\miniscript.exe
ENTRY_POINT=./src/main.ms
```

The interpreter `bootstrap.sh` unpacks on Linux has no extension, so the first line reads:

```conf
MINISCRIPT_EXE_PATH=/path/to/micro-expert/3rd-party/miniscript-linux/miniscript
ENTRY_POINT=./src/main.ms
```

The path must be absolute. To set the project up by hand, run `git submodule update --init`,
download the interpreter yourself, and write those two lines.

### Run a session

```text
micro-expert.bat --nlp
```

On Linux, `./micro-expert.sh --nlp`. You should see the version line, the options the run was
given, a one-line reminder of what to type, and the `?` prompt:

```text
[INF] micro-expert: micro-expert 0.2.0 starting
[INF] micro-expert: Command-line arguments (0): (none)
[INF] micro-expert: depth:      8
[INF] micro-expert: verbose:    0
[INF] micro-expert: nlp:        0
[INF] micro-expert: log-level:  information
Type a fact, a question or a rule as 'head <- conditions', or a value to see how it reads. /help lists the commands; /exit leaves.
? is-grandpa-of(?who, tim)
  walter is grandpa of tim
? /exit
```

Before the first question the run asks ipwho.is where the session is and adds that place's facts
under the `session` subject, so `has-location(session, ?p)` is already there. With no network it
logs a warning within seconds and starts without them.

Every option:

| Option | Meaning |
| --- | --- |
| `--depth <NUM>` | Maximum backward-chaining depth, default `8`; `0` is facts only |
| `--verbose` | Print the proof tree before each answer |
| `--nlp` | Say answers, and the trees above them, as sentences |
| `--domain <DIR>` | Folder holding `facts.kb`, `rules.kb`, and `schema.kb`, default `data` |
| `--facts <FILE>` | Facts file, in place of the domain's `facts.kb` |
| `--rules <FILE>` | Rules file, in place of the domain's `rules.kb` |
| `--schema <FILE>` | Schema file, in place of the domain's `schema.kb` |
| `--log-level <TEXT>` | `debug`, `information`, `warning`, `error`, or `fatal`; default `information` |
| `--help`, `-h` | Usage, generated from the option table the parser uses |
| `--version`, `-v` | Version line |

`--log-level debug` prints all 54 facts as they load and all sixteen rules as they are registered.
It is the fastest way to see what the engine was actually given.

### Run the tests

The suite needs the same interpreter your `.env` points at:

```text
"%MINISCRIPT_EXE_PATH%" test\run.ms
1066 passed, 0 failed
```

On Linux, `"$MINISCRIPT_EXE_PATH"` — but a plain shell does not read `.env`, so export it or paste
the path. One caveat affects how you read a failure: in this interpreter an uncaught runtime error
still exits `0`, so the `N passed, M failed` line is the real signal, not the exit code. Chapter 6
covers the runner's filters and JSON records.

### If something does not work

| Symptom | Likely cause |
| --- | --- |
| `MINISCRIPT_EXE_PATH` not found | The path in `.env` is missing, relative, or points at the folder rather than the executable |
| Imports fail at startup | The submodules under `src/cli`, `src/logging`, `src/repl`, `vscode-miniscript`, or `.agents/skills/miniscript-2` are empty; run the bootstrap again |
| A stray archive or empty `3rd-party/` | The download failed; delete the partial folder and re-run the bootstrap |
| Escape codes in redirected output | Set `NO_COLOR=1`; both the report and the logger honour it |
| An older date is refused | Dates are validated and counted by the bundled calendar, not the host clock |

## Where to go next

Everything so far can be learned by doing. Chapter 1 opens a session and asks the first questions;
the chapters after it add proofs, missing-fact reports, your own rules, a new domain, and finally
the test suite. Keep [the `.kb` grammar](kb-grammar.md) and
[the built-in constraints](constraints.md) open as references while you work.
