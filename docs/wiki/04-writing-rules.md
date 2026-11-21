# 4. Writing rules

Facts say what is true. Rules say what follows. This chapter covers the shape of a rule, how
variables join conditions, the three groupings, the seven constraints, and where to put a rule so it
is still there next run.

## Two arrows

The same rule has two spellings, and the arrow tells you where you are:

| Where | Written | Example |
| --- | --- | --- |
| At the prompt, and in `/rules` and proof trees | `head <- conditions` | `is-child-of(?x, ?y) <- is-parent-of(?y, ?x)` |
| In a `.kb` file | `head => conditions` | `is-child-of(?x, ?y) => is-parent-of(?y, ?x)` |

A line typed at the prompt with `<-` in it is a rule. A line in `rules.kb` with `=>` is the same
thing. `Rule.text` prints the `<-` form, which is why the prompt and the proof trees use it. The
prompt's parser expects `<-`; do not type `=>` at the prompt.

## Anatomy of a rule

```prolog
is-grandparent-of(?x, ?y) <- is-parent-of(?x, ?p), is-parent-of(?p, ?y)
```

- The **head** is the one triple the rule can prove: `is-grandparent-of(?x, ?y)`.
- The **body** is one condition or a comma-delimited list. The comma is an implied *and*: all
  conditions must hold.
- **Variables** are the names beginning with `?`. A variable shared between the head and the body
  carries a value out of the body into the answer. A variable that appears only in the body, such as
  `?p` here, is existential: it has to be some value, and the answer does not include it.

Read the rule above as: `?x` is a grandparent of `?y` when `?x` is a parent of some `?p` and `?p` is
a parent of `?y`. The same variable name in two conditions is what forces the two conditions to be
about the same person.

A rule's head is always exactly two fields. A condition is a fact, a constraint, or a grouping.

## Groupings

`and(...)`, `or(...)`, and `not(...)` are the three ways to shape a body beyond a flat list.

```prolog
// The implied and, written out. It flattens and nests without limit.
is-sibling-of(?x, ?y) => and(is-parent-of(?p, ?x), is-parent-of(?p, ?y), not-equal(?x, ?y))

// Either alternative is enough. Only the branch that succeeded appears in the proof.
is-in-law-of(?x, ?y) => or(and(married-to(?x, ?p), is-sibling-of(?p, ?y)), and(is-sibling-of(?x, ?p), married-to(?p, ?y)))

// The body must have no proof. It takes exactly one condition.
is-only-child-of(?x, ?y) => and(is-parent-of(?y, ?x), not(is-sibling-of(?x, ?q)))
```

`and(...)` and `or(...)` take one condition or more; `and()` and `or()` are refused. `or(...)` holds
alternatives as conditions of their own, so `or(and(a, b), c)` reads as it looks. `not(...)` takes
exactly one condition: a body of several must be joined out loud as `not(and(a, b))`, and
`not(a, b)` is refused rather than guessed at.

Negation is the one grouping that cannot go looking for bindings. It succeeds when the search finds
no proof of its body with the bindings already in hand, so the conditions that bind its variables
have to come first. That is why the only-child rule asks for the parent first, then says no sibling
exists. Move the negation first and it would pass vacuously, before anyone is bound.

## Constraints

A constraint is checked against the bindings instead of proved by search. It is written as a call,
so a body keeps one shape. Seven names are built in and reserved:

| Name | Holds when | Binds |
| --- | --- | --- |
| `not-equal(a, b)` | the two fields are not the same term | no |
| `equal(a, b)` | the two fields are the same term | yes |
| `years-since(date, years)` | `date` is a date; `years` is the whole years since it | yes, the years |
| `less-than(a, b)` | both are numbers and `a < b` | no |
| `less-than-or-equal(a, b)` | both are numbers and `a <= b` | no |
| `greater-than(a, b)` | both are numbers and `a > b` | no |
| `greater-than-or-equal(a, b)` | both are numbers and `a >= b` | no |

All seven take exactly two non-empty fields. [The built-in constraints](constraints.md) is the full
reference; these are the parts that matter while writing rules:

- **`equal` binds.** It is unification with the bindings kept: a side that is still a variable takes
  the other side's value, and both sides may be unbound, linking them for later conditions. That is
  how one condition can say "the same one" without a second lookup.
- **`not-equal` only checks.** It passes for two unbound variables with different names, vacuously,
  so put it after the conditions that bind them. It never binds, and failing it ends that branch.
- **Comparisons are arithmetic.** Both sides must be numbers; text, including `"18"`, fails rather
  than passing for zero. A comparison on a variable a later condition would have bound cannot wait —
  it is checked where it stands.
- **`years-since` counts.** It reads `YYYY-MM-DD` and binds the whole years since that date, or
  checks a number given to it. The count is as of the day the search runs, unless `triples.today` is
  pinned (the tests pin it, so a birthday cannot change a test's answer).

The shipped rules use each of these:

```prolog
has-age(?x, ?n) => and(has-birthdate(?x, ?b), years-since(?b, ?n))
belongs-to-age-group(?x, child) => and(has-age(?x, ?n), less-than-or-equal(?n, 18))
belongs-to-age-group(?x, adult) => and(has-age(?x, ?n), not(belongs-to-age-group(?x, child)))
shares-age-group-with(?x, ?y) => and(belongs-to-age-group(?x, ?g), equal(?g, ?h), belongs-to-age-group(?y, ?h), not-equal(?x, ?y))
```

The adult rule gets its other group from the child rule rather than repeating the threshold, so
"childhood ends at 18" is written once. The `shares-age-group-with` rule writes `equal(?g, ?h)` the
moment `?g` is known, so `?h` is already bound when the second person is looked up.

Constraint names are not predicates: `less-than-or-equal(5, 3)` typed at the prompt is refused
rather than stored or asked. The names are matched exactly, so `Equal` is an ordinary predicate.

## Walk-through: a grandparent rule

Type the rule at the prompt. It joins the search immediately:

```text
> micro-expert --nlp
? is-grandparent-of(?x, ?y) <- is-parent-of(?x, ?p), is-parent-of(?p, ?y)
  added rule is-grandparent-of(?x, ?y) <- is-parent-of(?x, ?p), is-parent-of(?p, ?y)
? is-grandparent-of(?p, tim)
  walter is grandparent of tim
  doris is grandparent of tim
```

Tim's parents are Bill and Susan. Bill's parents are Walter and Doris; Susan's parents are not in the
knowledge base. Walter and Doris are therefore the two grandparents the rule can reach. Note that
`is-grandparent-of(?p, tim)` puts the variable in the grandparent position, as chapter 1 taught.

The rule uses only stored predicates, so it needs one rule level, and even `--depth 1` would answer
it. The shipped domain does not have this rule — it has separate `is-grandpa-of` and `is-grandma-of`
rules, because each adds a gender condition.

## Walk-through: a cousin rule

A rule can join three conditions and two derived relations:

```text
> micro-expert --nlp
? is-cousin-of(?x, ?y) <- is-parent-of(?p, ?x), is-sibling-of(?p, ?q), is-parent-of(?q, ?y)
  added rule is-cousin-of(?x, ?y) <- is-parent-of(?p, ?x), is-sibling-of(?p, ?q), is-parent-of(?q, ?y)
? is-cousin-of(tim, ?y)
  tim is cousin of anna
  tim is cousin of mark
  tim is cousin of clara
  tim is cousin of jack
  tim is cousin of nina
  tim is cousin of oliver
```

`?p` is Tim's parent, `?q` is a sibling of `?p`, and `?y` is a child of `?q`. Because `is-sibling-of`
is itself a rule, this one spends two rule levels and needs a depth of at least 2. It also shows why
the variable names matter: `?p` and `?q` are different people, and only the shared name `?p` across
the first two conditions makes them meet at Tim's parent.

The new predicate `is-cousin-of` has no schema line yet. The prompt accepts a predicate the schema
does not name, so the rule still works, but it will not type-check its fields. Chapter 5 adds the
line when the rule moves into a file.

## The fifteen shipped rules, grouped

Reading the rules file is the best way to learn the idiom. In `data/rules.kb`:

| Group | Rules | What to notice |
| --- | --- | --- |
| Inverses | `is-child-of`, `married-to` | The second is symmetric: one stored direction answers both, and the cycle guard keeps it finite |
| Siblings | `is-sibling-of`, `is-brother-of`, `is-sister-of` | Sharing one parent is enough, so half-siblings count; `not-equal` excludes self |
| Aunts and uncles | `is-uncle-of`, `is-aunt-of` | Same body with a gender condition; the sibling is of the parent, not of the child |
| Grandparents | `is-grandpa-of`, `is-grandma-of` | Two parent links in a row, then the gender of the older one |
| In-laws | `is-in-law-of` | One `or(...)` for the two ways to marry into a family |
| Only child | `is-only-child-of` | `not(...)` asks for the absence of a sibling |
| Age | `has-age` | `years-since` computes the number; nothing stores an age |
| Age groups | `belongs-to-age-group` (child and adult) | One comparison and one negation, with the threshold written once |
| Shared group | `shares-age-group-with` | `equal` binds the second group from the first |

All fifteen are typed in `data/schema.kb`, derived predicates included. That typing is what lets the
prompt refuse a question whose constant could never match, and it is part of adding a rule to the
shipped domain (chapter 6).

## Order matters

The search solves a body left to right. That is invisible for pure goals, which can be reordered
freely, but it matters for the conditions that read bindings:

- a `not(...)` must come after the conditions that bind the variables it mentions;
- a comparison must come after both its sides have numbers;
- `equal` can come early when one side is known, because it binds the other;
- `years-since` must come after the date it reads, and before anything that reads the years.

If a body looks right but never fires, move the binding conditions earlier before suspecting
anything else.

## Rules at the prompt versus rules in a file

A rule typed at the prompt lives in memory for that session only. It is searchable immediately, and
`/rules` lists it, but it is not written anywhere. `/save-rules` writes the session's rules back to
their file; chapter 5 covers the save and load commands.

A rule in `data/rules.kb` is loaded at startup. Editing the file does not change a session already
running; start a new one, or use `/load-rules` to replace the session's rules with the file's.

Both places accept comments (`//` to the end of the line) and multi-line entries. A file entry may
break after `=>` or inside its parentheses; the prompt's parser is fed one line at a time, so keep a
typed rule on one line.

## Try it

1. Add a nephew rule at the prompt:

   ```text
   ? is-nephew-of(?x, ?y) <- is-parent-of(?p, ?x), is-sibling-of(?p, ?y), has-gender(?x, male)
   ```

   Then ask `is-nephew-of(?n, bill)`. It should answer Mark, Jack, and Oliver: the male children of
   Bill's brothers. Anna and Nina are nieces, and Tim is Bill's child rather than a nephew.
2. Change the grandparent rule to require the older person's gender, and compare it with the shipped
   `is-grandpa-of`. The only difference should be the condition you added.
3. Ask `belongs-to-age-group(?x, child)` and then `belongs-to-age-group(?x, adult)`. The two rules
   cover everyone with a birthdate, and nobody appears in both.

Next: [5. Your own domain](05-your-own-domain.md) moves rules out of the session and into files,
then replaces the family altogether.
