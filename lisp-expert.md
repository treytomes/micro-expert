# What `~/projects/lisp-expert` does about time and confidence

A review of the sibling project (`~/projects/lisp-expert`, Cog-Lisp on Pharo) for the
question this project is stuck on: **how do you keep a fact that is only true for an
hour, or only 80% believed, in a store that only has room for subject, predicate and
object?** Reviewed 2026-11-22 at the working tree (last commit 2026-11-16).

Short answer: they do not put time or confidence in the fact at all. The triple stays
exactly three terms, and time and certainty live in **hash tables keyed by the triple**.
Time is never read from a clock inside the engine — it is a parameter threaded in from
the edge. The two lessons that matter most for us are at the end: the interval design
solves our staleness problem for free, and it requires a fact identity we do not
currently have.

---

## 1. The shape of the thing

| Piece | Where |
| --- | --- |
| Facts, CFs, intervals, recency, working memory | `expert/knowledge-base.lisp` (553 lines) |
| Rules, unification, `defrule` validation | `expert/inference-core.lisp` (507) |
| Backward querying, `*current-time*`, `valid?`/`at` | `expert/backward-chaining.lisp` (626) |
| Forward chaining, Rete, truth maintenance, derived windows | `expert/forward-chaining.lisp` (716) |
| Save/load of facts + CFs + intervals + recency | `expert/persistence.lisp` |
| Tables that *show* CF and the window | `expert/views.lisp` |
| Open-Meteo → facts, the closest prior art to us | `weather/model.lisp`, `weather/load.lisp`, `weather/rules.lisp` |
| A clock, outside the engine | `system/src/clock.lisp` |

Both inference directions share one fact store; queries see derived facts as well as
base ones.

## 2. The representation: one triple, four side tables

```lisp
(define *spo-kb* '())                    ; the base facts, newest first
(define *cf-kb* (make-hash-table))       ; triple -> current CF in [-1, 1]
(define *base-cf-kb* (make-hash-table))  ; triple -> CF it was asserted with
(define *temporal-kb* (make-hash-table)) ; triple -> list of (start . end) intervals
(define *recency-kb* (make-hash-table))  ; triple -> when it was asserted
(define *derived-intervals* (make-hash-table)) ; triple -> when a derived fact holds
```

Four things are worth copying from this alone:

1. **The triple is untouched.** `has-temperature` still takes two fields. Every
   `has-temperature(berlin@2026-11-22T00:00, 2.5)` we have been agonising about is
   `(berlin temperature_2m 2.5)` plus one entry in `*temporal-kb*`. No `@`, no opaque
   term, no pointer facts, no `has-instant` duplication.
2. **Validity and recency are separate.** `*temporal-kb*` says *when the fact is true*;
   `*recency-kb*` says *when it was asserted or its CF changed*. Their comment is
   explicit: "Recency is independent of temporal validity." We conflated these in the
   `has-fetched-at` / `has-resolved-instant` sketch; two questions, two columns.
3. **A triple may hold in many intervals.** `assert-temporal` on the same triple again
   appends an interval rather than replacing it:

   ```lisp
   ;; "Another call adds another interval to the same triple."
   (%add-interval! triple (cons start end))
   ```

   So `0–1 °C` and then `2–3 °C` at 02:00 is two intervals on one triple. A day's hourly
   series is *one fact repeated 24 times with 24 windows* — not 24 subjects. Compare our
   `session.ms`, where `alreadyKnown` dedups by `triple.text`, which would silently
   collapse those two hours into one.
4. **Base CF and derived CF are separate tables.** `*cf-kb*` is reset to a *copy* of
   `*base-cf-kb*`, "so a derived CF never changes a base one" — the same discipline as
   keeping working memory apart from the knowledge base.

And the display treats both as first-class: `views.lisp`'s facts table has columns
*Subject, Predicate, Object, CF, Holds, Kind*. If it is in the model, it is on screen.

## 3. Time is a parameter, never a clock read

```lisp
;; expert/backward-chaining.lisp:21
;; The time queries are evaluated at (#f: always): a parameter, so with-time
;; gives it back however its thunk is left.
(define *current-time* (make-parameter #f))

(define (eval-query-at pattern env time) ...)
(define (query-as-of time pattern) ...)
(define (with-time time thunk) (parameterize ((*current-time* time)) (thunk)))
```

There is **no wall-clock read anywhere that produces a fact's time.** `system/src/clock.lisp`
exists and exports `now-seconds`, and it is required only by `logging/` — for log
timestamps and rotated file names. The only clock in the engine's own domain is a
*monotonic* one, `weather/transport.lisp:151`, used to wait between retries; it never
reaches a fact. The weather REPL never asks what time it is.

`#f` means *always*, and `%valid-when?` short-circuits on it:

```lisp
(define (%valid-when? triple time)
  (or (not time) (apply valid-at? (append triple (list time)))))
```

This gives two query modes and they mean genuinely different things:

| Call | Meaning |
| --- | --- |
| `(eval-query '(berlin temperature_2m ?t) '())` | **every hour loaded** — "an hour of the forecast" |
| `(eval-query-at '(berlin temperature_2m ?t) '() 1762653600)` | **only the hour containing that second** — "then" |

`weather/rules.lisp` documents exactly this, and the offline example uses it:

```lisp
;; over the whole forecast (an hour below freezing exists)
(show-query '(oslo has-freezing-hours yes))
;; and as of 02:30 (2.0 degrees then)
(with-time (at-half-past 2) (lambda () (show-query '(oslo has-freezing-hours yes))))
```

`at-half-past` computes its own second in Lisp: `(+ 1794182400 (* hour 3600) 1800)`.
**That is the answer to our "in 3 hours" question, and it is not an answer the engine
gives.** They never solved horizon arithmetic inside the KB either; the caller does it
and passes an absolute second. Their `at` goal takes the time *as a term*:

```lisp
(at 15 (a p ?x))          ; the `at` goal: evaluate a goal as of a second
(valid? a p b 15)         ; the `valid?` goal: is this fact true then
```

So the micro-expert equivalent of "what will it be in 3 hours" is a client-side
`session.now + 10800`, not a `{now+3h}` token and not a horizon label. The horizon label
is still the better *human* interface, but it is a writer/nlu decision, not something
the inference engine can express.

## 4. Intervals: three rules, each learned the hard way

**Half-open, `[start, end)`.** `TODO.md` records the bug: `valid-at?` counted the end as
inside, so at exactly 13:00 a query saw both the 12:00 and the 13:00 temperature.

```lisp
(define (%interval-contains? iv time)
  (and (or (not (car iv)) (>= time (car iv)))
       (or (not (cdr iv)) (< time (cdr iv)))))
```

The test states the invariant directly: at `7200` only the `[7200,10800)` fact holds;
at `7199` only `[3600,7200)`. `#f` at either end is unbounded; `(cons 0 #f)` is
"always".

**A derived fact holds while its supports all do.** `firing-intervals` takes the
intersection of the supports' intervals; when they never meet (a count over a day, a rule
comparing two hours) it takes their *span*; when no support is timed, it holds always.
`derived-intervals` unions the firings' windows and joins back-to-back intervals.

This closed a real bug (2026-11-13): before it, `run-inference` derived
`(oslo has-freezing-hours yes)` from one hour and the fact held *forever*, so
`(with-time <02:30>)` answered yes though it was 2 °C then. The fix is why
`weather/examples/offline.lisp` asks before inference and again after: the two answers
differ, and that difference is now correct.

**Merging is explicit.** `merge-intervals` joins `[0,1)` and `[1,2)` into `[0,2)`, so
the window of a derived fact does not grow a seam per hour.

## 5. Certainty factors

The full EMYCIN-ish algebra, on both facts and rules:

| Operation | Rule |
| --- | --- |
| Conjunction | `min` of the premises' CFs |
| Disjunction | `max` |
| Rule firing | `cf(rule) * cf(premise)` |
| Two derivations of one fact | `combine-cf` (consensus) |
| Query, believed? | `cf >= *cf-threshold*` (default `0.2`) |
| Negation | absent, or explicitly negative with `cf <= -threshold` |
| Aggregate (`count`/`sum`) | minimum CF across matches, `1` when none |

`combine-cf` is worth seeing because it handles the mixed case rather than averaging:

```lisp
(cond ((both non-negative) (+ cf1 (* cf2 (- 1 cf1))))
      ((both non-positive) (+ cf1 (* cf2 (+ 1 cf1))))
      (else (let ((d (- 1 (min (abs cf1) (abs cf2)))))
              (if (= d 0) 0.0 (/ (+ cf1 cf2) d)))))   ; 1.0 and -1.0 cancel to 0.0
```

Two behaviours we should note as *unavailable* to us:

- **The threshold is a third truth value, deliberately.** A fact at CF 0.1 answers
  neither `(bird can-fly yes)` nor `(not (bird can-fly yes))` — both return `()`. There
  is a test named exactly that. This is the cleanest treatment I have seen of
  "unknown vs. false", and it is *not* negation as failure: an intermediate value is
  inconclusive rather than absent.
- **A negative CF is explicit negation, not absence.** `:cf -0.8` on a rule makes the
  conclusion's `(not ...)` succeed with CF 0.8. That is the one thing our engine's
  `not` can never say — `docs/api/gaps.md` calls it out, and this is the mechanism that
  closes it, at the price of a numeric layer we do not have.

## 6. Persistence: the record and its validation

```lisp
(cog-lisp-kb version (facts records) (rules rules) (assertion-clock n))
;; a fact record is
(triple cf interval recency)
```

`load-kb` checks every record before it replaces anything: CF a real in `[-1,1]`,
interval `#f` or `(start end)` with numbers or `#f` in order, recency an integer no later
than the saved clock, rules validated by `defrule`'s own validator. Then it replaces.

One limitation to know about before copying: `persistence-interval-for` saves only
`(car ivs)` — **the first interval**. A fact with several windows round-trips as one.
The TODO does not mention it. If we ever write intervals to disk, save the list.

## 7. The weather integration — our problem, already built

This is the part worth reading line by line. A record is
`(subject predicate object start end)`:

```lisp
;; weather/model.lisp
;; "A record is (subject predicate object start end): a fact, with the hour it
;;  holds for, start and end in Unix seconds, or #f #f for always."

(define (%hour-record loc predicate value start)
  (list loc predicate value start (+ start 3600)))
```

So a Berlin forecast becomes:

```lisp
(berlin temperature_2m 2.5 1762650000 1762653600)   ; the hour from 01:00
(berlin temperature_2m 2.5 1762660800 1762664400)   ; and the hour from 04:00
(berlin latitude 52.52 #f #f)                        ; holds always
```

and `assert-record!` turns each into `assert-temporal` (or `assert-spo` when the start is
`#f`). Note the encoding decisions:

- **Place is the subject, variable is the predicate, value is the object, hour is
  metadata.** `temperature_2m` stays a predicate name with the height inside it — the
  same compromise our `has-temperature-2m` makes, and they live with it.
- **`place-location` normalises a name to a symbol**: `"New York"` → `new-york`. Text
  keys are made once, by the writer, never joined on by rules.
- **Nulls are counted, not asserted**: `(%variable-records ...)` returns
  `(records . skipped)`, and the reload report carries `skipped`. Our `gaps.md` asks for
  `has-unavailable`; they chose a count in the report instead of a fact, which is weaker
  (no rule can ask "was snowfall unavailable?") but honest.
- **Reload is by provenance, not by pattern.** `weather/load.lisp` remembers the records
  each `(loc, source)` last inserted, so reloading a forecast takes back exactly those —
  not a user's `(berlin going-out yes)`, and not the air-quality load. A triple another
  source also gave stays. That is the "one folder per fetch" idea from `gaps.md` §5,
  implemented at fact granularity in a hash table instead.
- **Conflicts are detected, not overwritten.** `%conflicts?` asks whether the KB already
  holds a different value for the same subject, predicate and *hour* (evaluating the old
  fact at the new record's start, since intervals are half-open). Those stay and are
  reported. Compare our `unique(...)` on `has-temperature`, which would silently replace.
  Their design says: a refresh updates its own load; anything else that disagrees is
  reported, not erased.

The rules over it are ordinary, and only work because `<` exists:

```lisp
((?loc has-freezing-hours yes) (?loc temperature_2m ?t) (< ?t 0))
((?loc needs-a-coat yes)       (?loc temperature_2m ?t) (< ?t 10) (?loc going-out yes))
```

## 8. What this design costs

From their own TODO, so we can price it honestly:

- **Time invalidates every cache.** The memo key is `(pattern env time)`, and Rete alpha
  memories store `(%alpha-time memory)` and rebuild when it differs
  (`forward-chaining.lisp:172–189`). A session that alternates `now` and `tomorrow` pays
  a rebuild per switch.
- **No cross-hour comparison in rules.** `specs/02-comparisons.md` §3 puts "colder
  tonight than now" out of scope: "a rule that compares a value from one pattern against
  another hour's cannot be written."
- **Backward joins over a day's hours are pathological.** `(?l t ?a) (?l t ?b) (?l t ?c)`
  takes 0.8 s over 8 facts, 36 s over 16, 508 s over 24. Still open. Any design that
  makes every hour a distinct binding pays this on micro-expert too, whose solver is
  simpler.
- **A built-in that looks like a fact fails silently.** Before `<` existed,
  `(< ?t 0)` parsed as a fact whose *subject* is `<` and matched nothing, forever, with
  no error. Our grammar already reserves seven names inside rule bodies; that reservation
  is the only thing standing between us and the same bug.
- **`#f` means "all of time", which is a footgun.** `(eval-query ...)` with no time
  answers "some hour of the loaded forecast", not "now". It is right for their REPL,
  where the user says `at 02:30`, and wrong as a default for anything that reads like a
  question about the present.

## 9. Lessons for this project

**Take the representation, not the implementation.** The idea is one sentence: *a fact's
time and confidence belong beside the triple, keyed by it, not inside its terms.* That
kills the whole `place@instant` line of reasoning from the last few days — no composite
subject, no `has-instant`, no `has-current-reading` pointer, no horizon labels, because
the query names the instant and the store answers whether the fact holds then.

The obstacle is ours, not theirs. `*temporal-kb*` is a hash table keyed on a Lisp list,
so a triple has an identity independent of its text. Our `.kb` grammar has exactly two
fields (`docs/wiki/kb-grammar.md`), `session.facts` is an array of `SpoTriple`, and
`alreadyKnown` compares `triple.text`. So "a side table" has to become one of:

1. **A fourth field in the grammar** — `has-temperature(berlin, 2.5, 1762650000)`.
   Cheap to parse, but it breaks "one fact is one triple", the schema's two-type list,
   `SpoTriple.parse`, every rule head, and the sentence rendering ("berlin has
   temperature 2.5 1762650000"). It also makes the hour a *term* again, which is what we
   were trying to avoid.
2. **A second file beside the facts** — `facts.kb` plus `when.kb`, lines keyed by the
   fact's text. Honest, no grammar change, but the key is the text, so a fact cannot
   repeat with two windows; the series case dies.
3. **The hour in the subject** — what we have been circling: `berlin@1762650000 2.5`.
   Works today, pays the pointer tax, and `unique(number)` behaves correctly per hour.

Of these, (3) is the only one that fits the current grammar and storage, and this review
does not change that. What it does change is the *semantics* we should copy into it:

- **Half-open windows, always.** `[start, end)` with `end` exclusive. If we ever add a
  time check, this is the one thing to get right first; they shipped the inclusive-end
  bug and had to fix it.
- **`now` is a parameter, not a token.** Our clock-hook plan substitutes `{now}` before
  parsing, which is fine as a *convenience*, but the engine should take the instant as an
  argument the way `eval-query-at` does. A substituted literal is indistinguishable from
  a value the user typed, which is exactly what makes answers unreproducible.
- **`#f`/absent time must mean "any time", and the prompt must say so.** Otherwise
  "what's the temperature" silently answers over the whole forecast.
- **Staleness falls out of the window.** A `current=` reading's window is 15 minutes; an
  hourly `temperature_2m` is 3600 seconds. A fact that no longer holds simply does not
  match, so no `has-fetched-at` comparison, no `years-since` hack, and negation stops
  being timing-dependent — the problem I raised against `has-temperature(dallas, 50)`
  dissolves without a rule.
- **A reload owns what it inserted.** Provenance as a remembered record list per
  `(place, source)` is a better answer than `unique(...)`: refresh corrects its own load,
  and a genuine disagreement from elsewhere is reported rather than erased.
- **Don't build the CF layer.** We have no arithmetic in bodies, no numeric parameter,
  and `unique(...)` refused on derived predicates; EMYCIN's algebra would be a second
  engine. The one piece worth stealing is the *three-valued* outcome — threshold as
  "inconclusive" rather than "false" — and that is a schema/prompt decision we can make
  without numbers if we ever want it.

## 10. What not to bring over

- The certainty-factor subsystem, `combine-cf`, salience/specificity/recency agenda
  ordering, the Rete network and its delta propagation. They are a CLIPS-shaped engine;
  we are an exact-match triple store, and their own TODO shows the Rete work is the
  expensive part.
- OAV frames and the OAV↔SPO bridge. Not a need we have.
- Pharo, `parameterize`, hash tables keyed on lists. The *concept* transfers; the
  mechanism does not.
- `#f`-as-always as a default query mode. Good for a REPL that says `at 02:30`; bad as
  a default for a question that reads like "now".

## 11. Where to read it

| File | Lines | What |
| --- | --- | --- |
| `expert/knowledge-base.lisp` | 134–161 | the side tables and their comments |
| | 163–182 | `combine-cf` |
| | 339–400 | `holds-intervals`, `valid-at?`, `assert-temporal` |
| `expert/backward-chaining.lisp` | 21–45 | `*current-time*`, `eval-query-at`, `with-time` |
| | 174–183 | `%time-of`, `%valid-when?` |
| | 520–537 | the `valid?` and `at` goals |
| `expert/forward-chaining.lisp` | 455–536 | interval intersection, hull, `merge-intervals`, `derived-intervals` |
| | 118–136 | `%holds-now?`, alpha-memory belief test |
| `expert/persistence.lisp` | 1–34, 88–96 | record shape and validation |
| `weather/model.lisp` | 13–90 | the record shape, `forecast->records`, `assert-record!` |
| `weather/load.lisp` | whole file | provenance, reload, conflict report |
| `weather/rules.lisp` | 1–25 | the no-time/with-time note and the three rules |
| `expert/test/test-temporal.lisp` | whole file | the interval semantics as executable specification |
| `expert/test/test-forward-chaining.lisp` | 418–505 | derived windows, retraction, span |
| `specs/02-comparisons.md` | §1, §3 | the silent `<` bug, and what stays out of scope |
| `TODO-WEATHER.md` | stage 1 | their own API-integration findings |
