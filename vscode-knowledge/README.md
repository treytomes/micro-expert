# Micro-Expert Knowledge for Visual Studio Code

Syntax highlighting for the `.kb` files the expert system reasons over: the family's
facts and rules in `data/facts.kb` and `data/rules.kb`. And a `.kbnb` notebook: cells of
knowledge, answered by the engine, with a question that needs a value asking for it in the
cell that needs it.

## What you get

- A TextMate grammar (scope `source.micro-expert-kb`) registered for `.kb` files.
- Comment lines, the rule arrow `=>`, constraints (`not-equal`), variables (`?x`), predicate
  names, numbers, the schema's field types (`number`, `text`, `boolean`, `date`, `time`,
  `datetime`) and its `unique(...)` wrapper, and the `and(...)` / `or(...)` / `not(...)`
  groupings each read in their own way.
- A language configuration: `//` toggles comments, parentheses match and auto-close.

## Notebooks

Open a `.kbnb` file, or **New Micro-Expert Notebook**, and each code cell is sent to one
`src/notebook.ms` of the micro-expert project, whose session the cells share: a fact one
cell adds is there for the next, and a rule one cell adds is used by the cell after it.
Nothing is written to disk, so the project's domain files are unchanged by a run; the
session starts from them again when it is restarted.

A cell that asks a question the knowledge cannot answer asks for a value, as the prompt
does: the cell's text up to that point is drawn as it arrives - the report of what would
answer the question - and the prompt it is waiting at (`?p = `) is drawn as a box under it,
with a line saying what a value there stands for (`the parent of ?p, needed to answer
is-uncle-of(oliver, ?p)`) so the box still explains itself once the report has scrolled
away. The answer - or Skip, which leaves the question without a value - goes back to the
engine and the cell finishes. A cell that says a warning is marked failed; its own text
says what was refused. A `//` note is a comment, as in a `.kb` file. Cells run one at a time,
each waiting for the one before it, since they share the one session.

- **Restart Knowledge Session** in the notebook toolbar starts a fresh session.
- **Stop** kills the session, so the facts added since it started are gone.

Settings, in `microExpert`:

- `projectDir` - the micro-expert folder the cells run in. Empty uses the workspace folder
the notebook is in, so a `.kbnb` opened inside a checkout needs nothing set.
- `domain` - the domain folder to serve, `data` by default.
- `interpreterPath` - the MiniScript interpreter. Empty reads `MINISCRIPT_EXE_PATH` from
the project's `.env`, and then takes `miniscript` from `PATH`.

## Try it

Open this folder in VS Code and press `F5`. The checked-in `.vscode/launch.json` starts an
Extension Development Host on the repo root, with this folder as the development
extension; open `data/rules.kb` there to see it highlighted.

## Tests

From this folder, `node --test` runs the notebook's file format, the session protocol
against the real engine (it needs `MINISCRIPT_EXE_PATH` in the repo's `.env`, or the
interpreter in `3rd-party/`), and the controller against a fake `vscode`: that a save goes
through the file's writer, that a notebook's runs queue behind each other, and that a
question is drawn as a box until it is answered or declined.

## Package it

From the repo root, `build-kb-ext.bat` (or `build-kb-ext.sh` on Linux) packages this
folder with `vsce` and writes `out/micro-expert-knowledge.vsix`; install it with
`code --install-extension vscode-knowledge/out/micro-expert-knowledge.vsix`.
`.vscodeignore` keeps the development files out of the package.

## License

MIT — see [LICENSE](LICENSE). Copyright © 2026 Trey Tomes.
