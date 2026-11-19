# To Know What You Don't Know

*This is the second article about [micro-expert](https://github.com/treytomes/micro-expert), a small backward-chaining expert system in MiniScript.  The [first article](https://github.com/treytomes/micro-expert/blob/main/docs/01-a-micro-expert-in-miniscript.md) built the engine: subject-predicate-object triples, eleven rules about one imaginary family, and a solver that answers a question only by handing back the proof that makes the answer true.  This one is about what the engine does when the answer is **no** - and why that "no" turns out to be the most useful thing it produces.  The worked example stays that same toy family, small enough to hold in your head; the idea it points at is the research frontier in the picture below.*

Let's say that you want to allow an AI to research a problem we don't have an answer for yet.  There are countless paths it could pursue.  How should it decide which way to go?  Which path has the highest value?

My theory is that the highest value path can be chosen by giving the model access to an expert system with an S-P-O graph.  The highest value next steps are to answer questions that link together sections of the graph that previously had no path between them, or to expand the frontier of the graph.

Some questions, like the problem of continual learning in AI, may not be provable right away, but expanding the graph of known facts will always have value.

![Two graphs: a chain of green facts from "neural network learns via gradient updates" through shared weights and catastrophic forgetting, mitigated by a replay buffer at the cost of memory growth, ending at a dashed "next fact" box; and a separate salmon island, "hippocampus replays in sleep", with a dashed "missing link - research target" box bridging to the replay buffer](assets/spo_graph_research_frontier_continual_learning.png)

## The expert can plug its own holes.

The interesting queries are the ones that fail; the times when backwards chaining comes back empty.  The answer isn't "yes" or "no", it's "this graph has a hole in it".  The useful answer in this case isn't the empty result set, it's the shape of the hole.

Our example model is small enough to hold in your head.  A fact is one ground S-P-O triple, `parent-of(susan, tim)`; put a `?p` in it and it becomes a question.  A rule is a head and a body:

```
uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
```

When the search fails, the same machinery runs backwards: one candidate for every path where the goal could still be proved, and each rule body walked left to right.  A condition the search can meet is crossed off, carrying a value forward only when every proof agrees on it - a report never picks one of two parents just to look concrete.  The conditions it can't meet are facts to add, in symbolic form, and a later one that those facts would settle is printed as a check instead:

```
Query: uncle-of(oliver, ?p)
  no solution found at depth 8
  A solution would need one of these:
    a fact like uncle-of(oliver, ?p)
    through rule uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
      parent-of(?p', ?p)
      sibling-of(oliver, ?p')  (checked once the facts above exist)
    (a name ending in ' is the rule's own variable, not one you asked about)
```

This is the case that matters for the picture above.  Every one of those conditions is separately provable - parent facts exist, Oliver has siblings, Oliver is male - and Oliver is still nobody's uncle: three conditions that each look satisfied prove nothing together.  That's why a body is judged as a body, and what comes back is the edge that is really missing: Oliver's siblings exist, but none of them has a child, so the fact to add is `parent-of(?p', ?p)` for one of those siblings.  Give one of them a child - `parent-of(clara, zed)` - and the query answers `uncle-of(oliver, zed)`.  The loop below walks exactly that: name the open sibling, and the one fact left to add is the child.

The REPL session picks an open topic to ask about, ranking according to what will allow the query to take the next step along the graph.  Asserting the answer teaches the graph exactly one instance and nothing else; in our example here we only learn about *one* of Oliver's nieces/nephews.

Here is that loop at the prompt from end to end - the report, the answers typed in at each prompt, and the query re-run against the one fact it gains:

```text
? uncle-of(oliver, ?p)
  no solution found at depth 8
  A solution would need one of these:
    a fact like uncle-of(oliver, ?p)
    through rule uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
      parent-of(?p', ?p)
      sibling-of(oliver, ?p')  (checked once the facts above exist)
    (a name ending in ' is the rule's own variable, not one you asked about)
  parent-of(?p', ?p)
  ?p' = clara
  parent-of(clara, ?p)  (not added: what is left is the question's own)
  no solution found at depth 8
  A solution would need one of these:
    a fact like uncle-of(oliver, ?p)
    through rule uncle-of(?x, ?y) <- parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male)
      parent-of(clara, ?p)
  parent-of(clara, ?p)
  ?p = zed
  added parent-of(clara, zed)
  uncle-of(oliver, zed)
```

Oliver begins as nobody's uncle; by the last line the one edge that was really missing - a child for Clara - sits in the graph where the report pointed, and the query that came back empty now answers.

That's the frontier to point a model at.  Each entry is cheap to check, and the answer goes exactly where the hole was - the graph gains an edge, the next report comes out different, and the loop runs again.  Continual learning, one missing fact at a time, which is why the report belongs in the engine rather than on the nice-to-have list.  It's also bounded by the same `--depth` as the search, so "missing" means missing at depth 8.

## The algorithm

The missing fact report is not a new algorithm; it is the search, run again with the answers thrown away.

`proveGoals` walks the rules whose heads meet the goal and returns the proofs it found.  `needsFor` walks the same rules, in the same order, from the same bindings, and where `proveGoals` would have recursed into a body it asks the same question of that body - except that a condition with no proof stops being a dead end and becomes a line of output.  Unification, standardization apart, the cycle guard and the depth counter are all the same code.  Stripped to the shape of the recursion, the two differ only in what they do with a derivation:

```
proveGoals                          needsFor
  for matched in matchingFacts        options = [a fact like the goal]  (if none matches)
    mergeAnswer(...)                  for candidate in matchingRules
  for candidate in matchingRules        for result in bodyResults
    for proved in proveConditions         if result.needs.len > 0
      mergeAnswer(...)                      options.push(result)
```

That is the whole idea, and it is why the feature was cheap: the hard parts - what a rule means, when two patterns meet, when a chain loops - were already solved once.

Walking a body is where the details are.  Conditions are taken left to right, carrying bindings, and each one lands in one of three states.  Proved, it is crossed off and its bindings go forward.  Unproved, it becomes a fact to add, printed in symbolic form with whatever the body has bound so far substituted in.  Or unproved *and* undecidable, because a fact asked for earlier in the same body would bind the variables it mentions.  There is no way to look that one up yet, and no honest way to say it needs a fact of its own either, so it prints as a check: `(checked once the facts above exist)`.  Two variables of bookkeeping, `newVars` for what the missing facts would bind and `coveredBy` for testing a condition against it, and the report stops asking for the same value twice.  A `not(...)` is a fourth state and the simplest: it is checked against the graph and never asked for, because nothing added can make an absence true - met, it disappears from the report, and failed, it rules that way through the rule out.

The next detail is the one I would defend hardest.  A condition can have several proofs, and the proofs can disagree: every child in this family has two parents, so `parent-of(?p, tim)` holds twice over, once with `?p` as Bill and once as Susan, and nothing about the question says which.  The report carries forward only the bindings *every* proof agrees on (`agreeingBinds`), so a line stays symbolic exactly as long as the graph fails to force a value.  It would have been easy - and wrong - to take the first proof and print `parent-of(bill, tim)` as the missing fact: the gap would look narrower than it is, and a reader would go looking for one particular fact when either would do.  Values that are settled do still show: the goal's own terms, anything the search pinned down, and anything the session has been told, which is substituted into the report before printing - the `clara` in the loop's second report above came from the session's answer, not from the search.

Then there is the case that made the report worth writing.  A body whose conditions are each provable on their own, but never all at once, gets walked leniently first: each condition is checked against the graph and crossed off, and at the end the body claims it needs nothing - while the search that prompted the report came back empty.  Rather than print a rule that needs nothing for a query that fails, the body is read a second time in a stricter mode (`reportOpen`): a condition whose proofs leave some variable open is reported as a fact to add instead of being crossed off.  That is the three-line block in the previous section, and it is the difference between "nothing is missing" and "nothing is missing individually".  A body has to be judged as a body.

What the report will not do is assert anything.  Each alternative is independent - the header says *one of these*, not all of them - and nothing is added to the graph by being printed; only the session, with a human at the prompt, turns an alternative into a fact.  It is also still goal-directed, in the same limited sense as the search: every rule is tried against the question, but only a rule whose head meets it has its body walked, and nothing else in the graph is visited.  So a hole in one branch costs the conditions between the question and the hole, not a tour of the knowledge base.  That is not the same as cheap: the head match and the fact scan still run over everything, at every level, exactly as they do when answering, so the report pays for the size of the graph the way a query does.  Depth bounds how tall that work gets, not how wide.

What we gain here is honesty rather than intelligence: the system can tell you where the graph has no edge, and it cannot tell you which edge is most worth exploring.  That judgement is the part we want a model for.

## Why MiniScript?

Why not C#?  I love C#.

The goal was to make the reasoning visible, and that decided everything else: the reasoner has to fit in one sitting's reading, it has to run on a machine with no toolchain, and the things you type - a triple, a rule, a query - have to be the same things the program stores and prints.  C# does all three.  It just does them with more scaffolding than reasoning: a solution, a project per library, a test project, a target framework, a build between me and the next experiment, and a `Term` hierarchy before the first rule is parsed.

MiniScript strips the scaffolding.  A module is a file you `import`; a class is a map with a constructor function; `new Var` builds one and `isa` asks what it is.  Unification - the match, the dereference, the binding - is forty-five lines, docstrings included.  The same forty-five lines in C# arrive as a base class, a subclass per kind of term, a visitor for substitution, and a switch that has to know about all of them.  None of that is difficult, and all of it is distance between the algorithm and the person reading it.

Then there is the loop I actually worked in.  `repl.ms` is 419 lines that take a fact, a rule or a query and keep a session, and the whole development cycle was: edit a function, run the interpreter, type a query, read the block.  No build, no watch mode, no debugger to restart.  The examples in this article are transcripts from that prompt rather than reconstructions, which is the only way I trust them.

The costs are real, and they are the price of a late-bound language.  A missing map key is a fatal `Key Not Found` rather than null, so `hasIndex` guards every lookup that might miss - you can see the habit in `deref`.  A module that imports another gets its own copy, class maps included, so `triples.ms` keeps every class together in one file; the header says why, in case I am tempted to split it.  There are no static types, so a renamed field is found by running a test, not by a compiler.  There is no package manager, so the CLI parser and the logger are submodules written in the same language, read the same way.  And the interpreter is slower than compiled code, which starts to matter the day the knowledge base is large.

What that cost buys you: 822 lines for the reasoner, about 1,750 for the program, and roughly 900 lines of tests that need no framework - a map with two counters, a `check` function, and the same interpreter that runs the app.  The runtime is one executable that `bootstrap` unzips into the repo, and every value in the system is a map entry or a list slot you can print: the derivation tree is maps and lists, so rendering it is a loop, and the session is a map you can inspect at the prompt while the query runs.  In C# I would have had to enforce those separations.  Here the shortest path was the honest one.
