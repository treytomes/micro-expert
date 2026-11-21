* A domain is composed of the combination of schema, rules, and facts.
* Add to CLI: load individual components of a domain by file, or an entire domain by folder, or keep the default paths.
* /save {"filename{.kb}"}

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

* Use doc-strings in `vscode-miniscript`.  Also alt-click symbol linking?

# Later

* Spike: Bringing an Ollama embedding model into MiniScript.
* Spike: Bringing an Ollama chat model into MiniScript.
* Match predicate names based on some kind of similarity search, e.g. `has-sex` should match to `has-gender`.  Use the match if its confident, otherwise create a new fact.
