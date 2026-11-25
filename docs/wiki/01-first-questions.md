# 1. Asking your first questions

By the end of this chapter you can start a session, tell a fact from a question, put a variable
where the unknown is, read the answers, and have the answers said as sentences.

## Start the session

Run the wrapper with no options:

```text
> micro-expert
[INF] micro-expert: micro-expert 0.2.0 starting
[INF] micro-expert: Command-line arguments (0): (none)
[INF] micro-expert: depth:      8
[INF] micro-expert: verbose:    0
[INF] micro-expert: nlp:        0
[INF] micro-expert: log-level:  information
Type a fact, a question or a rule as 'head => conditions', or a value to see how it reads. /help lists the commands; /exit leaves.
?
```

On Windows the wrapper is `micro-expert.bat`; on Linux it is `./micro-expert.sh`. Every example in
this wiki writes `micro-expert` for both. The timestamps in the log lines are trimmed for width.

With no options the session loads the default domain in `data/`: 54 facts, sixteen rules, and the
schema that types their fields. The `?` at the start of the last line is the **prompt** — it is
waiting for you to type. Variables also begin with `?`, so `? is-uncle-of(bill, ?p)` is the prompt
followed by a question containing one variable.

## One line has one meaning

The session decides what a line is from its shape.

| What you type | What it means |
| --- | --- |
| `is-parent-of(walter, bill)` | A ground fact. It is added to the session. |
| `is-grandpa-of(?who, tim)` | A question, because it holds a variable. |
| `is-grandparent-of(?x, ?y) => is-parent-of(?x, ?p), is-parent-of(?p, ?y)` | A rule, because it holds `=>`. |
| `oliver` | A value, said back the way a fact would write it. Nothing is stored. |
| `add(3, 5)` | A call working out a number: it is answered, `8`, since arithmetic reads nothing but the values it is given. Nothing is stored. |
| `less-than(5, 3)` | A constraint with a value in both fields: it is checked and said `true` or `false`. |
| `/help` | A command for the session itself. |

A ground line whose predicate is an ordinary name is always a fact. To ask whether something is
true, leave a variable in the line and read the answers: if the answer set is empty, nothing proves
it. Chapter 3 covers the report you get in that case. There is no separate "assert" command.

The two rows before `/help` are the exceptions, and neither one changes what the session holds. A
line that is one term — no `(` and no `|` — is that term said back, which is how a value is checked before it goes
into a fact:

```text
? "Dallas, TX"
  "Dallas, TX"
? 1e3
  1000
```

A line the date reader takes is said back as a `DateTime` instead, with its type in front, so
`2019-04-01` answers `DateTime 2019-04-01`.

The quotes are there because of the comma; a value that needs no quotes comes back without them, so
`oliver` answers `oliver`. They also promise the value is text, which is how an all-digit value
stays text: `"5"` is the text `5`, where `5` is the number.

A constraint's name is a shape a rule body checks rather than a predicate, so `less-than(5, 3)` is
checked where it stands — `false`, here — and a constraint that still holds a variable is refused,
because a check waiting on a value belongs in a rule body. Chapter 4 covers the seven names.

## Put the variable where the unknown is

Every predicate has the same shape: `predicate(subject, object)`. Ask "who is Bill an uncle of?" by
fixing Bill in the subject and putting a variable in the object:

```text
? is-uncle-of(bill, ?p)
  is-uncle-of(bill, anna)
  is-uncle-of(bill, mark)
  is-uncle-of(bill, clara)
  is-uncle-of(bill, jack)
  is-uncle-of(bill, nina)
  is-uncle-of(bill, oliver)
```

Each answer is the fact that proves the question, written the way you would write it in a facts
file. Bill is an uncle of six people: the children of his brothers George and Henry.

Ask "who is Tim's grandfather?" by moving the variable to the subject:

```text
? is-grandpa-of(?who, tim)
  is-grandpa-of(walter, tim)
```

The predicate reads "?who is the grandpa of tim", so the variable has to stand where the grandpa
goes. `is-grandpa-of(tim, ?who)` would ask who Tim is the grandpa of, which is nobody.

Both fields may be variables, and then the answer is every pair that holds:

```text
? is-grandma-of(?x, ?y)
  is-grandma-of(doris, tim)
  is-grandma-of(doris, anna)
  is-grandma-of(doris, mark)
  is-grandma-of(doris, clara)
  is-grandma-of(doris, jack)
  is-grandma-of(doris, nina)
  is-grandma-of(doris, oliver)
```

Seven pairs, all through Doris. The answers come in the order the search finds them, not sorted
alphabetically.

Nothing about uncles or grandmothers is stored. Every answer above is derived when you ask, from
the parent, sibling, and gender facts; chapter 2 shows the derivation.

## Say the answers in words

Add `--nlp` and each answer is said as a sentence:

```text
> micro-expert --nlp
? is-uncle-of(bill, ?p)
  bill is uncle of anna
  bill is uncle of mark
  ...
```

The name is where the words come from. A predicate is written in lower case in sections joined by
dashes, and the sentence is the subject, then the predicate's sections with the dashes opened to
spaces, then the object. `has-uncle(oliver, zed)` is said "oliver has uncle zed".

That is the whole mechanism — there is no second table saying what a predicate means — which is why
the shipped family names its predicates as verbs and the prepositions they need: `has-age`,
`married-to`, `is-uncle-of`. It is also why names such as `is-only-child-of` are said without
articles: "tim is only child of bill". A name that a sentence could not be made from is refused
where it is read.

`--nlp` changes only how results are displayed. The default answer is always the fact form, because
that is the form you can write back into a `.kb` file or ask again.

## Answers can be computed, not only looked up

Ages are not stored as facts. `has-age` is a rule over birthdates and today's date:

```text
> micro-expert --nlp
? has-age(tim, ?n)
  tim has age 24
```

On 21 November 2026, Tim — born 5 April 2002 — is 24. Ask the same question in a year and the answer
changes, because `years-since(...)` counts the years on the day the search runs. Chapter 4 explains
how a rule does that.

## Watch out: a ground line adds a fact

This trips up almost everyone once. Typing a complete triple does not test it; it asserts it:

```text
? is-uncle-of(bill, anna)
  added is-uncle-of(bill, anna)
```

If the fact is already known, the session says so rather than adding it twice. If it was only
derivable, it is now also stored as a fact — which changes later proofs, because a stored fact is a
reason of its own. To ask a question, always leave at least one variable.

## Commands for getting your bearings

A line that starts with `/` is a session command. The ones worth knowing now:

| Command | What it does |
| --- | --- |
| `/help [NAME]` | Lists every command, or prints one command's line |
| `/facts` | Lists the facts the session holds, in writing form |
| `/rules` | Lists the rules the session holds, as `head => conditions` |
| `/depth` | Says how deep the search goes |
| `/verbose [ON|OFF]` | Shows the proof tree before each answer, or stops showing it; a line naming neither switches it |
| `/nlp [ON|OFF]` | Says answers as sentences, or as the facts they are; a line naming neither switches them |
| `/exit` | Leaves the session |

`/facts` and `/rules` show what is in memory, including anything you added this session, and nothing
is written back to disk until you ask with a `/save-*` command (chapter 5). `/help` is the source of
truth if you forget a name.

## Try it

Start a session and ask these. The answers follow.

1. `is-grandpa-of(?who, tim)`
2. `is-grandma-of(?x, ?y)`
3. `is-only-child-of(tim, ?who)`
4. `married-to(doris, ?who)`

Answers: 1 is `walter is grandpa of tim`; 2 is the seven Doris pairs above; 3 is
`tim is only child of bill` and `tim is only child of susan`; 4 is `married-to(doris, walter)`,
derived by the rule that turns a marriage around, because only the couple's one direction is stored.

Next: [2. Reading a proof](02-reading-proofs.md) turns the answers inside out and shows the tree
behind each one.
