# micro-expert

**A little expert system for MiniScript 2.** Fifty-four facts about one imaginary family, sixteen
rules about what those facts imply, and a backward-chaining solver that answers a question only by
showing you the facts and rules that make the answer true.

```text
? is-uncle-of(bill, ?p)
  bill is uncle of anna
  bill is uncle of mark
  bill is uncle of clara
  bill is uncle of jack
  bill is uncle of nina
  bill is uncle of oliver
```

Nothing is stored about uncles. The engine derives each answer from the facts you assert and the
rules you write, and hands back the tree of steps that got there: every leaf is a fact, every
branch names the rule it used. No weights, no API key, no network.

## Start here

| Page | What it covers |
| --- | --- |
| [Introduction](introduction.md) | What the project is, why it exists, and how to build and run it |
| [1. Asking your first questions](01-first-questions.md) | Start a session, ask a question, read the answers, say them in words |
| [2. Reading a proof](02-reading-proofs.md) | Turn on proof trees, read them, and bound the search with `--depth` |
| [3. When there is no answer](03-when-there-is-no-answer.md) | Read the missing-fact report, answer its questions, and fix the knowledge base |
| [4. Writing rules](04-writing-rules.md) | Write your own rules with `and`, `or`, `not`, and the seven constraints |
| [5. Your own domain](05-your-own-domain.md) | Replace the family with your own facts, rules, and schema |
| [6. Tests and extending the knowledge base](06-tests-and-extending.md) | Run the suite and add a rule with checks behind it |
| [7. The notebook in VS Code](07-the-notebook.md) | Run knowledge as cells: the protocol, the ask box and its reason line, the settings |
| [The `.kb` grammar](kb-grammar.md) | Reference: the exact file format for facts, rules, and schema |
| [The built-in constraints](constraints.md) | Reference: what each constraint checks, binds, and refuses |

Read the introduction first, then work through chapters 1 to 7 in order. Each chapter assumes only
the ones before it. If you want the long-form story instead — why a rules engine in 2026, how
backward chaining and unification work here, and where an LLM fits in front of it — read
[A Micro Expert in MiniScript](../articles/01-a-micro-expert-in-miniscript.md).

## Quick start

A plain clone does not carry the submodules or an interpreter, so clone with them or run the
bootstrap afterwards:

```text
git clone --recurse-submodules https://github.com/treytomes/micro-expert.git
cd micro-expert
bootstrap.bat        (bootstrap.sh on Linux)
micro-expert.bat     (micro-expert.sh on Linux)
```

Then type a question at the `?` prompt, and `/exit` to leave:

```text
? is-grandpa-of(?who, tim)
  is-grandpa-of(walter, tim)
? /exit
```

`--nlp` says each answer as a sentence instead, `--verbose` prints the proof tree behind it, and
`--help` lists every option. A question about where the session is asks ipwho.is for the answer
when the fact is needed, rather than every run asking at startup. The
[introduction](introduction.md) explains what `bootstrap` does,
what goes in `.env`, and how to run the suite.

## What it is, in one paragraph

Every stored statement is a triple, `predicate(subject, object)` — `is-parent-of(walter, bill)`,
`has-gender(bill, male)`. A rule gives one triple it can prove and a body of conditions that must
all hold. A question may hold variables, and the solver works backwards from it: unify it with the
facts, then with each rule head, prove that rule's body, and keep the bindings that survive. The
answer is the fact that proves the question, together with the derivation. Change the three text
files in `data/` and the same engine answers questions about a different world.

## Repository map

| Path | What it holds |
| --- | --- |
| `src/main.ms` | Logging and the session at the prompt |
| `src/triples.ms` | The solver: terms, unification, search, proofs |
| `src/knowledge.ms` | The reader and writer for `.kb` data |
| `src/session.ms` | The session's knowledge side: facts, rules, questions |
| `src/engine.ms` | The domain's three files read into that session |
| `src/notebook.ms` | That session served to a notebook's cells |
| `data/facts.kb` | The 54 facts, as text |
| `data/rules.kb` | The sixteen rules, as text |
| `data/schema.kb` | The field types, as text |
| `test/` | The 1087 checks and their runner |
| `docs/` | This wiki, the long-form articles, and the format references |
| `vscode-knowledge/` | Syntax highlighting for `.kb` files, and the `.kbnb` notebook |
| `bootstrap.bat`, `bootstrap.sh` | Submodules, interpreter, `.env` |
| `micro-expert.bat`, `micro-expert.sh` | Run the entry point named in `.env` |

MIT licensed — see [LICENSE](../../LICENSE). Copyright © 2026 Trey Tomes.
