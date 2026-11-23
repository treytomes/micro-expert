# The Program You Can Talk To

*This is the third article about [micro-expert](https://github.com/treytomes/micro-expert), a small backward-chaining expert system in MiniScript.  The [first article](https://github.com/treytomes/micro-expert/blob/main/docs/articles/01-a-micro-expert-in-miniscript.md) built the engine out of triples, unification and proof trees; the [second](https://github.com/treytomes/micro-expert/blob/main/docs/articles/02-to-know-what-you-dont-know.md) turned a failed query into a report of the facts that would let it succeed.  This one starts with the ledger: everything that has landed since `v0.2.0`.  The prose that puts these pieces together comes next; the list is here first so the claims have somewhere to point.*

## The prompt is the program

I have been stewing over this problem for months now in a variety of projects.  In the time of LLMs, we can have any program we want written in any language we want targeting any platform we want.  The "computer language", C#, Rust, MiniScript, is almost immaterial.  What matters is the *query*: can you define what you want precisely, and know exactly if and where that query failed?

`micro-expert` v0.3 doesn't add any grand new features (though those are coming).  This release is all about *completion*.  There are a number of things needed to make the system whole:
- The REPL is now the primary mode of execution.
- `--verbose` and `--nlp` flags can be used to generate a kind of natural language output that's a bit easier on the eyes.
- I've extracted the REPL concern from the engine into its own git submodule.  Git submodules are an odd beast, but if you can get everything scripted it's working quite well as a cheap MiniScript package manager.
- CLI and REPL commands have been added to save and load custom knowledge bases.  Core concept here:
    - The *domain* is the complete knowledge base, and is made up of a *schema*, *rule set*, and *facts*.
    - The *schema* defines the constraints on the S-P-O facts.
- Data types are enforces on-demand, including date/times, so `has-age` is now a rule based on a birthdate.

## The knowledge base data format

Facts, rules and field types live in three text files, and the program reads a *domain* rather than a hard-coded family.

- **`.kb` as a format** (`src/knowledge.ms`, 660 lines): one triple per line, one rule per line, one schema line per predicate, with `//` comments, blank lines and entries that may run over several lines inside their parentheses.
- **A domain is the three files.**  `--domain <DIR>` names a folder holding `facts.kb`, `rules.kb` and `schema.kb`; `--facts`, `--rules` and `--schema` name one file in place of the folder's piece.  With no option the default folder is `data/`.
- **Saving and loading per component**: `/save-facts`, `/load-facts`, `/save-rules`, `/load-rules`, `/save-schema`, `/load-schema`, each with an optional file, and a path with a space is quoted.
- **An atomic save.**  A save writes a temp file and swaps it in when it is whole, so a failed save cannot truncate a data file; the only file removed is the temp file that save wrote.  A save or load says `file` rather than borrowing `added`, so writing to disk and adding to the session can be told apart.

A data file is held to the same promise the prompt is: the facts loader applies the same `unique(...)` the prompt does, which is why the schema is read before the facts are.

## The schema types every field

`data/schema.kb` names each predicate and the type of its two fields, stored or derived, and the prompt holds what you type to it before anything is stored or searched.

| Type | What fits it |
| --- | --- |
| `number` | any number, whole or fractional: `24`, `24.5`, `-3`, `1e3` |
| `text` | any text - e.g. a person or a word |
| `boolean` | the word `true` or the word `false` |
| `date` | a calendar date, `yyyy-MM-dd`: `2019-04-01` |
| `time` | a clock time, `HH:mm:ss`: `09:30:00` |
| `datetime` | a date and a clock time, `yyyy-MM-dd HH:mm:ss`: `2019-04-01 09:30:00` |
| `a\|b\|c` | one of these words, exactly |
| `unique(t)` | at most one value of type `t` for a subject/predicate pair, e.g.: `unique(number)` |

- **A fact and a question are held alike**: `has-age(?a, twenty)` is refused where it is typed, rather than searched for and ending in a fact the same check refuses.
- **`unique(...)` is about the pair, not the value**: a second birthdate for one person is a correction rather than a second fact, and `unique(text)` in the subject position is the other direction.  A predicate a rule concludes cannot carry it, and a schema line that marks one is refused at startup, by `/load-schema`, by `/load-rules` and by a typed rule line.
- **Every predicate the rules name is typed**, derived ones included, with the schema's line derived from the conditions that use it.  Rule constants are checked against the schema too, and each mismatch is printed on its own line.
- **Predicates have a name shape**: lower case, sections joined by dashes, each section letters and numbers, the first starting with a letter.  Every reader refuses a line that breaks it, so the knowledge base holds only names an answer can say.
- **A number is written as one**, exponent and all - `1e3` is a thousand - and the digits are checked on both sides of the `e`, so `1e` stays text.

If a data type is provided for an object, the REPL will provide an appropriate interface for choosing a value to suit the type.

## Rule bodies gained constraints

A condition used to be a fact to prove.  It can now also be a call that checks or computes, and the body keeps one shape for both.

```prolog
is-sibling-of(?x, ?y) => and(is-parent-of(?p, ?x), is-parent-of(?p, ?y), not-equal(?x, ?y))
belongs-to-age-group(?x, child) => and(has-age(?x, ?n), less-than-or-equal(?n, 18))
shares-age-group-with(?x, ?y) => and(belongs-to-age-group(?x, ?g), equal(?g, ?h), belongs-to-age-group(?y, ?h), not-equal(?x, ?y))
```

- **Seven built-in names**, all written as calls so no condition is infix: `not-equal`, `equal`, `years-since`, `less-than`, `less-than-or-equal`, `greater-than`, `greater-than-or-equal`.
- **`equal` binds** as well as checks, which is what lets `shares-age-group-with` reach the second age group through the first group's word instead of looking it up twice.
- **Comparisons are arithmetic**: both sides have to be numbers, and a name never passes for a zero.
- **`and(...)` nests, `or(...)` holds alternatives, `not(...)` asks for an absence** - so a rule that can be read two ways is still one line, and "nobody is a sibling of ?x" is sayable.
- **`years-since(date, years)` works a value out** rather than only checking one, and is the one constraint that computes.  A birthday that has not come round yet is not counted; on this machine, `years-since("1948-03-14", ?n)` binds `78`.
- **A constraint typed as a question is refused**, so `less-than-or-equal(5, 3)` is not kept as a fact.
- **`docs/wiki/constraints.md`** documents the seven one by one, including what each does with a field that is still a variable.

## Dates are a type, not a string

`src/temporal.ms` owns the calendar, and `years-since` counts on it.

- **The strict shape is the type's**: `2021-02-30` and `3/15/2024` are refused where the host's parser would read one of them, because the calendar is counted here rather than guessed.
- **A time is written to the second**, so one clock time has one spelling and a `unique(time)` field cannot hold both `09:30` and `09:30:00`.
- **A fitting value reads into a `DateTime`**, which formats it (`str("HH:mm")`), moves it by seconds (`addSeconds(90)`), and orders it against another of its kind (`compare`), so a fact's date is something a script can work with.
- **A `TimeSpan` measures the distance between two of them**, so `later.since(when).days` is how many days apart two dates are, and `.str` reads the span as `2d 00:00:00`.
- **Dates before 1970 work**, in both directions: the host's dates begin at the epoch, so an older date is counted and printed from its own parts, and a step that crosses back before 1970 is a count rather than a refusal.
- **`schema.receive(text)`** hands the reader on, since a module that imports `temporal.ms` gets its own copy and `isa` only agrees inside one copy.
- **`has-age` became a rule over `has-birthdate`**: the birthdate is stored and the age is derived on the day the query runs, so an age cannot go stale in a file.  The report was taught to carry the constraint past the fact it waits on, so asking for `has-age(zed, ?n)` names `has-birthdate(zed, ?b)` to add instead of saying nothing.

## The session corrects, not just grows

- **A unique field replaces instead of refusing**:
  ```
  ? has-gender(zed, male)
    added has-gender(zed, male)
  ? has-gender(zed, female)
    replaced has-gender(zed, male) with has-gender(zed, female)
  ```
- **`/retract <FACT>`** takes a stored fact out by name, wherever it stands, and a name the session does not hold says so without ending the question.
- **`/undo`** takes back the last change - an added fact, a replacement or a retraction - at the prompt or in the middle of a question, which puts the question again from the knowledge base it left.
- **The value prompt is a list when the schema says so**: a `boolean` or `a|b|c` field is offered numbered, and takes the number or the word.  A word outside the set is refused where it is typed rather than ending the question.
- **Digits at a number field are the number they spell**, so `24` completes an age rather than being refused as text.
- **A whole fact typed where a value is asked for is an answer by fiat**, and an empty value stops the asking with the report standing.
- **A fact that needs no variable is offered** with `add it? [y/N]` rather than assumed.
- **A value given once is not asked twice**: answers are carried to the rest of that rule's facts, so one parent's name turns the next check into a ground fact.
- **`/undo` and `/retract` answer inside a value prompt the same as at the prompt**, through one helper rather than two copies of the command table, so the two paths cannot drift apart.

## Answers are sentences when you ask for them

- **`--nlp` says each answer as a sentence.**  A predicate is named in lower case sections joined by dashes; saying it opens the dashes to spaces, so `has-uncle(oliver, zed)` is `oliver has uncle zed`.
- **The shipped predicates were renamed as verbs** - `is-parent-of`, `married-to`, `shares-age-group-with` - because the name is where the words come from.  There is no second table saying what a predicate means.
- **`--verbose` prints the proof tree before each answer**, not under it, so a verbose run reads in the order the reasoning went; `--nlp` says every line of the tree too, while a constraint such as `not-equal(?x, ?y)` stays as written because it has no sentence.
- **`--verbose` is off unless asked for.**  It had defaulted on and a run printed a proof tree nobody requested.
- **`triples.speak`** is the one function that decides say-it-or-show-it, replacing three copies of that decision.
- **`/facts` and `/rules` keep the fact form either way**, since each is something to read as data or write back.

```
? is-uncle(oliver, ?p)
  no solution found at depth 8
  A solution would need one of these:
    a fact like is-uncle(oliver, ?p)
  ?p = clara
  added is-uncle(oliver, clara)
  oliver is uncle clara  <- fact
  oliver is uncle clara
? is-parent-of(walter, ?p)
  walter is parent of bill  <- fact
  walter is parent of bill
  walter is parent of george  <- fact
  walter is parent of george
  walter is parent of henry  <- fact
  walter is parent of henry
```

The natural language wording is a little clumsy, but it communicates.  Later phases will hopefully smooth this out.

## Running it anywhere

- **Linux companions**: `bootstrap.sh` next to `bootstrap.bat`, and `micro-expert.sh`, `build-ext.sh` and `build-kb-ext.sh`.  The Linux interpreter unpacks at `3rd-party/miniscript-linux/miniscript` and has no extension, so the `.env` example differs by platform.
- **`--filter` and `--file` in the suite** (`test/run.ms`), with `--json` records per check and a `##END` line, so a test runner can ask for part of the suite and know it reached the end.  The VS Code Testing panel uses exactly those arguments.
- **`vscode-knowledge`**, the `.kb` highlighting extension: 0.1.0 at the format's first commit, 0.1.1 for the field-type grammar, 0.1.2 once `unique(...)` read as type syntax rather than a predicate name.  It now highlights `unique(...)`, the `|` value lists, and `date`, `time` and `datetime` as types.
- **The suite is 839 checks**, with case modules added since `v0.2.0` for the knowledge format (98), the schema (43), the date and time types (62), the loaders (19), the session (178), the domain (10), the command line (6), the Mermaid diagram (49) and the API layer (149).  The date cases live in `test/temporal.ms` so the module that owns the types owns their cases.

## Where to next?

### "Tool" Use

I've taken the family domain example about as far as it can go.  The next big leap is the weather domain.  The date and time types are a good first step towards that, but we will also need to incorporate the concept of *confidence level*: if there's a 40% chance of rain next Wednesday we don't want to oversell it.  Weather facts are ephemeral, only true for a certain time frame with a certain confidence, and worth little afterwards except as history.  A confidence is a number, which the schema can already type, so a miniature of the domain is mostly a renaming of what the engine does now:

```prolog
rain-chance(date, number)
high-temperature(date, number)
will-rain(date, number)
will-need-umbrella(date, number)
will-need-coat(date, number)
```

The first two belong to the forecast, and their facts are about a day rather than a person:

```prolog
rain-chance(2026-11-26, 40)
high-temperature(2026-11-26, 7)
rain-chance(2026-11-27, 10)
high-temperature(2026-11-27, 14)
```

The rest is reading, in the grammar the family rules already use, with the percent carried from the forecast to the answer:

```prolog
will-rain(?date, ?percent) => and(rain-chance(?date, ?percent), greater-than-or-equal(?percent, 30))
will-need-umbrella(?date, ?percent) => will-rain(?date, ?percent)
will-need-coat(?date, ?temperature) => and(high-temperature(?date, ?temperature), less-than(?temperature, 10))
```

Asked `will-need-umbrella(2026-11-26, ?p)`, it answers 40, and the tree says which threshold the 40 cleared:

```
? will-need-umbrella(2026-11-26, ?p)
  will-need-umbrella(2026-11-26, 40)  <- rule will-need-umbrella(?date, ?percent) <- will-rain(?date, ?percent)
    will-rain(2026-11-26, 40)  <- rule will-rain(?date, ?percent) <- rain-chance(?date, ?percent), greater-than-or-equal(?percent, 30)
      rain-chance(2026-11-26, 40)  <- fact
  will-need-umbrella(2026-11-26, 40)
```

The day after, it answers `no solution found at depth 8`, and the report names `will-rain(2026-11-27, ?p)` as the fact the rule went looking for.  Under `--nlp` the answer is said `2026-11-26 will need umbrella 40`, which is the naming rule showing its seam: the sentence is the predicate's dashes opened to spaces, and a date does not read much like a subject.

What is still missing is where the numbers come from.  On the day of the question neither forecast predicate has a fact, and a `.kb` file is a snapshot of the day it was saved.  Today the only ways one arrives are the prompt - where an unbound field is a value the session asks for - and a file loaded earlier; the engine never goes and looks.  That is the crack the weather domain opens: there is no fact in place for `rain-chance` on a date nobody has forecast yet, so for a certain class of predicates the engine should query for a response, and it doesn't need to query the *user*: it can query an API, caching what it gets against the date so the tree can still say where a confidence came from and when it was true.

### Embeddings

`will-need-umbrella`, `will-want-umbrella`, `will-wish-for-umbrella`; they all basically mean the same thing.  It would be nice if we could normalize the query input to an existing predicate.  This is something an embedding model is good at.  But how do we give MiniScript access to an embedding model?  TBC.

### Natural Language Chat

The big prize is a natural language conversation, where the question's words become a date and the engine does the reasoning:

```
User: Will I need a coat next Thursday?
Assistant:
*BEGIN THINKING*
Thursday is 2026-11-26; will-need-coat(2026-11-26, ?t)
  2026-11-26 will need coat 7  <- rule will-need-coat(?date, ?temperature) <- high-temperature(?date, ?temperature), less-than(?temperature, 10)
    high-temperature(2026-11-26, 7)  <- fact
*END THINKING*

Yes, you will want a coat next Thursday: 7 degrees, and the rule asks for one under 10.
```
