# The `.kb` grammar

`.kb` files are the text form of the knowledge base. Three of them make a domain: the facts,
the rules, and the schema — `data/facts.kb`, `data/rules.kb` and `data/schema.kb` in the
folder this program ships. One reader accepts all three, `src/knowledge.ms`, and it reads
each field of a fact through the term reader in `src/triples.ms`, so one grammar covers the
three files and the terms in them.

## Notation

This is ISO/IEC 14977 BNF, with the two extensions everyone writes anyway:

| Form | Meaning |
| --- | --- |
| `<name>` | a production |
| `"text"` | a terminal, exactly those characters |
| `[ x ]` | `x`, or nothing |
| `{ x }` | `x`, zero or more times |
| `x - y` | everything in `x` that is not in `y` |
| `; ...` | a comment on the grammar, to the end of the line |

Spaces and tabs are insignificant between tokens — around a name, a field, a condition, an
annotation, an entry — and significant only inside a `<text>` field, where they are part of the value. A
leading or trailing space is trimmed from every field, so a value always begins and ends on
a character that is not a space or a tab.

## The grammar

```bnf
<document>         ::= { <entry> }

<entry>            ::= <statement>                  ; one or more physical lines, joined

<statement>        ::= <fact>                       ; facts.kb
                     | <rule>                       ; rules.kb
                     | <schema-line>                ; schema.kb

<fact>             ::= <call> [ <annotation> [ <annotation> ] ]
                     ; predicate(subject, object), then when it holds and how confident
<call>             ::= <name> <field-list>          ; the bare triple: a head, or a condition
<rule>             ::= <call> "=>" <body>
<schema-line>      ::= <name> <type-list>           ; predicate(field type, field type)

<body>             ::= <condition> { "," <condition> }

<condition>        ::= <grouping> | <constraint> | <call>

<grouping>         ::= <and> | <or> | <not>
<and>              ::= "and" <condition-list>
<or>               ::= "or"  <condition-list>
<not>              ::= "not" "(" <condition> ")"

<constraint>       ::= <constraint-name> <field-list>

<constraint-name>  ::= "not-equal"
                     | "equal"
                     | "years-since"
                     | "less-than"
                     | "less-than-or-equal"
                     | "greater-than"
                     | "greater-than-or-equal"

<condition-list>   ::= "(" <condition> { "," <condition> } ")"
<field-list>       ::= "(" <field> "," <field> ")"
<type-list>        ::= "(" <schema-type> "," <schema-type> ")"

<annotation>       ::= <temporal-annotation> | <confidence-annotation>
                     ; each at most once, in either order

<temporal-annotation> ::= "@" ( <moment> | <timespan> )
<moment>           ::= <date> | <time> | <datetime>
                     ; any text the date reader parses as a DateTime
<timespan>         ::= "[" <moment> "," <moment> "]"
                     ; any text the date reader parses as a TimeSpan
<date>             ::= <digits> "-" <digits> [ "-" <digits> ]
                     ; yyyy-MM-dd or yyyy-MM, a month or a day of one digit too
<time>             ::= <digits> ":" <digits> [ ":" <digits> ]
                     ; HH:mm:ss or HH:mm, an hour of one digit too
<datetime>         ::= <date> " " <time>
                     ; either side as short as it likes

<confidence-annotation> ::= "~" <number> "%"
                     ; any floating point number from 0 to 100

<field>            ::= <variable> | <number> | <text>
<variable>         ::= "?" <text>
<number>           ::= [ "-" ] <mantissa> [ <exponent> ]
<mantissa>         ::= <digits> [ "." { <digit> } ] | "." <digits>
<exponent>         ::= ( "e" | "E" ) [ "+" | "-" ] <digits>
<digits>           ::= <digit> { <digit> }

<text>             ::= <text-character> { <text-character> }
                     ; no top-level "," and no unbalanced "(" or ")";
                     ; and neither a <number> nor beginning with "?"

<name>             ::= <section> { "-" <section> }
                     ; lower case, sections joined by "-", none empty: is-parent-of
<section>          ::= <name-character> { <name-character> }
<name-character>   ::= <letter> | <digit>
<letter>           ::= "a" … "z"
<digit>            ::= "0" … "9"

<schema-type>      ::= <field-type>
                     | "unique" "(" <field-type> ")"
<field-type>       ::= <type-word> { "|" <type-word> }
<type-word>        ::= <text>
                     ; "number", "text", "boolean", "date", "time", "datetime",
                     ; or one value of a list
```

## Entries and lines

A file is read as physical lines, and an entry is one statement however many lines it
takes. Each physical line loses everything from its first `//` — that is its comment — and
the pieces are joined with a space. The entry ends on the first line after which the text
gathered so far has no unclosed `(` and does not end with `=>`:

```bnf
<entry>            ::= { <physical-line> }          ; while the text is still open, see below
<physical-line>    ::= <content> [ "//" <comment> ]
```

The reader's own test of "still open" is exactly two conditions, so this is the whole rule:

1. Take the next physical line.
2. Remove everything from its first `//`.
3. Append what is left to the entry, after a space.
4. If the text now has more `(` than `)` — a call is still open — or its trimmed end is `=>`,
   take the next line and go to 2.
5. Trim the text. If nothing is left, the entry is skipped: it was blank, or comments only.

That is why a body may be broken after its arrow or anywhere inside its parentheses, and
why nothing else may be broken:

```prolog
is-uncle-of(?x, ?y) => and(
	is-parent-of(?p, ?y),
	is-sibling-of(?x, ?p),
	has-gender(?x, male))

married-to(?y, ?x) =>
	married-to(?x, ?y)
```

A line ends at a line break, `\n` or `\r\n`, and the last line of a file need not end with
one. A file's line endings therefore make no difference to how it reads.

## Terms

Every field of a fact, and either side of a constraint, is one term, read by `termOf`:

- `?name` is a variable — an unknown, to be bound by the search.
- A `<number>` is a number, and is written bare.
- A field in double quotes is text: the quotes say where it ends, and what they hold is that
  text, never a number or a variable — `"24"` is the text `24`, and a `number` field refuses
  it.
- Anything else is text: the string itself, as it stands.

A number is written as one:

```bnf
<number>           ::= [ "-" ] <mantissa> [ <exponent> ]
<mantissa>         ::= <digits> [ "." { <digit> } ] | "." <digits>
<exponent>         ::= ( "e" | "E" ) [ "+" | "-" ] <digits>
```

So `24`, `-3`, `24.5`, `.5`, `5.` and `1e3` are numbers, and `1E-3` is one too. The
exponent needs a digit on each side of the `e`, the mantissa needs at least one digit, and
`-` may only open the number: `1e`, `e3`, `-`, `+5` and `1.2.3` all stay text, which is why
a mistyped age is a name no rule can reach rather than a zero.

Text is the rest. Bare, it has no top-level comma, since that separates fields and
conditions, and no unbalanced parenthesis, since that decides where a call ends and where an
entry continues. A value holding one of those is written in quotes, `has-home-town(guid,
"Dallas, TX")`, and so is a value that would otherwise read as a number or a variable; the
quotes are syntax, not part of the text, there is no escape for a double quote inside one,
and an unclosed quote refuses the entry. So `has-age(tim, "24")` is the text `24`, and the
schema refuses it where a number belongs. Two sequences cannot appear bare in a field: `//`,
because a comment starts there wherever it stands on the line, and, in a rule, `=>`, because
that splits the line into head and body; in quotes both are ordinary text.

## Predicate names

A name is lower case, its sections joined by `-`, none of them empty, and each of them
letters and digits. The first section starts with a letter, so a name never reads as a
number; a later one may open with a digit, which is how `has-1-child` is written. `is-parent-of`,
`married-to` and `has-1-child` are names; `Parent-Of`, `2nd-child`, `parent--of`,
`parent_of` and `parent of` are not.

The rule is not about the search - nothing in unification or proof cares what a predicate is
called. It is about saying a result: with `--nlp` an answer is said as a sentence, and the
sentence is the name with its dashes opened to spaces, so `has-uncle(oliver, zed)` is said
`oliver has uncle zed`. The name is the words, so there is no second table saying what each
predicate means, and a name no sentence could be made of is refused where it is read: in a
facts or rules file, in a schema line, and at the prompt. `?p(bill, susan)` is the one thing
that is not a name - a variable stands there - and an answer holding one keeps the fact form.

## Facts

```bnf
<fact>             ::= <call> [ <annotation> [ <annotation> ] ]
<call>             ::= <name> <field-list>
<field-list>       ::= "(" <field> "," <field> ")"
<annotation>       ::= <temporal-annotation> | <confidence-annotation>
```

One fact is one triple, `predicate(subject, object)`, and a facts file is one fact per
entry. Exactly two fields: `is-parent-of(walter)` is refused, and so is a call with nothing in
its parentheses or a field with no text in it.

After the closing `)` a fact may carry two annotations: when it holds, and how confident we
are that it does. Both are optional, so a fact may carry neither, either, or both; when it
carries both they may stand in either order, and each appears at most once. Anything else
after the `)` is refused rather than read — a second call, a lone `@` or `~`, the same
annotation twice.

```prolog
has-birthdate(walter, 1948-03-14)
married-to(walter, doris)
won-prize(bill, sprint) @ 2002-04-05
works-at(tim, school) ~ 80%
wakes-up(anna, early) ~ 60% @ 07:30:00
```

The first two carry neither annotation, so each is `~ 100%` and not time-bound, which is what
every fact written before the annotations existed says.

Both doors read this. A fact typed at the prompt takes the same annotations through the same
reader, so `won-prize(bill, sprint) @ 2002-04-05` typed there is the fact the same line in a
 file is — kept with its text, and written back in that form by `/save-facts`. Neither a question nor a
constraint is a fact: a line that still holds a variable is a search, and a constraint line is a
check, and the search and the check read neither annotation, so an annotated line of either is
refused rather than answered with the annotation dropped. And neither is a rule: its head and every condition are written bare, so an annotation on either is refused
wherever the rule is read.

### When a fact holds

`@` followed by a date, a time, a datetime, or a span between two of them, says when the
fact holds: the one instant it happened, or the range of instants it covers.

```bnf
<temporal-annotation> ::= "@" ( <moment> | <timespan> )
<moment>           ::= <date> | <time> | <datetime>
<timespan>         ::= "[" <moment> "," <moment> "]"
```

A moment is any text the date reader parses as a `DateTime` — `2002-04-05`, `07:30:00`,
`2002-04-05 07:30:00` — and a part may be left short the way a person writes one, since the
annotation is read through the same reader that fills a short part in: `2019-04` is the first
of that month, `09:30` the start of that minute, and `2019-4-1` the first of April. The fact
keeps the text as it was written, so nothing here rewrites `2019-04` as `2019-04-01`; a text
the reader refuses, `2019-02-30` or `25:00:00`, is refused with it.

A fact with no `@` is not time-bound. It holds at no particular instant, and no question about
when it holds can separate it from a fact that carries one.

A span is any text the date reader parses as a `TimeSpan`: two moments in square brackets
with a comma between them, each as short as it likes. Both of its ends count, so a fact
holding `@ [2019-04-01 09:00:00, 2019-04-01 17:00:00]` holds at 09:00:00 and at 17:00:00 as
well as between. A span written the other way round covers the same instants,
since what it names is the ground between the two. The span stays on the line of the fact it
annotates: only `(` and `)` decide whether an entry runs on to the next line, so a line
ending in `[` does not.

```prolog
won-prize(bill, sprint) @ 2002-04-05
works-at(tim, school) @ [2019-04-01 09:00:00, 2019-04-01 17:00:00]
wakes-up(anna, early) @ 07:30:00
```

### How confident a fact is

```bnf
<confidence-annotation> ::= "~" <number> "%"
```

`~` followed by a number and a `%` says how confident we are that the fact holds. It is any
floating point number from 0 to 100 — `~ 87.5%` is a confidence — and a number outside that
range is refused.

A fact with no `~` is `~ 100%`: we are fully confident of it, which is what saying nothing
has always meant. The two annotations do not depend on each other, so a fact may be sure of
when it holds, unsure, sure of an instant, or neither.

```prolog
works-at(tim, school) @ [2019-04-01 09:00:00, 2019-04-01 17:00:00] ~ 80%
works-at(tim, school) ~ 80% @ [2019-04-01 09:00:00, 2019-04-01 17:00:00]
```

The last two lines are one fact written twice: the annotations may stand in either order.

A fact is known by its whole line, annotations and all, so those two lines are one fact and
`works-at(tim, school) @ 2002-04-05 ~ 80%` is another. Two facts that differ only in when they
hold, or only in how sure we are, are two facts: a reading at 1 pm and a reading at 2 pm sit
beside each other rather than one being taken for the other. An answer carries the annotation of
the fact it came from, so a question about two hours says which hour each answer covers; with
`--nlp` it says so in words as well - `berlin has precipitation 4.1 during [2026-11-22 00:00,
2026-11-22 01:00], 40% confident` - rather than printing one sentence twice.

## Rules

```bnf
<rule>             ::= <call> "=>" <body>
<body>             ::= <condition> { "," <condition> }
<condition>        ::= <grouping> | <constraint> | <call>
```

A rule is one head and one body, joined by `=>`, which appears exactly once. The head is a
call: exactly two fields, and no annotation, since `@` and `~` say when a stored fact holds
rather than what follows from others. The body is one condition, or a comma-delimited list of
them — the implied *and*. A condition is a call, a constraint, or a grouping, and a call
there carries no annotation either.

The three groupings say their own name:

```bnf
<and>              ::= "and" <condition-list>
<or>               ::= "or"  <condition-list>
<not>              ::= "not" "(" <condition> ")"
<condition-list>   ::= "(" <condition> { "," <condition> } ")"
```

`and(...)` and `or(...)` take one condition or more; `and()` and `or()` are refused.
`and(...)` flattens into the conditions it holds, and nests without limit, so a body may say
its implied *and* out loud in any shape. `or(...)` becomes one condition holding
alternatives, each of which is a condition of its own, so `or(and(a, b), c)` reads as it
looks. `not(...)` takes exactly one condition — a body of several has to be joined out loud
as `not(and(a, b))`, and `not(a, b)` is refused rather than guessed at.

```prolog
is-sibling-of(?x, ?y) => and(is-parent-of(?p, ?x), is-parent-of(?p, ?y), not-equal(?x, ?y))
is-in-law-of(?x, ?y) => or(and(married-to(?x, ?p), is-sibling-of(?p, ?y)), and(is-sibling-of(?x, ?p), married-to(?p, ?y)))
is-only-child-of(?x, ?y) => and(is-parent-of(?y, ?x), not(is-sibling-of(?x, ?q)))
```

## Constraints

```bnf
<constraint>       ::= <constraint-name> <field-list>
<constraint-name>  ::= "not-equal" | "equal" | "years-since"
                     | "less-than" | "less-than-or-equal"
                     | "greater-than" | "greater-than-or-equal"
```

A constraint is a condition that is checked against the bindings rather than proved by
search, and it is written as a call so that a body keeps one shape. It takes exactly two
fields, both non-empty: `not-equal(?x)` and `equal(?n)` are refused.

`not-equal` and `equal` read their fields as they are, whatever type they hold; `equal` can
also bind a field that is still a variable. `years-since` reads its first field as a
`YYYY-MM-DD` date and binds the second to the whole years since it. The four comparisons read
arithmetically and
need a number on each side, so a name never passes for a zero.

```prolog
is-sibling-of(?x, ?y) => and(is-parent-of(?p, ?x), is-parent-of(?p, ?y), not-equal(?x, ?y))
belongs-to-age-group(?x, child) => and(has-age(?x, ?n), less-than-or-equal(?n, 18))
shares-age-group-with(?x, ?y) => and(belongs-to-age-group(?x, ?g), equal(?g, ?h), belongs-to-age-group(?y, ?h), not-equal(?x, ?y))
```

## The schema

```bnf
<schema-line>      ::= <name> <type-list>
<type-list>        ::= "(" <schema-type> "," <schema-type> ")"
<schema-type>      ::= <field-type>
                     | "unique" "(" <field-type> ")"
<field-type>       ::= <type-word> { "|" <type-word> }
<type-word>        ::= <text>
```

One line per predicate, giving the type of each field in the order a fact writes them.
Exactly two field types, both non-empty. A type is one of these:

| Type | What fits it |
| --- | --- |
| `number` | any number, whole or fractional |
| `text` | any text |
| `boolean` | the word `true` or the word `false` |
| `date` | a calendar date, `yyyy-MM-dd`: `2019-04-01`, a month or a day one or two digits |
| `time` | a clock time, `HH:mm:ss`: `09:30:00`, an hour one or two digits |
| `datetime` | a date and a clock time, `yyyy-MM-dd HH:mm:ss`: `2019-04-01 09:30:00` |
| `a\|b\|c` | one of these words, exactly |
| `unique(t)` | a value of type `t`, and at most one of them per subject |

The three date types keep their value as text in the fact, in the one shape the type
fixes, and a value written any other way - or a day the calendar does not have - is
refused like any other misfit. A time is written to the second, so one clock time has one
spelling and a `unique(time)` field cannot hold both `09:30` and `09:30:00` for one
subject. `src/temporal.ms` reads a fitting value into a `DateTime`, which formats it, moves it
by seconds and orders it against another of its kind. A reader, unlike a fact, also takes a
part left short - `2019-04` is the first of that month, `09:30` the start of that minute - and
reads a month, a day or an hour written with one digit too, since that is how a person writes a
date by hand, and it reads the text as that instant, so a script may hand it what a person
wrote and take the full shape back. Two values in square brackets, `[2019-04-01, 2019-04-03]`,
read as the `TimeSpan` between them, and one typed on a line of its own at the prompt is read
the same way and said back as a `TimeSpan` with the two ends it kept, so a line can be read
without asking a script. A line on its own that reads as a date, a time or a datetime is said
back as a `DateTime` with its type in front, so `2019-04-01` answers `DateTime 2019-04-01`; a
line the reader refuses is still said back as the text it was. The host's own dates begin in
1970, so an older date is checked and counted by that reader rather than by the host, and
prints in its kind's one shape; a date the host can hold prints in whatever `str(...)` format
asks for.

```prolog
is-parent-of(text, text)
has-gender(text, unique(male|female))
has-birthdate(text, unique(date))
belongs-to-age-group(text, child|adult)
```

The reader accepts any non-empty type word; the meaning is what the prompt gives it. A
predicate the schema does not name is accepted as it is written, and a schema line repeats
what it says — the last line for a predicate is the one kept.

`unique(...)` is the one shape the reader takes apart rather than keeping whole, and only
to check it: it wraps exactly one field type, so `unique()` and `unique(number, number)`
are refused, as is `unique(unique(number))`, and a bare `unique` is an ordinary word, so a
domain that allows that value still writes it. What it means is about the pair rather than
the value — `has-birthdate`'s date is one per person — so it is the prompt and the facts loader
that apply it, the value set there taking the place of the one already held, and
`unique(...)` on a predicate a rule concludes is refused when the program starts, since a
derived fact is never added anywhere a second one could be.

## Names the reader treats specially

Seven names never name a fact inside a rule body. `and`, `or` and `not` are groupings there,
and the seven constraint names above are constraints there. A call spelled with one of those
names is read that way, whatever it holds.

Outside a rule body they are ordinary text, because nothing there looks for them: in a facts
file, `not-equal(a, b)` is stored as a triple whose predicate is `not-equal`, and the prompt
is what refuses such a fact rather than the file reader.

The predicate goes through the same term reader as either field, so a variable or a number
stands in the predicate's place too: `?p(a, b)` and `18(a, b)` both parse. No file in the
repo writes one.

## Where the grammar lives

| Place | What it holds |
| --- | --- |
| `src/knowledge.ms` | `entries`, `parseFacts`, `parseRules`, `parseSchema`, and the writer that puts each back |
| `src/temporal.ms` | `DateTime` and `TimeSpan`, the values behind those types |
| `src/triples.ms` | `termOf` and `isNumber`, the reading of one term, and the two annotations a fact may carry, which the file and the prompt both read |
| `test/knowledge.ms` | 141 checks on the format, a fact's annotations, and its writer |
| `test/schema.ms` | 43 checks on the schema format, the field check and the one-value rule |
| `test/temporal.ms` | 79 checks on the three date types, the shapes a text reads from (a month, a day and an hour may be one digit), the value it is read into, the span between two, and whether a value stands inside one |
| `vscode-knowledge/` | the same shape as a TextMate grammar, for highlighting only |

A refusal names the entry it came from, `line N: ...`, where `N` is the first physical line
of that entry, and a loader prefixes the file's name.
