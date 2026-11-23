# The built-in constraints

A rule body is mostly goals — facts to prove by search — and a constraint is the other kind
of condition: something checked against the bindings the goals have already made. The seven
names below are built in and reserved, and they are written as calls so a body keeps one
shape whether a condition is proved or checked.

`docs/kb-grammar.md` says where a constraint sits in a `.kb` file. This note says what each
one does, what it does with a variable that is still unbound, and what it refuses.

## The seven names

```bnf
<constraint>       ::= <constraint-name> "(" <term> "," <term> ")"
<constraint-name>  ::= "not-equal" | "equal" | "years-since"
                     | "less-than" | "less-than-or-equal"
                     | "greater-than" | "greater-than-or-equal"
```

| Name | Kind | Holds when | Binds |
| --- | --- | --- | --- |
| `not-equal` | identity | the two fields are not the same term | no |
| `equal` | identity | the two fields are the same term | yes |
| `years-since` | calendar | the first field is a date, and the second is the whole years since it | yes, the years |
| `less-than` | comparison | both are numbers and the left is smaller | no |
| `less-than-or-equal` | comparison | both are numbers and the left is smaller or the same | no |
| `greater-than` | comparison | both are numbers and the left is larger | no |
| `greater-than-or-equal` | comparison | both are numbers and the left is larger or the same | no |

All seven take exactly two fields, and both have to be non-empty. The shape is the one a fact
has, and the fields go through the same term reader, so `?x` is a variable, a plain number is
a number, and everything else is text.

## `not-equal`

`not-equal` asks that its two fields not be the same term, read as they stand under the
current bindings. It holds for any type: `not-equal(tim, bob)` passes, and so does
`not-equal(1, "1")`, because a number and the text `1` are not the same term.

Its one piece of arithmetic is the number the term reader already did. `not-equal(1, 1.0)`
fails, and so does `not-equal(1e3, 1000)`, because each pair reads as one number.

```prolog
// ?x and ?y are siblings when they share at least one parent, so half-siblings count
// too, and nobody is their own sibling.
is-sibling-of(?x, ?y) => and(is-parent-of(?p, ?x), is-parent-of(?p, ?y), not-equal(?x, ?y))
```

A field that is still an unbound variable is compared by name. Two different names are two
different terms, so `not-equal(?x, ?y)` passes before either has been bound — a vacuous pass,
which is why the constraint belongs after the conditions that give it something to compare.
The same name is the same term, so `not-equal(?x, ?x)` never holds, bound or not:
`not-equal(?x, ?x)` with `?x` free already ends the branch, and with `?x = 1` it compares 1
with 1.

`not-equal` never binds. It agrees or disagrees with what the conditions before it settled,
and failing it ends that branch of the search.

## `equal`

`equal` asks that its two fields be the same term, and it is the one constraint that can bind:
a field that is still a variable takes the other field's value. Unification is exactly the
check `equal` needs — the same value holds, and a variable takes the other side — so `equal`
is one unification whose bindings are kept.

That is what lets a body say "the same one" about a value it has only just reached. The
shipped rule reaches the second age group through the first group's word, instead of looking
it up a second time:

```prolog
// ?x and ?y are in the same age group when both fall into one and it is the same one.
// The two groups are reached by separate conditions, so equal(?g, ?h) is what says they
// have to agree - and it is written the moment ?g is known, so ?h is already bound when
// the second condition goes looking for the people in it.
shares-age-group-with(?x, ?y) => and(belongs-to-age-group(?x, ?g), equal(?g, ?h), belongs-to-age-group(?y, ?h), not-equal(?x, ?y))
```

Both fields may be unbound: `equal(?a, ?b)` links them, and the next condition that binds
either one binds both. Both may also be ground, and then it simply checks them: `equal(1, 1.0)`
passes, because both read as numbers, while `equal("24", 24)` fails, because the quotation
marks are ordinary text and the field never becomes a number.

Whatever `equal` settles is visible to the conditions after it, to the answer, and to the
missing-fact report — the body of `shares-age-group-with` can go looking for the second person
with `?h` already bound to the first person's group.

## `years-since`

`years-since` is the one constraint that works a value out rather than only checking one:
`years-since(date, years)` reads its first field as a date written `YYYY-MM-DD` and binds the
second to the whole years between that date and today. A birthday that has not come round yet
this year is not counted, so the answer is the years on the day the search runs: on the 21st
of November 2026, `years-since("1948-03-14", ?n)` binds `?n` to 78.

It is not about ages in particular. A birthdate is one date among others, and the same
constraint counts the years since a founding, a move or a hire; the shipped rule is simply
the one this domain needed:

```prolog
// ?x is ?n years old on the day this runs. The birthdate is the fact and the age is
// arithmetic, so years-since(...) does the counting: a goal can only prove a fact, and a
// comparison only reads a number that is already there.
has-age(?x, ?n) => and(has-birthdate(?x, ?b), years-since(?b, ?n))
```

Both fields may be ground, and then it checks: `years-since("1948-03-14", 78)` passes today,
and `years-since("1948-03-14", 79)` does not. A first field that is not a date has no years
and ends the branch — `years-since(yesterday, ?n)`, `years-since("1948-3-14", ?n)` and
`years-since("2019-02-30", ?n)` all fail — so a date that reads as a different day cannot be
counted by accident. The second field is a number of whole years: a variable takes it, and
anything else is checked against one.

The report that says what a solution would need reads the same body, so a field the constraint
cannot read yet is carried past the fact already listed that would settle it: asking for
`has-age(zed, ?n)` with nothing about zed offers a `has-birthdate(zed, ?b)` to add, as well as
the fact shaped like the goal. A condition after it that reads the years keeps the same
promise, since the constraint settles them once that fact exists:

```prolog
// The age is worked out and then compared, and the report names the birthdate, not nothing.
over-65(?x, ?n) => and(has-birthdate(?x, ?b), years-since(?b, ?n), greater-than(?n, 65))
```

A date before 1970 is counted like any other, since the calendar is counted rather than taken
from the host, whose own dates begin in that year: walter's `1948-03-14` is a count of years and not
a refusal. **Today** is the host's clock unless `triples.today` is pinned to a table of `year`,
`month` and `day`; the checks pin it, so a birthday cannot quietly change a test's answer.

## Comparisons

The four comparisons read their fields arithmetically. They are the constraints that most
need a number on each side, and they are strict where their names say:

| Call | Holds when |
| --- | --- |
| `less-than(9, 18)` | left is strictly smaller — `less-than(18, 18)` fails |
| `less-than-or-equal(18, 18)` | left is smaller or the same |
| `greater-than(18, 18)` | left is strictly larger — this one fails |
| `greater-than-or-equal(18, 18)` | left is larger or the same |

A side that is not a number ends the branch instead of passing for a zero: text, a quoted
number such as `"9"`, and a variable nothing has bound all fail. This is deliberate — MiniScript
will not compare a string with a number, and as text `"9"` would sort after `"18"`. It is the
term reader that puts an age on the arithmetic side of the line: `18`, `1.0`, `.5` and `1e3`
are numbers, while `1e`, `eighteen` and `"18"` are text.

```prolog
// A child is 18 or younger; the line lives in the rule rather than in a column of facts.
belongs-to-age-group(?x, child) => and(has-age(?x, ?n), less-than-or-equal(?n, 18))
```

A comparison on a variable that a later condition would have bound cannot wait: it is checked
where it stands, so it ends the branch. The same is true in the report that says what a
solution would need — the comparison is checked against what is known, and with its field
still free the branch is gone, so that body is not offered as a way to answer. `equal` does
not have that problem, because it binds rather than checks. Two kinds of field are the
exception, both settled by a fact the body has already listed: the report carries the check
past that fact instead of ending the branch, which is how a missing age names the birthdate,
and a field `years-since` *binds* waits the same way, since the years are settled once the
date it reads exists.

## Constraint and grouping

A constraint is a condition, so it nests in `and(...)`, `or(...)` and `not(...)` like any
other. A negation of a constraint is a negation of the check, not of a search:
`not(not-equal(?x, 1))` holds exactly when `?x` is 1, and `or(equal(?x, 1), equal(?x, 2))`
holds for either value.

```prolog
is-sibling-of(?x, ?y) => and(is-parent-of(?p, ?x), is-parent-of(?p, ?y), not-equal(?x, ?y))
```

A constraint proves nothing, so it adds no step to a proof tree, and it asks for no fact in a
missing-fact report. Only goals do either.

## What a constraint is not

A constraint's name is a shape a body checks, not a predicate a fact stores or a question
asks. The prompt refuses a line whose predicate is one of the seven, whether it would have been
stored or asked:

```
refused: less-than-or-equal(5, 3): the predicate is a constraint, checked in a rule body rather than stored or asked
refused: less-than-or-equal(?n, 18): the predicate is a constraint, checked in a rule body rather than stored or asked
```

The names are matched exactly: `Equal` is an ordinary predicate, so `Equal(?x, 1)` in a body
is a goal to prove, not a check to make.

The `.kb` readers themselves do not refuse these names — `not-equal(tim, bob)` in a facts file
loads as a fact whose predicate is `not-equal`, and a rule head may name one — because the
readers only see the shape of a line. The refusal is the prompt's, which is where a line is
decided to be a fact or a question, and the shipped files never use a constraint as either.

## Reading a call

The call is split on its commas before the fields are read, so it is exactly two fields and
there is no quoting: `not-equal(?x, "a, b")` has three, and the entry is refused. Spaces
around the name and the fields are trimmed; `not-equal (?x, 1)` is accepted and reads back
without the space.

A malformed constraint refuses the whole entry. The rule reader reports it as a malformed
rule — `malformed rule: expected 'head <- condition, condition': ...` — and the `.kb` reader
puts the line number in front, the same way it reports any other broken entry. In particular:

| Written | Why it is refused |
| --- | --- |
| `not-equal(?n)` | one field |
| `not-equal(?x, ?y, ?z)` | three fields |
| `not-equal(?x,)` | an empty field |
| `not-equal()` | no fields at all |
| `not-equal(?x, ?y` | no closing parenthesis |
| `less-than(?x)` | one field |

## Where it lives

| File | What it holds |
| --- | --- |
| `src/triples.ms` | the constraints section: the seven names, `NotEqual`, `Equal`, `YearsSince`, `Comparison`, `comparisonHolds`, `holdsConstraint`, `applyConstraint`, `renameConstraint` |
| `src/knowledge.ms` | `parseCondition` and `constraintOf`, which read a constraint call out of a rule body |
| `src/temporal.ms` | the date, time and datetime types, and the calendar `years-since` counts on |
| `src/session.ms` | `refuseConstraint`, which keeps a constraint's name from being stored or asked at the prompt |
| `src/rule.ms` | the body solver's use of `applyConstraint`; a constraint adds no proof step |
| `test/relations.ms` | the checks behind the binding, arithmetic and proof-tree behaviour |
| `test/knowledge.ms` | the checks behind the call shape and its refusals |
| `test/session.ms` | the checks behind the prompt's refusal to store or ask one |
