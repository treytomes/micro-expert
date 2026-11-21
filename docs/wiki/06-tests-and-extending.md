# 6. Tests and extending the knowledge base

A rule is a claim about what follows. The suite is how the project checks that claim without
re-reading every proof by hand. This chapter runs the suite, asks it for part of itself, and adds a
rule with a positive and a negative check behind it.

## Run the suite

The suite needs the interpreter your `.env` points at. On Windows, with the variable set for the
shell:

```text
> "%MINISCRIPT_EXE_PATH%" test\run.ms
...
554 passed, 0 failed
```

On Linux, `"$MINISCRIPT_EXE_PATH"` — a plain shell does not read `.env`, so export it or paste the
absolute path. You can also call the interpreter directly:
`3rd-party\miniscript-win\miniscript.exe test\run.ms`.

That count is the project's current one; it changes when a check is added. The number at the end is
the result, not the exit code.

## Read the signal, not the exit code

A caveat that affects every automated run: in this interpreter an uncaught runtime error still exits
`0`. A run that crashes part way through can look successful to a script. The signals that matter
are:

- the final `N passed, M failed` line;
- with `--json`, the `##END {"passed":...,"failed":...,"skipped":...}` record, which says the suite
  reached the end.

Treat a run without either line as a failure, whatever the exit status says.

## Ask for part of the suite

While working on one rule, run only the checks that cover it:

```text
> "%MINISCRIPT_EXE_PATH%" test\run.ms --json --file session.ms --filter "a rule line parses"
PASS  a rule line parses
##TEST {"name":"a rule line parses","status":"pass","file":"session.ms","line":31}

1 passed, 0 failed, 553 skipped
##END {"passed":1,"failed":0,"skipped":553}
```

| Argument | Meaning |
| --- | --- |
| `--filter <TEXT>` | Run checks whose name contains the text |
| `--file <NAME>` | Run checks from that case module, such as `session.ms` |
| `--json` | Add the `##TEST` and `##END` records a runner reads |

Each argument may be repeated, and a check runs when it matches any of the filters and any of the
files that are given. The VS Code extension's Testing panel passes exactly these arguments, so its
tree and its runs come from the suite rather than from a list kept beside it.

## Add a rule to the shipped domain

The README's recipe is three steps, and all three matter:

1. Add the rule's line to `data/rules.kb`, in file syntax with `=>`.
2. If the rule names a predicate `data/schema.kb` does not type, add its line there. This applies to
   derived predicates too, so the prompt can refuse a value no rule could use.
3. Add checks to `test/relations.ms` that assert both a positive and a negative case.

Then run the suite. A rule that changes behavior without a failing check somewhere means the suite
is missing a case, not that the change is safe.

For example, the cousin rule from chapter 4 goes into `data/rules.kb` as:

```prolog
// ?x is a cousin of ?y when ?y is a child of a sibling of ?x's parent.
is-cousin-of(?x, ?y) => and(is-parent-of(?p, ?x), is-sibling-of(?p, ?q), is-parent-of(?q, ?y))
```

and into `data/schema.kb` as:

```prolog
is-cousin-of(text, text)
```

Restart the session to load the edited files, or use `/load-rules` and `/load-schema`.

## What a check looks like

The suite is MiniScript, not a separate test framework. `test/run.ms` imports the program once and
hands each case module the same copies: the solver as `t`, the rule factory as `rules`, and the
harness as `h`. A module is a `run` function that records checks with `h.check(name, condition)`.

The family cases in `test/relations.ms` build a small fixture (`lineage` facts and a `kinAll` list of
rules), then define helpers:

```miniscript
ask = function(predicate, a, b)
	return t.proveGoals(spo(a, predicate, b), lineage, kinAll, 4)
end function

h.check("an uncle is a male sibling of a parent", ask("is-uncle-of", "george", "tim").len == 1)
h.check("a parent is neither", ask("is-uncle-of", "bill", "tim").len == 0)
```

`proveGoals(goal, facts, rules, depth)` returns the derivations it found, so `.len` is the number of
answers. A check names one behavior and asserts it in one line. Positive and negative cases are
both expected: "a parent is neither" is as important as "an uncle is", because it catches a rule
that has become too general.

Add the cousin rule to the same fixture and list, then check both directions of the claim:

```miniscript
cousinRule = rule(spo(v("x"), "is-cousin-of", v("y")),
	[spo(v("p"), "is-parent-of", v("x")),
	 spo(v("p"), "is-sibling-of", v("q")),
	 spo(v("q"), "is-parent-of", v("y"))])
kinAll.push(cousinRule)

h.check("a cousin is a child of a parent's sibling", ask("is-cousin-of", "tim", "jack").len == 1)
h.check("a parent is not a cousin", ask("is-cousin-of", "tim", "bill").len == 0)
```

In that fixture Tim is Bill's son and Jack is George's son, and Bill and George are siblings, so the
first check should pass. Bill is Tim's parent, not his cousin, so the second should pass too.

Run just these while you work:

```text
> "%MINISCRIPT_EXE_PATH%" test\run.ms --file relations.ms --filter "cousin"
```

Once the focused checks pass, run the whole suite. A new rule can change answers elsewhere — the
uncle and grandparent checks are sensitive to the sibling rule, and the age checks pin today so a
birthday cannot change them — so the focused run is a shortcut, not the final word.

## The suite's own shape

The 554 checks cover the program itself, split by area: display and parsing (32), the knowledge data
format (81), the predicate schema (42), the date and time types (31), the loaders (19), proofs and
explanations (23), the missing-fact report (34), recursion and cycle handling (13), relations
including the family rules (104), the session at the prompt (158), the notes example on the repl
library (1), the command line (6), and the domain (10).

Three of the components are separate repositories with suites of their own:

| Folder | Suite | Checks |
| --- | --- | --- |
| `src/cli` | the argument parser | 32 |
| `src/logging` | the logger | 56 |
| `src/repl` | the prompt loop and its commands | 52 |

Each is run from its own folder with the same interpreter, and the main suite imports none of them.
A knowledge-base change does not need those suites; a change to the parser, the logger, or the repl
library does.

## Where to go next

You now have the whole loop: ask, read the proof, answer the report, write a rule, point at a
domain, and check the result. For reference while extending the knowledge base, keep these open:

- [The `.kb` grammar](kb-grammar.md) — the exact format, line joining, terms, and schema types.
- [The built-in constraints](constraints.md) — each of the seven, what it binds, and what it refuses.
- [A Micro Expert in MiniScript](../articles/01-a-micro-expert-in-miniscript.md) — the design story
  and where an LLM fits in front of the engine.
- [README](../../README.md) — the full option table and the shipped examples.
