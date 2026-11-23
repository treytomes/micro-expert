# 5. Your own domain

The family is only data. `data/facts.kb` holds the facts, `data/rules.kb` the rules, and
`data/schema.kb` the field types, and nothing else in the repository knows what a family is. Replace
those three files, or point the program at a folder of your own, and the same engine answers
questions about invoices, devices, or a library.

This chapter builds a small second domain, then covers the CLI options and the session's save and
load commands.

## A domain is three files

A domain folder holds the three files by those names. `--domain` reads them from there. With no
option the folder is `data/`.

| File | One entry is | Used by |
| --- | --- | --- |
| `facts.kb` | `predicate(subject, object)` | the facts loader, then search |
| `rules.kb` | `head => body` | the rules loader, then search |
| `schema.kb` | `predicate(field type, field type)` | the prompt and the facts loader |

The schema is read before the facts because it enforces `unique(...)` while the facts load. The
solver never reads it.

## Facts

One triple per line:

```prolog
is-parent-of(walter, bill)
has-gender(bill, male)
has-birthdate(bill, 1972-01-30)
```

Exactly two fields, both non-empty. Facts are ground: a stored fact has values where a variable
would be. Comments start at `//`
anywhere on a line, blank lines are skipped, and an entry may run over several physical lines while
its parentheses are still open.

## Rules

One rule per line, with `=>` between the head and the body:

```prolog
is-child-of(?x, ?y) => is-parent-of(?y, ?x)
married-to(?y, ?x) => married-to(?x, ?y)
is-sibling-of(?x, ?y) => and(is-parent-of(?p, ?x), is-parent-of(?p, ?y), not-equal(?x, ?y))
```

The head is a fact: exactly two fields. The body is one condition or more, joined by commas (an
implied *and*) or grouped with `and(...)`, `or(...)`, and `not(...)`. The same constraints are
available as at the prompt. An entry may break after the `=>` or inside any open parentheses:

```prolog
is-uncle-of(?x, ?y) => and(
	is-parent-of(?p, ?y),
	is-sibling-of(?x, ?p),
	has-gender(?x, male))
```

The file writes `=>`; the prompt and `Rule.text` write `<-`. Everything else about the shape is the
same.

## The schema

One line per predicate, giving the type of each field in the order a fact writes them:

```prolog
is-parent-of(text, text)
has-gender(text, unique(male|female))
has-birthdate(text, unique(date))
belongs-to-age-group(text, child|adult)
```

| Type | What fits it |
| --- | --- |
| `number` | any number, whole or fractional: `24`, `24.5`, `-3`, `1e3` |
| `text` | any text, which is what a person or a word is here |
| `boolean` | the word `true` or the word `false` |
| `date` | a calendar date, `yyyy-MM-dd`: `2019-04-01`, a month or a day one or two digits |
| `time` | a clock time, `HH:mm:ss`: `09:30:00`, an hour one or two digits |
| `datetime` | a date and a clock time, `yyyy-MM-dd HH:mm:ss`: `2019-04-01 09:30:00` |
| `a\|b\|c` | one of these words, exactly |
| `unique(t)` | a value of type `t`, and at most one per subject |

The three date types keep their value as text in the fact, in the one shape the type fixes. A value
written another way, or a day the calendar does not have, is refused. A month, a day and an hour
may be written with one digit where a reader takes them - `2019-4-1` is `2019-04-01` - though a
fact still keeps the full shape. `src/temporal.ms` can read a fitting value into a `DateTime` for
scripts that need to format, move, order or measure between it.

`unique(...)` wraps exactly one field type, so `unique()` and `unique(number, number)` are refused,
as is `unique(unique(number))`. It is about the pair rather than the value: a second value for the
same subject replaces the first. Put it on stored predicates only — a derived fact is never added,
so a schema line that marks a predicate a rule concludes is refused when the program starts.

The reader accepts any non-empty type word; the meaning is what the prompt gives it. A predicate the
schema does not name is accepted as written, and a repeated schema line keeps the last one. The
shipped file types every predicate the rules use, derived ones included, because that is what lets
the prompt refuse a constant no rule could match.

## Writing names and terms

A predicate is lower case, in sections joined by dashes, each section letters and digits, and the
first section starting with a letter: `is-parent-of`, `has-1-child`, `married-to`. A name written
another way — `Parent-Of`, `2nd-child`, `parent_of` — is refused where it is read, in a data file,
a schema line, and at the prompt alike. This is not a search rule; it is what makes `--nlp` possible,
because the name is the words of the sentence.

A field is a variable (`?x`), a number, or text. A number may carry a sign, a decimal point, and an
exponent with digits on both sides of the `e`: `24`, `-3`, `.5`, `1e3`, `1E-3`. `1e`, `e3`, `-`, and
`1.2.3` stay text, which is why a mistyped age cannot pass for a zero. A field in double quotes is
text and nothing else: `"24"` is the text `24`, so a `number` field refuses it the way it refuses a
word, and a number is written bare.

Two sequences cannot appear bare in a field: `//` starts a comment wherever it stands, and in a rule
`=>` splits the head from the body. Bare text also cannot hold a top-level comma or an unbalanced
parenthesis, since those decide where a field and a call end; a value holding one is written in
quotes, `"Dallas, TX"`, which is what the quotes are for. [The `.kb` grammar](kb-grammar.md) is the
exact reference.

## Point the program at another domain

```text
> micro-expert --domain domains/invoices
> micro-expert --domain domains/invoices --facts draft-facts.kb
```

`--domain` names the folder. `--facts`, `--rules`, and `--schema` each replace one component with a
file, while the folder supplies the other two. The component option wins over the folder's file of
that name. Paths are kept exactly as typed; use an absolute path when you are not sure what the
working directory will be.

## Worked example: a library

Create a folder `domains/library` and three files in it.

`domains/library/facts.kb`:

```prolog
// Who has which book.
borrowed(anna, dune)
borrowed(mark, dune)
borrowed(anna, emma)
```

`domains/library/rules.kb`:

```prolog
// ?x and ?y share a book when both borrowed the same one.
shares-book-with(?x, ?y) => and(borrowed(?x, ?b), borrowed(?y, ?b), not-equal(?x, ?y))
```

`domains/library/schema.kb`:

```prolog
borrowed(text, text)
shares-book-with(text, text)
```

Now run it:

```text
> micro-expert --domain domains/library
? shares-book-with(anna, ?y)
  shares-book-with(anna, mark)
? borrowed(?who, emma)
  borrowed(anna, emma)
```

The first question needs the rule: nobody stores who shares a book. `?b` is the shared book, and
`not-equal(?x, ?y)` keeps Anna from being her own answer — without it, `shares-book-with(anna, ?y)`
would answer `anna` as well as `mark`, because she borrowed `dune` too. The second question is a
direct fact and needs no rule, so it also answers at `--depth 0`.

With `--nlp`, the first answer is said "anna shares book with mark": the predicate name's dashes open
to spaces, with the subject first. Nothing in the engine knows the word "book"; it is all in the
name.

`shares-book-with` is typed in the schema even though its fields are only text. That is what lets
the prompt refuse a number where a borrower belongs. If you add a predicate and skip its schema
line, the engine still works, but the prompt accepts every value for it.

## Editing a domain from the session

Facts and rules you type at the prompt live in memory. Nothing is written back until you ask.
These commands move a component between memory and disk:

| Command | What it does |
| --- | --- |
| `/save-facts [FILE]` | Writes the facts to their file, or to the file named |
| `/load-facts [FILE]` | Replaces the facts with a file's |
| `/save-rules [FILE]` | Writes the rules to their file, or to the file named |
| `/load-rules [FILE]` | Replaces the rules with a file's |
| `/save-schema [FILE]` | Writes the schema to its file, or to the file named |
| `/load-schema [FILE]` | Replaces the schema with a file's |

A bare name is read as a file in the domain's folder and gets `.kb` added: `/save-facts draft`
writes `draft.kb` beside the facts it came from. A path with a space in it is quoted, as in
`/save-facts 'my notes.kb'`.

A save writes a temporary file and swaps it in when the whole file is written, so a save that fails
part way through leaves the file it was writing as it was; the only file it removes is the temporary
one it wrote itself. A load replaces the in-memory component, so the next question uses the new
data. Neither command edits the file behind your back: the session's state and the file on disk are
separate until you choose one direction.

## Try it

1. Build the library domain above and run both questions. Then add
   `borrowed(jack, dune)` at the prompt and ask `shares-book-with(jack, ?y)`. It should answer Anna
   and Mark. Save the facts with `/save-facts draft` and look at `domains/library/draft.kb`.
2. Start over and remove `not-equal(?x, ?y)` from the rule. Ask the same question and notice that
   Anna now shares a book with herself. Put it back.
3. In the session, type `/facts` after adding a fact. It shows the in-memory list, not the file —
   then `/load-facts` and watch your addition disappear because the file never had it.

Next: [6. Tests and extending the knowledge base](06-tests-and-extending.md) makes a rule change safe
to ship.
