# A Micro Expert in MiniScript

[micro-expert on GitHub](https://github.com/treytomes/micro-expert)

A little expert system for MiniScript 2: 54 facts about one imaginary family, fourteen rules about what those facts imply, and a backward-chaining solver that answers a question only by showing you the facts and rules that make the answer true.

```prolog
? uncle-of(bill, ?p)
  uncle-of(bill, anna)  <- rule uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
    parent-of(george, anna)  <- fact
    sibling-of(bill, george)  <- rule sibling-of(?x, ?y) <- parent-of(?p, ?x), parent-of(?p, ?y), not-equal(?x, ?y)
      parent-of(walter, bill)  <- fact
      parent-of(walter, george)  <- fact
    ...
  ...
```

Abridged: five more answers follow - mark, clara, jack, nina and oliver - each with a tree of that shape. The tree is three levels deep, `uncle-of` via `sibling-of` via the parent facts, and the sibling step shows up twice under one answer because Bill and George share both parents, so both license the same conclusion. Every leaf is a fact, every branch names the rule it used, and there is nothing in there you have to take on trust.

No weights, no API key, no network. About 2,100 lines of MiniScript across eight modules, 1,175 of them the engine itself, and nothing needs retraining to change.

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
- **Determinism.** The same facts and the same question give the same answer, byte for byte. That is what makes it testable: this repo ships 487 assertions and they either pass or they don't.
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

- A **fact** is a triple with no variables. Facts are the leaves of every answer: `54` of them live in `data/facts.kb`, one `predicate(subject, object)` line each.
- A **rule** has a head — one triple it can prove — and a body: the conditions that must all hold first. Rules are data, one per line in `data/rules.kb`, and print as `head <- conditions`:

```prolog
uncle-of(?x, ?y) => and(parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male))
```

The arrow reads "proves". The body is a comma-delimited list of conditions — an implied `and` — so `and(...)` is optional there; it nests. `or(...)` holds alternatives: any one of them may hold instead, and each alternative is a body of its own, so a rule that could be written two ways is still one line. `not(...)` holds a body that must have no proof, so a rule can ask for something the graph does not have: the shipped `only-child-of` holds when no sibling of the child can be found. `src/knowledge.ms` parses the format and `src/rules.ms` loads it.

A body item does not have to be a triple. It can be a **constraint**, checked against the bindings rather than proved by search — here is the sibling rule, which must exclude a person paired with themselves:

```prolog
sibling-of(?x, ?y) => and(parent-of(?p, ?x), parent-of(?p, ?y), not-equal(?x, ?y))
```

`not-equal` only checks; `equal` can also **bind**. A side that is still a variable takes the other side's value, so a body can write `equal(?g, ?h)` the moment `?g` is known and go on with `?h` already settled — the shipped `same-age-group-as` reads as "the same group" without a second variable for the second lookup:

```prolog
same-age-group-as(?x, ?y) => and(age-group(?x, ?g), equal(?g, ?h), age-group(?y, ?h), not-equal(?x, ?y))
```

A comparison is the other constraint, written as a call like every other condition: `less-than-or-equal(?n, 18)` reads two numbers and holds when they stand in that order, so `age-group(?x, child) => and(has-age(?x, ?n), less-than-or-equal(?n, 18))` puts the age where childhood ends into the rule instead of into a column of `is-child` facts. The parser reads a number as a number, which is what makes that arithmetic rather than text — as text, `"9"` would sort after `"18"` — and a side that is not a number ends the branch rather than passing for a zero. A number may also carry an exponent - `1e3` is a thousand - with digits required on both sides of the `e`, so `1e` stays text. `not(...)` then gives the other group without writing the line twice:

```prolog
age-group(?x, adult) => and(has-age(?x, ?n), not(age-group(?x, child)))
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

**Cycles.** A rule like `married-to(?y, ?x) <- married-to(?x, ?y)` can cheerfully call itself forever. The search therefore keeps the chain of goals on the current branch and refuses to re-enter a goal it is already inside, comparing goals with variables renamed away so that `?x` and `?x_7` are recognized as the same goal.

**Every derivation is kept.** Ask `sibling-of(bill, george)` and one answer comes back carrying two derivations — one through Walter, one through Doris — because both are true and a reasoner that silently drops one is hiding information. `--verbose` shows them:

```prolog
$ micro-expert --verbose
Verbose run: depth 8
? uncle-of(bill, ?p)
  uncle-of(bill, anna)  <- rule uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
    parent-of(george, anna)  <- fact
    sibling-of(bill, george)  <- rule sibling-of(?x, ?y) <- parent-of(?p, ?x), parent-of(?p, ?y), not-equal(?x, ?y)
      parent-of(walter, bill)  <- fact
      parent-of(walter, george)  <- fact
    sibling-of(bill, george)  <- rule sibling-of(?x, ?y) <- parent-of(?p, ?x), parent-of(?p, ?y), not-equal(?x, ?y)
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
| Constraints | `Equal`, `NotEqual`, `Comparison`, `holdsConstraint` and `applyConstraint`, and renaming for `standardizeApart` |
| Search | `proveGoals`, `proveConditions`, `mergeAnswer` |
| Explanation | `proofLines`, `derivationLines`, plus cycle keys (`goalKey`, `canonicalText`) and parsing (`parseLine`, `parseCall`) |

If you have met Prolog or Datalog, the mapping is direct: a triple is an atomic goal, a rule is a clause, unification is unification, and `proveGoals` is a depth-bounded SLD-style resolution that returns proofs instead of a yes/no.

### Knowledge lives in its own files

`data/facts.kb` and `data/rules.kb` hold the domain, and nothing else in the repo knows what a family is. A third file, `data/schema.kb`, is a table rather than knowledge: one line per predicate the knowledge base uses, giving the type of each field in the order a fact writes them, and `src/schema.ms` loads it so the prompt can refuse `has-age(tim, twenty)` instead of filing it where no rule could reach it. The stored predicates are typed from the facts that use them and the derived ones from the rules that conclude them, so `sibling-of` is two texts because the siblings come from `parent-of`, and `age-group`'s second field is `child|adult` because those are the two words its rules write. The suite holds the schema and the rules to each other: every predicate a rule names must be typed, and every constant it writes must fit the type it is given. The solver never reads it. Both are loaded through a `build` function rather than exported as a top-level array, because of a real constraint in this interpreter: **a module that imports `triples.ms` gets its own copy of its classes**, and `isa` checks only agree inside one copy. A loader that imported `triples.ms` directly would build triples the solver does not recognize, so the caller hands its copy in. The data dodge the problem another way: `src/knowledge.ms` parses the text with whichever copy it is handed, and the loaders wrap what it returns.

```miniscript
import "facts"
import "rules"

// The arrays themselves, not the module maps that hold them.
facts = globals["facts"].build(triples)
rules = globals["rules"].build(triples)
```

Nothing else is needed to add a domain. Rewrite those three data files, keep the shape, and point `--domain` at the folder that holds them - or leave them in `data/` - and the engine answers questions about invoices or network devices instead of aunts.

### Adding a rule

Two steps, and the test suite has a spot for each rule you add:

1. Add its line to `data/rules.kb`: a head, `=>`, and a body of conditions.
2. Add a check to `test/relations.ms` that asserts both a positive and a negative case.

For example, grandparenthood from the child's side:

```prolog
grandchild-of(?x, ?y) => and(parent-of(?p, ?x), parent-of(?y, ?p))
```

## How to use this demo

**Prerequisites:** the command-line MiniScript 2 interpreter. Download the archive for your platform from the [MiniScript 2 releases page](https://github.com/JoeStrout/miniscript2/releases) - on Windows that is `miniscript-win.zip`, which unpacks to a folder holding `miniscript.exe`. Put the absolute path to that executable in a `.env` beside the runner:

```conf
MINISCRIPT_EXE_PATH=C:\path\to\miniscript.exe
ENTRY_POINT=./src/main.ms
```

`micro-expert.bat` reads `.env`, forwards every argument to the entry point, and passes the script's exit code back. Opening it puts you at a prompt: the program is the session, `data/` is already loaded, and every line you type is answered against those facts and rules. Then:

```plaintext
> micro-expert
[INF] micro-expert: micro-expert 0.2.0 starting
[INF] micro-expert: Command-line arguments (0): (none)
...
Type a fact, a question, or a rule as 'head <- conditions'. /help lists the commands; /exit leaves.
? uncle-of(bill, ?p)
  bill uncle of anna
  bill uncle of mark
  bill uncle of clara
  bill uncle of jack
  bill uncle of nina
  bill uncle of oliver
? /exit
[INF] micro-expert: micro-expert exiting with code 0
```

(timestamps trimmed for width; `...` stands for the option lines the logger prints before the prompt)

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

`--log-level debug` is the interesting one: it prints all 54 facts as they load and all fourteen rules as they are registered, which is the fastest way to see what the engine was actually given.

```prolog
[DBG] micro-expert: (fact) parent-of(walter, bill)
...
[DBG] micro-expert: (rule) sibling-of(?x, ?y) <- parent-of(?p, ?x), parent-of(?p, ?y), not-equal(?x, ?y)
[DBG] micro-expert: (rule) uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
```

**Change the question** by typing another one at the prompt: `grandma-of(?x, ?y)` asks for every grandmother/grandchild pair (seven of them), and `grandpa-of(?who, tim)` asks for Tim's grandfather, the predicate reading "?who is the grandpa of tim", so the variable goes in the subject.

**Type a fact or a rule** at the same prompt and it joins the search. One line has one meaning: a ground line adds a fact, a line with a variable asks a question, a line with `<-` adds a rule, and a line starting with `/` is a command for the session (`/help`, `/facts`, `/rules`, `/undo`, `/exit`, and the six `/save-*` and `/load-*` commands that write a component back where it came from or read one in its place).

```plaintext
> micro-expert
Type a fact, a question, or a rule as 'head <- conditions'. /help lists the commands; /exit leaves.
? parent-of(?p, susan)
  no solution found at depth 8
  A solution would need one of these:
    a fact like parent-of(?p, susan)
  ?p = walter
  added parent-of(walter, susan)
  walter parent of susan
? grandparent(?x, ?y) <- parent-of(?x, ?p), parent-of(?p, ?y)
  added rule grandparent(?x, ?y) <- parent-of(?x, ?p), parent-of(?p, ?y)
? grandparent(?p, tim)
  walter grandparent tim
  doris grandparent tim
```

A question with no answer reads the report above, asks for the fact that would let a rule reach one, adds it, and asks again - the loop the report was written for. It asks for a rule's fact before the query's own shape, since asserting the answer proves nothing; it shows the fact it is filling, with the values given so far in it, and the report above reads the same way; and it asks one variable at a time, so a missing `parent-of(?p, ?q)` takes two answers. A rule's fact is filled in by the variables it brings itself, so `parent-of(?p', ?p)` asks for `?p'` and not again for `?p`, which the question already named; a fact that is still incomplete once its own variables are filled is shown with what is left over and not added, rather than the answer being written in as though it had been found, and the answers given are carried to the rest of that rule's facts, so a value is never asked for twice; a fact the session can already prove needs nothing added, so it drops out of the report too. A whole fact typed where a value is asked for is a fact too, so the answer can still be asserted by fiat when that is what you want: the session adds it and asks again from there, while a line that parses as a fact but still holds a variable is refused rather than stored as a value. A fact with no variable left is offered with `add it? [y/N]` rather than assumed, and a value left empty stops the asking and leaves the report standing. A fact and a question are both held to `data/schema.kb`: a question that names a value no fact could store is refused before the search, and an answer that completes a refused fact stops the question instead of being asked for again. `/undo` takes back the last fact the session added - at the prompt or in the middle of a question, which asks it again - so a wrong value does not stick for the rest of the run. Nothing is written back until you ask: the session adds to the arrays `main.ms` built, and `/save-*` is what puts a component back on disk.

Adding `--verbose` prints the proof tree behind each answer here too, exactly as in the example above.

A rule typed at the prompt is read from the line `Rule.text` prints, which is why that parser lives in `triples.ms` and returns the pieces `Rule.make` takes rather than a rule: the engine stays free of the Rule class. The data files have their own parser, `src/knowledge.ms`, built the same way, with a fact as a bare `predicate(subject, object)` and a rule's `=>` in place of `<-`.

The session paints from the same style table as the report, so `NO_COLOR` turns the whole run plain, prompt included.

**Run the tests** with the same interpreter your `.env` points at. The runner is for the program, not the suite, and `3rd-party/` is gitignored, so there is no checked-in binary to fall back on:

```plaintext
> "%MINISCRIPT_EXE_PATH%" test\run.ms
487 passed, 0 failed
```

`micro-expert.bat` reads that variable out of `.env`; a plain shell does not, so `set` it for the session or paste the path in its place.

The 487 checks are split by area: display and parsing (32), the knowledge data format (81), the predicate schema (40), the loaders (19), proofs and explanations (21), the missing-fact report (34), recursion and cycle handling (13), relations including the family rules (89), the session at the prompt (147), the notes example on the repl library (1), and the domain (10). The parser, the logger and the repl library are submodules with suites of their own (32, 56 and 52 checks), run from their own folders. One caveat worth knowing, because it affects how you read a failed run: in this interpreter an uncaught runtime error still exits `0`, so the `N passed, M failed` line is the real signal, not the exit code.

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
- **Failures are visible.** "No answer" is a first-class result here — missing fact, or a rule that does not fire — and it is exactly the signal an LLM alone cannot give you. The program spells it out: it reports the absence, then the facts that would have allowed an answer. That report is painted for a terminal through the interpreter's bundled `vt` module - `no solution found` in red, a rule path in olive, the facts in aqua with their variables dimmed - and `NO_COLOR` turns that paint off, which is what a redirected run wants. A rule's variable that would otherwise read like the query's comes out primed (`?p'`), and a condition the listed facts would settle is tagged as one to check rather than one to add. A body is judged as a body, too: a rule whose conditions can each be met on their own but never all at once still appears, with the facts those conditions would need as one set, instead of the query being left with nothing but its own shape.

None of this needs a frontier model. The pattern has been tested end to end with models as small as **3B parameters**, small enough to run on a CPU with no graphics card at all: the model only has to turn a sentence into a handful of triples and a rule name, and the engine does the part that has to be right. That puts the whole stack - language front door and
reasoner - on one ordinary machine, offline.

You get the interface people expect from a chatbot, with the answer coming from a system that can be reviewed, tested and argued with.

## License

MIT — see [LICENSE](../../LICENSE). Copyright © 2026 Trey Tomes.

## About MiniScript

MiniScript is a small, clean language built for embedding and for learning, created by Joe Strout. [MiniScript 2.0](https://dev.to/joestrout/announcing-miniscript-20-gl4) landed in October 2026 as a from-the-ground-up rewrite: 45-50x faster than 1.x on some benchmarks and 10-15x on average, with real error handling, frozen lists and maps, computed lists and mark-and-sweep garbage collection. Its command-line build — Linux, Windows, macOS and anything with .NET — is what runs this demo.

It turns out to be a good host for a rules engine: `import` for keeping the knowledge apart from the solver, maps and classes for the term types, closures for the little shorthands, and a REPL for poking at triples by hand. The language manual ships inside the download, along with *What's New in MiniScript 2.0* for anyone arriving from 1.x.
