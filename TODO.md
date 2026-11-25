* Generate a tokenizer and parser from the BNF.
* Need a syntax highlighter for the BNF grammar.
* Create submodule packages for the syntax highlighter, `repl` library, and BNF parser.

* Complete the set of operations, in the order worth building them:
    1. `equal` -- done: the boolean set is whole, and it is the first constraint that can
       bind, not just filter.
    2. `is-number`, `is-text` -- the type tests that finish the boolean set. They take one
       field, so the constraint call shape has to allow a unary call first; constraintOf
       enforces two fields today.
    3. `starts-with`, `ends-with`, `contains` -- text predicates, two fields, domain-gated by
       the schema so they stay off numeric fields.
    4. `add`, `subtract`, `multiply`, `divide` -- the operations that calculate to another
       type. They cannot filter, so they are binding goals with the value as a field:
       add(?a, ?b, ?sum), last field the output.
    5. what else? min, max, count -- decide once the binding-goal shape has been used enough
       to say whether a third field is the right call form.

* forward-chaining / RETE algorithm

* Need to begin building wiki-style documentation under `./docs`.  Use CI/CD to generate the GitHub wiki.

* ~~Use doc-strings in `vscode-miniscript`.  Also alt-click symbol linking?~~ -- done: hover
  shows a function's docstring (or the `//` comment above it), Ctrl-click goes to the
  definition, and the Outline lists the file's symbols.

# Later

* Spike: Bringing an Ollama embedding model into MiniScript.
* Spike: Bringing an Ollama chat model into MiniScript.
* Match predicate names based on some kind of similarity search, e.g. `has-sex` should match to `has-gender`.  Use the match if its confident, otherwise create a new fact.

# Much Later

* **Provenance where answers are read.** Value: high. The proof tree prints `fact` for every leaf
  (`src/triples.ms`, `reasonText`) while the whole staleness story hangs on which fact and which
  day, so `--verbose` hides the thing a reader needs. A tree line naming the service and day, and
  a plain `2 of 3 from services` under an answer, would show it. Effort: small-medium; the
  matched fact has to be carried into the reason.
* **An age ceiling for readings (`--max-age`).** Value: high, it finishes the staleness rule.
  Every earlier day is equally stale today, so yesterday's coordinate and a 2024 reading are both
  used once nothing can refresh them. Effort: small-medium; a day count on the session and a
  refusal in `staleFacts`/`askGoal` when nothing fresh can be had.
* **A lint test over the shipped declarations.** Value: medium-high, cheap insurance. Every
  `provides` entry should be askable: each `from` field has a request parameter, the reply can
  produce the declared fact, no entry collides with another, and the same predicate is not
  declared twice by one endpoint. Effort: small; one case in `test/providers.ms`.
* **Per-service switches and ordering.** Value: medium. `--offline` is all-or-nothing and registry
  order is the literal list in `src/main.ms` (and now in `src/notebook.ms`), which decides who is
  asked first now that a failure falls through. `--without geocode.maps.co`, or an order declared
  by the domain, makes priority a user decision. Effort: small.
* **Retry transient failures, and cap the calls.** Value: medium. One attempt per request is
  remembered for the whole run, so a single 429 or 5xx costs the question its answer, and
  `providerCalls` has no idea which failures are worth repeating. Effort: small-medium; a retry
  with a short backoff for retryable statuses, plus a per-run call budget.
* **Notebook parity: a `/providers` listing.** Value: medium. A notebook asks the maps only after
  a cell runs `/online` now, but nothing lists what a session could ask, what it has asked, or how
  old each reading is - `/facts` is the only way to see a `# source day`. Effort: medium; one
  command reading `session.providers` and `session.providerCalls`.
* **Persist attempts with the session.** Value: medium, a design decision worth arguing first.
  `providerCalls` lives in the session map and dies with the process, so `/save` then `/load`
  re-asks everything while `/undo` forgets a request only within the run. Effort: medium; a saved
  calls file beside the facts, with the same reload rules.
* **Moment-aware questions (`--as-of`).** Value: high, and the largest piece here. A forecast is
  fetched for the next hour whatever the question meant, so a fact carries two kinds of time - the
  hour it describes (`@`) and the day it was fetched - and nothing says which one a question wants.
  Effort: large; declarations that take a moment beside their coordinates, and a goal that names
  one.
* **A "declaring a service" page in the wiki.** Value: medium-high for anyone else. `provides` is
  described only inside the three `docs/api` pages, and wiki step 05 is about domains, so the
  pattern - map, `provides`, request fields, reply reading - has no guide of its own. Effort:
  small; one page, with a local service as the worked example.
