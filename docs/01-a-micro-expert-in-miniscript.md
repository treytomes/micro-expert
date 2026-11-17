# A Micro Expert in MiniScript

[micro-expert on GitHub](https://github.com/treytomes/micro-expert)

A little expert system for MiniScript 2: 54 facts about one imaginary family, nine rules about what those facts imply, and a backward-chaining solver that answers a question only by showing you the facts and rules that make the answer true.

```prolog
Query: uncle-of(bill, ?p)
  uncle-of(bill, anna)  <- rule uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
    parent-of(george, anna)  <- fact
    sibling-of(bill, george)  <- rule sibling-of(?x, ?y) <- parent-of(?p, ?x), parent-of(?p, ?y), ?x != ?y
      parent-of(walter, bill)  <- fact
      parent-of(walter, george)  <- fact
    ...
  ...
```

Abridged: five more answers follow - mark, clara, jack, nina and oliver - each with a tree of that shape. The tree is three levels deep, `uncle-of` via `sibling-of` via the parent facts, and the sibling step shows up twice under one answer because Bill and George share both parents, so both license the same conclusion. Every leaf is a fact, every branch names the rule it used, and there is nothing in there you have to take on trust.

No weights, no API key, no network. About 1,400 lines of MiniScript across seven modules, 402 of them the engine itself, and nothing needs retraining to change.

---

## What is an expert system?

An expert system encodes knowledge as **explicit facts and rules** and reasons over it with an **inference engine**. The engine knows nothing about families, medicine or tax law; it knows how to prove a goal from what it was given. The domain lives entirely in the facts and rules you hand it.

That split is the whole idea, and it is old: MYCIN diagnosed blood infections in the 1970s by chaining a few hundred if/then rules and, crucially, by being able to say which rules fired and why. The knowledge was auditable by doctors who could not read the program.

Three properties follow from the design, and every section below is a consequence of them:

- **The knowledge is data.** A fact is a triple you can list, diff and review. A rule is four lines you can argue about in code review.
- **Answers are derived, not recalled.** The engine never "remembers" that Bill is an uncle; it derives that, every run, from facts about parents and siblings.
- **Every answer carries its proof.** For each result the engine hands back the tree of facts and rule applications that produced it, so "why?" has a mechanical answer.

What makes a system *expert*, in this framing, is the rule base — the curated knowledge — not the engine. The engine here is small on purpose.

## Why should I care in 2026? Why not just use an LLM?

Because for a large class of questions you want the opposite of a plausible answer: you want a correct, reproducible, inspectable one, and you want to know when there isn't one. An LLM is a language model; a rules engine is a proof procedure. They fail in different directions.

| | Rules engine (this) | LLM |
| --- | --- | --- |
| Input | triples you assert | natural language, images, files |
| Answer | deterministic: same facts, same answer | sampled; can vary run to run |
| "Why?" | the exact proof tree, every step a fact or a rule | a narrative that reads like an explanation |
| Wrong answers | trace to a bad fact or a missing rule, which you fix | surface unpredictably, and confidently |
| Cost per query | microseconds, local, no tokens | network, latency, money |
| Changing behavior | edit one fact or rule | retrain, re-prompt, or hope the neighbors don't move |
| Common sense, paraphrase, messy input | none whatsoever | strong |

The last row is the honest one. This program cannot read *"who are Bill's nephews?"* — it has no idea what a sentence is. That is not a gap to paper over; it is the boundary that makes the hybrid in [Where an LLM fits](#where-an-llm-fits) worth building.

What a rules engine buys you, concretely, in an era of cheap text generation:

- **Auditability.** Every claim has a proof you can print. There is no "the model said so" step to defend to a reviewer, an auditor, or yourself in six months.
- **Determinism.** The same facts and the same question give the same answer, byte for byte. That is what makes it testable: this repo ships 112 assertions and they either pass or they don't.
- **Cheap correctness on narrow, high-stakes domains.** Entitlements, eligibility, scheduling constraints, device diagnostics, family relationships — questions where the rule is the requirement and being consistently right matters more than being fluent.
- **Knowledge as a reviewed artifact.** Adding a rule is a five-line pull request with a test. There is no training run, and nothing else silently changes.
- **No data leaving the machine.** The facts are the data, and they are text files.

Use an LLM where the input is language, ambiguity, or volume. Use something like this where the output must be right and explainable.

## SPOs, rules, and backward chaining

### Triples

Everything the program knows is a **subject–predicate–object triple**:

```plaintext
walter  parent-of  bill
bill    has-gender male
```

It prints in a predicate-first call form, which reads like the query you asked:

```prolog
parent-of(walter, bill)
```

A triple may hold **variables** in any position, written `?x`. `parent-of(?p, ?x)` is the pattern "someone is the parent of ?x". The parser accepts that call form and the old pipe form (`walter | parent-of | bill`), and rejects malformed calls rather than guessing.

- A **fact** is a triple with no variables. Facts are the leaves of every answer: `54` of them live in `src/facts.ms`.
- A **rule** has a head — one triple it can prove — and a body: the conditions that must all hold first. Rules live in `src/rules.ms`, print as `head <- conditions`, and are written in the same Lisp-ish shape as the comment above them:

```miniscript
// (<- (uncle-of ?x ?y) (parent-of ?p ?y) (sibling-of ?x ?p) (has-gender ?x male)):
// ?x is an uncle of ?y when ?x is a male sibling of one of ?y's parents.
uncleOf = rule(
	fact(var("x"), "uncle-of", var("y")),
	[fact(var("p"), "parent-of", var("y")), fact(var("x"), "sibling-of", var("p")),
		fact(var("x"), "has-gender", "male")])
```

A body item does not have to be a triple. It can be a **constraint**, checked against the bindings rather than proved by search — here is the sibling rule, which must exclude a person paired with themselves:

```miniscript
// (<- (sibling-of ?x ?y) (parent-of ?p ?x) (parent-of ?p ?y) (?x != ?y))
siblingOf = rule(
	fact(var("x"), "sibling-of", var("y")),
	[
		fact(var("p"), "parent-of", var("x")),
		fact(var("p"), "parent-of", var("y")),
		notEqual(var("x"), var("y")),
	])
```

Sharing *at least one* parent is deliberate, because a half-sibling should count. This family happens to have none - Walter and Doris are both parents to all three sons - so every sibling pair here shares both parents and every answer carries both derivations. The rule does not care either way: one `parent-of` fact is enough, and the test suite exercises the half-sibling case with a Henry who has only Walter for a father.

### Backward chaining

The engine answers a goal by working backwards from it:

1. Unify the goal with every fact. Each match is an answer.
2. Unify the goal with the **head** of every rule. A match is a lead, not an answer: the rule is only usable if all of its body conditions can themselves be proved.
3. Prove each body condition the same way, carrying the bindings forward.
4. Substitute the final bindings into the goal to get the answer, and keep the tree of steps that got there.

This is goal-directed, so it only explores what the question needs. Asking
`uncle-of(bill, ?p)` never touches ages; asking about `has-age` never wakes the sibling rule.

Three details in that loop are where a toy implementation turns into a solver:

**Unification and fresh variables.** Matching a pattern against a triple assigns variables or fails; it never mutates the rule. Before a rule is used, its variables are **standardized apart** — renamed to fresh names like `?x_3` — so one use of a rule cannot capture the bindings of another. Without that, `uncle-of(bill, george)` and `uncle-of(bill, anna)` could not both be derived in one search.

**Depth.** `--depth` bounds how many rule levels the search may go down. `0` means facts only. `uncle-of` needs two levels (`uncle-of` → `sibling-of` → facts), so `--depth 1` answers nothing — and says which
fact would change that.

**Cycles.** A rule like `married-to(?y, ?x) <- married-to(?x, ?y)` can cheerfully call itself forever. The search therefore keeps the chain of goals on the current branch and refuses to re-enter a goal it is already inside, comparing goals with variables renamed away so that `?x` and `?x_7` are recognised as the same goal.

**Every derivation is kept.** Ask `sibling-of(bill, george)` and one answer comes back carrying two derivations — one through Walter, one through Doris — because both are true and a reasoner that silently drops one is hiding information. `--verbose` shows them:

```prolog
$ micro-expert --verbose
Verbose run: depth 8
Query: uncle-of(bill, ?p)
  uncle-of(bill, anna)  <- rule uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
    parent-of(george, anna)  <- fact
    sibling-of(bill, george)  <- rule sibling-of(?x, ?y) <- parent-of(?p, ?x), parent-of(?p, ?y), ?x != ?y
      parent-of(walter, bill)  <- fact
      parent-of(walter, george)  <- fact
    sibling-of(bill, george)  <- rule sibling-of(?x, ?y) <- parent-of(?p, ?x), parent-of(?p, ?y), ?x != ?y
      parent-of(doris, bill)  <- fact
      parent-of(doris, george)  <- fact
    has-gender(bill, male)  <- fact
```

Each line is either `<- fact` or `<- rule ...`; nothing else is allowed to be a reason.

## How to build an expert system in MiniScript

The engine is `src/triples.ms`, and it holds five things:

| Piece | What it is |
| --- | --- |
| Terms | `Var` (a logic variable) and plain values; `SpoTriple` for triples |
| Unification | `unify`, `unifyParts`, `unifyTerms`, `deref`, `resolveBindings`, `substitute` |
| Constraints | `NotEqual`, `holdsConstraint`, and renaming for `standardizeApart` |
| Search | `proveGoals`, `proveConditions`, `mergeAnswer` |
| Explanation | `proofLines`, `derivationLines`, plus cycle keys (`goalKey`, `canonicalText`) and parsing (`parseLine`, `parseCall`) |

If you have met Prolog or Datalog, the mapping is direct: a triple is an atomic goal, a rule is a clause, unification is unification, and `proveGoals` is a depth-bounded SLD-style resolution that returns proofs instead of a yes/no.

### Knowledge lives in its own files

`src/facts.ms` and `src/rules.ms` hold the domain, and nothing else in the repo knows what a family is. Each exposes a `build` function rather than a top-level array, because of a real constraint in this interpreter: **a module that imports `triples.ms` gets its own copy of its classes**, and `isa` checks only agree inside one copy. A facts file that imported `triples.ms` directly would build triples the solver does not recognise. So the caller hands its copy in:

```miniscript
import "facts"
import "rules"

// The arrays themselves, not the module maps that hold them.
facts = globals["facts"].build(triples)
rules = globals["rules"].build(triples)
```

Nothing else is needed to add a domain. Rewrite those two files, keep the shape, and the engine answers questions about invoices or network devices instead of aunts.

### Adding a rule

Three steps, and the test suite has a spot for each rule you add:

1. Write the rule in `src/rules.ms` with the local `rule(head, body)` helper, and put the Lisp form in the comment above it.
2. Add it to the array `build` returns.
3. Add a check to `test/relations.ms` that asserts both a positive and a negative case.

For example, grandparenthood from the child's side:

```miniscript
// (<- (grandchild-of ?x ?y) (parent-of ?p ?x) (parent-of ?y ?p)): ?y is a grandparent
// of ?x when ?y is a parent of ?x's parent.
grandchildOf = rule(
	fact(var("x"), "grandchild-of", var("y")),
	[fact(var("p"), "parent-of", var("x")), fact(var("y"), "parent-of", var("p"))])
```

## How to use this demo

**Prerequisites:** the command-line MiniScript 2 interpreter. Download the archive for your platform from the [MiniScript 2 releases page](https://github.com/JoeStrout/miniscript2/releases) - on Windows that is `miniscript-win.zip`, which unpacks to a folder holding `miniscript.exe`. Put the absolute path to that executable in a `.env` beside the runner:

```conf
MINISCRIPT_EXE_PATH=C:\path\to\miniscript.exe
ENTRY_POINT=./src/main.ms
```

`micro-expert.bat` reads `.env`, forwards every argument to the entry point, and passes the script's exit code back. Then:

```plaintext
> micro-expert
[INF] micro-expert: micro-expert 0.1.0 starting
[INF] micro-expert: depth:      8
[INF] micro-expert: verbose:    1
[INF] micro-expert: log-level:  information

Verbose run: depth 8
Query: uncle-of(bill, ?p)
  uncle-of(bill, anna)  <- rule uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
    parent-of(george, anna)  <- fact
    ...
  ...
[INF] micro-expert: micro-expert exiting with code 0
```

(timestamps trimmed for width)

| Option | Meaning |
| --- | --- |
| `--depth <NUM>` | Maximum backward-chaining depth, default `8`; `0` is facts only |
| `--verbose` | Print the proof tree behind each answer; on by default in this demo |
| `--log-level <TEXT>` | `debug`, `information`, `warning`, `error`, `fatal`; default `information` |
| `--help`, `-h` | Usage, generated from the same option declarations the parser uses |
| `--version`, `-v` | Version line |

`--log-level debug` is the interesting one: it prints all 54 facts as they load and all nine rules as they are registered, which is the fastest way to see what the engine was actually given.

```prolog
[DBG] micro-expert: (fact) parent-of(walter, bill)
...
[DBG] micro-expert: (rule) sibling-of(?x, ?y) <- parent-of(?p, ?x), parent-of(?p, ?y), ?x != ?y
[DBG] micro-expert: (rule) uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
```

**Change the question** by editing the last `runQuery` line of `src/main.ms`:

```miniscript
runQuery fact("bill", "uncle-of", var("?p"))
```

Try `fact(var("x"), "grandma-of", var("y"))` for every  grandmother/grandchild pair (seven of them), or `fact(var("who"), "grandpa-of", "tim")` for Tim's grandfather: the predicate reads "?who is the grandpa of tim", so the variable goes in the subject.

**Run the tests** with the same interpreter your `.env` points at. The runner is for the program, not the suite, and `3rd-party/` is gitignored, so there is no checked-in binary to fall back on:

```plaintext
> "%MINISCRIPT_EXE_PATH%" test\run.ms
112 passed, 0 failed
```

`micro-expert.bat` reads that variable out of `.env`; a plain shell does not, so `set` it for the session or paste the path in its place.

The 112 checks are split by area: display and parsing (12), proofs and explanations (19), the missing-fact report (22), recursion and cycle handling (13), and relations including the family rules (46). One caveat worth knowing, because it affects how you read a failed run: in this interpreter an uncaught runtime error still exits `0`, so the `N passed, M failed` line is the real signal, not the exit code.

## Where an LLM fits

The interesting 2026 architecture is not LLM *or* rules engine. It is an LLM as the language front door and a rules engine as the authority behind it:

```plaintext
"who are bill's nephews?"          natural language
        │
        ├── LLM: plans the question, proposes triples/queries
        │        uncle-of(bill, ?x)? validate predicate against the rule base
        ▼
   engine: unifies, chains, returns answers *with proof trees*
        │
        ├── LLM: renders the phrasing a human wants to read
        ▼
"Bill has six nieces and nephews: Anna, Mark, Clara, Jack, Nina and Oliver.
 Every one is the child of his brothers George and Henry."
```

The contract that makes this worth doing:

- **The LLM never asserts a fact the engine did not prove.** Its job is to translate, not to know. Anything it proposes goes through the engine, and an unknown predicate is a refusal, not a guess.
- **The proof travels with the answer.** Render the proof (or a summary of it) next to the sentence, so the fluent answer is still auditable. The engine's `--verbose` tree is already that artifact.
- **Failures are visible.** "No answer" is a first-class result here — missing fact, or a rule that does not fire — and it is exactly the signal an LLM alone cannot give you. The program spells it out: it reports the absence, then the facts that would have allowed an answer. That report is painted for a terminal through the interpreter's bundled `vt` module - `no solution found` in red, a rule path in olive, the facts in aqua with their variables dimmed - and `NO_COLOR` turns that paint off, which is what a redirected run wants. A rule's variable that would otherwise read like the query's comes out primed (`?p'`), and a condition the listed facts would settle is tagged as one to check rather than one to add.

None of this needs a frontier model. The pattern has been tested end to end with models as small as **3B parameters**, small enough to run on a CPU with no graphics card at all: the model only has to turn a sentence into a handful of triples and a rule name, and the engine does the part that has to be right. That puts the whole stack - language front door and
reasoner - on one ordinary machine, offline.

You get the interface people expect from a chatbot, with the answer coming from a system that can be reviewed, tested and argued with.

## License

MIT — see [LICENSE](LICENSE). Copyright © 2026 Trey Tomes.

## About MiniScript

MiniScript is a small, clean language built for embedding and for learning, created by Joe Strout. [MiniScript 2.0](https://dev.to/joestrout/announcing-miniscript-20-gl4) landed in October 2026 as a from-the-ground-up rewrite: 45-50x faster than 1.x on some benchmarks and 10-15x on average, with real error handling, frozen lists and maps, computed lists and mark-and-sweep garbage collection. Its command-line build — Linux, Windows, macOS and anything with .NET — is what runs this demo.

It turns out to be a good host for a rules engine: `import` for keeping the knowledge apart from the solver, maps and classes for the term types, closures for the little shorthands, and a REPL for poking at triples by hand. The language manual ships inside the download, along with *What's New in MiniScript 2.0* for anyone arriving from 1.x.
