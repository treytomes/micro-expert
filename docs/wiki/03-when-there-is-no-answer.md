# 3. When there is no answer

An empty answer set is a result, not an error. This chapter shows how the session reports what it
would have needed, how to answer its questions, how to take a change back, and how the schema stops
a fact that no rule could use.

## The report

Ask about something the knowledge base does not know:

```text
? is-parent-of(?p, susan)
  no solution found at depth 8
  A solution would need one of these:
    a fact like is-parent-of(?p, susan)
```

The first line says the search failed and at what depth. The rest is a description of the missing
knowledge, in the same form you would write it. Here the only way to answer is a parent fact about
Susan, so that is what it asks for.

When a rule could conclude the question, the report names the rule and the facts its body would
still need. Running chapter 2's uncle question at `--depth 1` gives:

```text
? is-uncle-of(bill, ?p)
  no solution found at depth 1
  A solution would need one of these:
    a fact like is-uncle-of(bill, ?p)
    through rule is-uncle-of(?x, ?y) => is-parent-of(?p, ?y), is-sibling-of(?x, ?p), has-gender(?x, male)
      is-sibling-of(bill, ?p')
    (a name ending in ' is the rule's own variable, not one you asked about)
```

Read it as: either store the fact itself, or use this rule — and for this rule, you would need a
sibling of Bill. The `?p'` is the rule's own `?p`, primed to keep it distinct from the `?p` you asked
about. The parent and gender conditions are not listed as facts to add because the sibling fact, once
present, would bind them and they would be checked.

The report judges a body as a body. If each condition could be met on its own but not all at once,
the rule still appears with the set of facts its conditions would need, rather than being dropped as
if no rule could conclude the query. A condition the listed facts would settle is tagged
`(checked once the facts above exist)` instead of being listed as something to add: write down the
untagged lines, and the search decides the rest.

`--depth` bounds the report the same way it bounds the search, which is why the depth-1 run asks for
the sibling rather than the parent facts two levels down.

## Answering the report

At a plain prompt the report is informational and the session waits for your next line. But when a
question has no answer, the session asks for the values that would complete the missing fact:

```text
? is-parent-of(?p, susan)
  no solution found at depth 8
  A solution would need one of these:
    a fact like is-parent-of(?p, susan)
  ?p = walter
  added is-parent-of(walter, susan)
  walter is parent of susan
```

The fact being filled is shown above the question, with the values given so far already in it. A
`?` variable of the question is asked for like any other value. A rule's own variable is asked for
rather than the question's, since asserting the answer would prove nothing.

The loop asks one variable at a time. In the uncle example, the missing `is-parent-of(?p', susan)`
would ask first for `?p'`, then for the next fact. Values are carried across the rest of that rule's
facts, so a value is never asked for twice. A fact the session can already prove needs nothing added
and drops out of the report.

A few ways out of a value prompt:

| You type | What happens |
| --- | --- |
| A value, such as `walter` | Binds the variable and adds the completed fact |
| Nothing (just Enter) | Stops the asking and leaves the report standing |
| A whole fact, such as `is-uncle-of(oliver, walter)` | Asserts it as a fact, then starts the question again |
| A line that still holds a variable | Refused as a value; it is neither a fact nor a value |
| `/undo` | Takes back the last change, then asks the question again |
| `/retract <FACT>` | Removes a stored fact, then asks the question again |

If a fact is already complete — a condition that needed no variable — the session offers it with
`add it? [y/N]` rather than assuming. A fact that would still be incomplete once its own variables
are filled is shown with what is left and not added, rather than writing an answer into the knowledge
base as if it had been found.

Answering by fiat is still available when you want it. Typing a whole fact where a value is asked
for stores that fact and re-runs the question from the new knowledge base. That is how you assert an
answer instead of deriving it.

## Taking changes back

`/undo` takes back the last change — an added fact, a value that replaced one, or a retraction — at
the prompt or in the middle of a question. This is what keeps a wrong value from sticking for the
rest of the run:

```text
? /retract has-birthdate(tim, 2002-04-05)
  retracted has-birthdate(tim, 2002-04-05)
? has-age(tim, ?n)
  no solution found at depth 8
  A solution would need one of these:
    a fact like has-age(tim, ?n)
    through rule has-age(?x, ?n) => has-birthdate(?x, ?b), years-since(?b, ?n)
      has-birthdate(tim, ?b)
  has-birthdate(tim, ?b)
  ?b = /undo
  put has-birthdate(tim, 2002-04-05) back
  tim has age 24
```

`/retract <FACT>` is the other direction: it removes a stored fact **wherever it stands**, not just
the last one. It works at a value prompt too, and a fact the session does not hold says so without
ending the question, so a typo does not throw away the asking:

```text
? is-parent-of(?p, susan)
  no solution found at depth 8
  ...
  ?p = /retract has-birthdate(tim, 1999-01-01)
  no such fact: has-birthdate(tim, 1999-01-01)
  ?p =
```

Retraction only touches facts. A rule is not retracted this way; a rule you added at the prompt is
still there until you leave the session or load another rules file, and the shipped rules are
reloaded next run.

## The schema is a gate

`data/schema.kb` gives each predicate's field types. The prompt holds every fact and every question
against it before doing anything else, so a value no fact could store is refused where it is typed.
The object field of `has-age` is a `number`, so a word where a number belongs fails:

```text
? has-age(?a, twenty)
  refused: has-age(?a, twenty): the object should be a number
```

Quotes promise text, so the same digits quoted are text and are refused the same way — a `number`
field needs a number, not a name for one:

```text
? has-age(?a, "27")
  refused: has-age(?a, "27"): the object should be a number
```

A number is written bare, and a question with it finds what stores one:

```text
? has-age(?n, 24)
  has-age(tim, 24)
```

The message names the field by position — `object` is the second field of the triple.

A field typed `boolean`, or typed as a list of values such as `unique(male|female)`, offers the
choices numbered. You can answer with the number or with the word:

```text
? has-gender(zed, ?g)
  no solution found at depth 8
  A solution would need one of these:
    a fact like has-gender(zed, ?g)
  1) male
  2) female
  ?g = 1
  added has-gender(zed, male)
  zed has gender male
```

A word outside the list is refused at the prompt and asked for again, rather than completing a fact
the schema would refuse and ending the question with it. A text field keeps a plain prompt, since
there is nothing to choose from.

The date types are checked the same way. A `date` is `yyyy-MM-dd`, a `time` is `HH:mm:ss`, and a
`datetime` is `yyyy-MM-dd HH:mm:ss`. A reader also takes a month, a day or an hour written with
one digit, and a date or a clock left short, though what a fact keeps is the full shape. A value
in any other shape, or a day the calendar does not have (for example `2019-02-30`), is refused
like any other misfit. The calendar is bundled, so dates before 1970 are checked rather than
handed to the host and rejected.

### `unique(...)`

`unique(...)` around a field type says how many values the pair takes. `has-birthdate(text,
unique(date))` is one birthdate per person, so a second one corrects the first instead of sitting
beside it:

```text
? has-gender(zed, male)
  added has-gender(zed, male)
? has-gender(zed, female)
  replaced has-gender(zed, male) with has-gender(zed, female)
```

The corrected fact stands where the old one stood, because search tries facts in the order they are
held. The same rule is applied by the facts loader to a whole file, which is why `data/schema.kb` is
read before `data/facts.kb`: a file that stores the same unique pair twice is refused just as the
prompt would refuse it.

`unique(text)` in the subject position is the other direction — one subject per object. A predicate
that a rule concludes cannot carry `unique(...)`, because a derived fact is never added anywhere a
second one could be. A schema line that marks one is refused when the program starts, and
`/load-schema`, `/load-rules`, and a typed rule line refuse it too, so the prompt is not a way around
the check.

## A constraint is not a predicate

The seven built-in constraint names are conditions you write in a rule body, not predicates you can
store or ask. A line with a value in every field is checked where it stands and said `true` or
`false`; one that still holds a variable is refused:

```text
? less-than-or-equal(5, 3)
  false
? less-than-or-equal(?n, 18)
  refused: less-than-or-equal(?n, 18): the predicate is a constraint, checked in a rule body rather than stored or asked
```

The names are matched exactly, so `Equal` is an ordinary predicate. The `.kb` readers themselves
only see the shape of a line, which is why a facts file could technically store a triple named
`not-equal`; the prompt is what keeps that out of the session.

## Try it

Start a fresh session for each group, so the changes do not accumulate.

1. Ask `is-parent-of(?p, susan)` and answer `walter`. Then ask `is-child-of(susan, ?who)`; it should
   answer `walter`, because the new parent fact now feeds the child rule.
2. Ask `is-uncle-of(?p, susan)` and read the rule path. It asks for a parent of Susan, then for a
   sibling. Answer `george`, then `bill`; the answers should include `bill` and `henry`.
3. Ask `has-age(?a, twenty)` and confirm the refusal, then ask `has-age(?n, 24)` and confirm it finds
   Tim.
4. Type `less-than-or-equal(5, 3)` and confirm it is checked and said `false`, then type
   `less-than-or-equal(?n, 18)` and confirm it is refused as a constraint that still holds a variable.

Next: [4. Writing rules](04-writing-rules.md).
