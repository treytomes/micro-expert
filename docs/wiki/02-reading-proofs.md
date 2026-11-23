# 2. Reading a proof

By the end of this chapter you can turn on proof trees, read one line by line, explain why one answer
can carry two derivations, and use `--depth` to bound the search.

## Turn the trees on

`--verbose` prints the proof tree before each answer. Ask with a variable, as always:

```text
> micro-expert --verbose
? is-uncle-of(bill, ?p)
  is-uncle-of(bill, anna)  <- rule is-uncle-of(?x, ?y) <- is-parent-of(?p, ?y), is-sibling-of(?x, ?p), has-gender(?x, male)
    is-parent-of(george, anna)  <- fact
    is-sibling-of(bill, george)  <- rule is-sibling-of(?x, ?y) <- is-parent-of(?p, ?x), is-parent-of(?p, ?y), not-equal(?x, ?y)
      is-parent-of(walter, bill)  <- fact
      is-parent-of(walter, george)  <- fact
    is-sibling-of(bill, george)  <- rule is-sibling-of(?x, ?y) <- is-parent-of(?p, ?x), is-parent-of(?p, ?y), not-equal(?x, ?y)
      is-parent-of(doris, bill)  <- fact
      is-parent-of(doris, george)  <- fact
    has-gender(bill, male)  <- fact
  is-uncle-of(bill, anna)
  is-uncle-of(bill, mark)  <- rule ...
  ...
```

Here is how to read it.

- **The top line** is the answer being derived. The part before `<-` is the goal with its variables
  filled in; the part after is the reason it holds. `<- rule` names the rule and repeats its body.
- **The lines under it** are the conditions of that rule, in the order the body wrote them: a parent
  of Anna, a sibling of that parent, and that sibling's gender. The tree is indented one level per
  body.
- **A leaf** ends in `<- fact`. It is a stored triple and there is nothing below it. Every branch
  ends in facts; nothing in the tree has to be taken on trust.
- **The last line** of each block repeats the answer alone. That is the result the tree justifies.

The same fact form is used in the tree, in `/facts`, and in the default answer. The `<-` arrow is the
one `Rule.text` prints and the one you type at the prompt; the `.kb` files write `=>` instead.

Remember from chapter 1 that a ground line adds a fact rather than asking a question — a line whose
predicate is an ordinary name, that is; a lone value and a ground constraint are only reported.
Running `--verbose` does not change that: `is-uncle-of(bill, anna)` is still a ground line, so it is
added and there is no search to show. Leave a variable to get a proof.

## One answer can have more than one derivation

Look at the two `is-sibling-of(bill, george)` blocks under Anna's answer. They are not duplicates:

- the first reaches the sibling conclusion through `is-parent-of(walter, bill)` and
  `is-parent-of(walter, george)`;
- the second reaches it through `is-parent-of(doris, bill)` and `is-parent-of(doris, george)`.

The sibling rule only asks that the two people share **at least one** parent, so both derivations
are valid. The solver keeps both rather than silently dropping one, because a reasoner that hides a
reason is hiding information. That is also why a half-sibling counts: one shared parent is enough.

Each of the six answers gets its own tree, and each tree is built the same way. Bill is an uncle of
Anna and Mark through George, and of Clara, Jack, Nina, and Oliver through Henry. Those two sibling
blocks appear under every child of that brother.

## Depth

The uncle rule needs the sibling rule, which needs the parent facts. That is two rule levels. The
solver's depth budget counts how many rule levels it may descend; `--depth` sets it, and the default
is `8`.

`--depth 2` is enough for `is-uncle-of`:

```text
> micro-expert --depth 2
? is-uncle-of(bill, ?p)
  is-uncle-of(bill, anna)
  is-uncle-of(bill, mark)
  ...
```

`--depth 1` is not, and the run says so instead of failing silently:

```text
> micro-expert --depth 1
? is-uncle-of(bill, ?p)
  no solution found at depth 1
  A solution would need one of these:
    a fact like is-uncle-of(bill, ?p)
    through rule is-uncle-of(?x, ?y) <- is-parent-of(?p, ?y), is-sibling-of(?x, ?p), has-gender(?x, male)
      is-sibling-of(bill, ?p')
    (a name ending in ' is the rule's own variable, not one you asked about)
```

The session then asks for a value, as it does whenever a question has no answer; chapter 3 is
entirely about that loop. The report already tells you what a deeper run would do: it needs a
sibling of Bill, and that is one rule level below the goal.

`--depth 0` means facts only. A question whose answer is a stored fact still works; a question that
needs any rule answers nothing, because no rule may be used. It is a quick way to separate "stored"
from "derived".

The bound is a budget, not a fixed chain length: a rule that nests two derived conditions can spend
more than one level on its body. The default of 8 leaves plenty of room for the shipped family,
whose longest chain is three rules (`shares-age-group-with` through `belongs-to-age-group` to
`has-age`).

## Cycles

A rule may be symmetric, and the shipped knowledge base has one:

```prolog
married-to(?y, ?x) => married-to(?x, ?y)
```

Ask `married-to(walter, doris)` and the fact proves it. Ask `married-to(doris, ?who)` and the rule
turns the stored fact around. If the search were naive, it could then apply the rule again to its own
result forever. It does not, because the search keeps the chain of goals on the current branch and
refuses to re-enter a goal it is already inside. Goals are compared with variables renamed away, so
`?x` and `?x_7` are recognized as the same goal rather than two fresh ones.

You do not need to write cycle guards in rules. `--depth` is still there as a backstop, and a query
that seems to need an unreasonable depth is usually a sign that a rule is written too generally.

## Proofs in words

`--nlp` says the answers as sentences, and with `--verbose` it says the trees too:

```text
> micro-expert --verbose --nlp
? is-uncle-of(bill, ?p)
  bill is uncle of anna  <- rule ?x is uncle of ?y <- ?p is parent of ?y, ?x is sibling of ?p, ?x has gender male
    george is parent of anna  <- fact
    bill is sibling of george  <- rule ?x is sibling of ?y <- ?p is parent of ?x, ?p is parent of ?y, not-equal(?x, ?y)
      walter is parent of bill  <- fact
      walter is parent of george  <- fact
    ...
  bill is uncle of anna
```

Facts and rule heads become sentences by the same dashes-to-spaces rule. A condition that is a
constraint rather than a goal, such as `not-equal(?x, ?y)`, stays as written, because it has no
sentence to be said in. The structure is unchanged: one line per step, indented by body level, and
each line names either a fact or a rule as its reason.

## Why keep the tree at all

The tree is the difference between "the system says so" and an answer you can check. If a result is
wrong, one of three things is true, and the tree shows which:

- a fact is wrong — a leaf says something you did not mean to assert;
- a rule is wrong — a branch names a rule whose body does not mean what you thought;
- a fact is missing — there is no branch that could have produced the answer.

The first two are visible in the tree. The third is the subject of the next chapter, where the
engine reports what it would have needed.

## Try it

Run each with `--verbose` and read the top and bottom of the tree before the middle.

1. `is-grandpa-of(?x, ?y)` — how does Walter's answer differ from Doris's in chapter 1? (The gender
   condition is the only difference, which is why one predicate covers grandpas and the other
   grandmas.)
2. `is-in-law-of(?x, ?y)` — find an answer whose derivation uses the `or(...)` rule, and note that
   only one alternative appears in the tree.
3. `is-only-child-of(tim, ?who)` — read the rule's `not(...)`, then look at the tree: the negation
   has no line of its own. It proves nothing and adds no step; it only removes branches, so the
   tree shows the parent fact and stops.

Next: [3. When there is no answer](03-when-there-is-no-answer.md).
