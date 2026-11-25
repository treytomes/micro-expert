# 7. The notebook in VS Code

micro-expert can serve the engine to a notebook. A `.kbnb` file is a column of cells, each run
against `src/notebook.ms` with the same facts, rules and questions a prompt takes. The cells share
one session, so what one cell learns the next one holds, and nothing is written to disk: `data/` is
exactly as it was when the session started.

## Install it

```text
./build-kb-ext.sh
code --install-extension vscode-knowledge/out/micro-expert-knowledge.vsix
```

`build-kb-ext.sh` packages `vscode-knowledge/` with `vsce` (or `npx @vscode/vsce`) into
`vscode-knowledge/out/micro-expert-knowledge.vsix`, which is git-ignored. To work on the extension
instead of installing it, open the repository in VS Code and press `F5`.

A cell's question may also be answered by a remote service, as a line at the prompt is - but only
once a cell asks for it. A notebook is opened to read and to write, so nothing goes out because a
cell was run: a cell of `/online` attaches the registry the service maps declare, and until then a
question the facts cannot answer asks the box under the cell, exactly as a notebook with no
services does. After it, a question the facts cannot answer is asked of `ipwho.is`,
`geocode.maps.co` or Open-Meteo, and a fact one of them answers carries
`# <service>/<endpoint> <day>` into the cell. Start the engine with `--offline` and `/online`
refuses rather than attaching anything. A service that needs a key reads it from the `.env` beside
the run - `GEOCODE_MAPS_API_KEY` for `geocode.maps.co` - and a run without it says which variable
is missing rather than sending the call. The search takes the first result `limit=1` offers, so its
map also refuses a reply whose own city or country is not the place's: the other map is asked, and
the cell shows that warning and the answer it did reach rather than a forecast for a namesake. The
map it falls through to checks its own first result the same way - against the name the reply gives
the place and its country - so a geocoder that finds the wrong town on either side leaves the value
asked for in the box under the cell. "The same name" is the same words rather than the same
letters: `Washington, D.C.` is confirmed by a reply that says `Washington`, `New York` by `City of
New York`, and `St. Louis` by `Saint Louis`, while another town's name is still another town's.
A result with no city in its address is judged by the name it is called, so `Sao Paulo` - which
comes back with coordinates and no city - is confirmed rather than taken unchecked.

`examples/explore.kbnb` is the tour: a rule's answer, a question that needs a value, the fact that
answer added, a rule typed in a cell, one question read as a proof tree and as a sentence by
`/verbose` and `/nlp` and then back as the fact it is, and `/mermaid`. `examples/providers.kbnb` is the services
one: ipwho.is locating the session, `geocode.maps.co` locating a place by name and reading back an
address from its coordinates, and Open-Meteo forecasting for it.

## Running a cell

`Shift+Enter` runs the cell under the cursor. A cell is any number of lines, run in order:

```text
is-parent-of(casey, sam)
is-parent-of(drew, casey)
is-parent-of(?p, sam)
```

A line is a line of the prompt: a fact, a rule as `head => conditions`, a question, or a command
starting with `/`. `/exit` is refused — the session belongs to the notebook, not to a cell — and
`Restart Knowledge Session` in the toolbar is what starts a fresh one. A cell of just `/mermaid`
prints the diagram as a fence and draws the picture beside it.

A notebook has no `--verbose` or `--nlp` flag to start with, so the two commands are how it asks for
them: a cell of `/verbose` puts the proof tree before each answer from then on, a cell of `/nlp`
says the answers - and those trees - as sentences, and running either one again turns it off. The
switch belongs to the session rather than to the cell that set it, so every cell after it reads
answers the new way.

A cell with a line the engine refuses is marked failed, and the session carries on into the cell
after it. What was refused is in the cell's own text.

A cell reads its lines the way a `.kb` file does, so `//` starts a comment: a note beside a fact is
a note, a line that is only a note is skipped, and neither marks the cell failed.

One cell runs at a time. Every cell of a notebook goes to the same process and reads its answer off
the same pipe, so a cell started while another is running waits its turn instead of taking the
running cell's text for its own — VS Code shows it queued behind the one executing. Stopping a cell
that is still queued ends it without running.

## The protocol

The extension starts one `src/notebook.ms` per notebook and talks to it over stdin and stdout, one
cell at a time. Every line either end writes is ordinary text; the markers are what say which block
a line belongs to.

| Marker | Written by | Means |
| --- | --- | --- |
| `<<kbnb:cell>>` … `<<kbnb:end>>` | extension | one cell's source |
| `<<kbnb:out>>` … `<<kbnb:end-out>>` | engine | the cell's text, the report and the answers in it |
| `<<kbnb:failed>>` | engine | a line of this cell said a warning |
| `<<kbnb:draw:MIME>>` … `<<kbnb:end-draw>>` | engine | a picture, and the type to draw it as |
| `<<kbnb:ask:N>>` … `<<kbnb:end-ask>>` | engine | a question waiting for a value, numbered per session |
| `<<kbnb:answer:N>> VALUE` | extension | the value for question N |
| `<<kbnb:decline:N>>` | extension | no value for question N |
| `<<kbnb:done>>` | engine | the cell is over |

A cell's answer comes in that order: the output, the failed mark if a line was refused, any picture
drawn, then `<<kbnb:done>>`. The ask is written inside the output, where the prompt happened, and
the engine holds the cell open at it, so nothing else is read or written until it is answered.

Both answer lines name the ask they belong to. The number counts the asks of one session, so an
answer meant for a question that is gone is passed over instead of becoming the value of the one
now waiting.

## The ask box

When a question needs a fact before it can go on, the prompt's own ask-for-a-value loop runs inside
the cell, and the notebook draws the question where it happened:

```text
?p' = [__________]  Answer  Skip
the parent of ?p, needed to answer is-uncle-of(oliver, ?p)
```

The report above the box is the cell's text: no solution at this depth, the fact that would answer
it, and the rule it would need. The line inside the box says the same thing in one sentence, so the
question still explains itself after the report has scrolled away. What a value there stands for is
read from the predicate's own name: in `is-parent-of(?p', ?p)` the first field is "the parent of
?p" and the second "the one ?p' is the parent of", while a name of another shape is said as the
fact's own sentence. When the fact is a rule's, the question it serves is named after it — that is
where `needed to answer is-uncle-of(oliver, ?p)` comes from, and why the label is `?p'`: a name
ending in `'` is the rule's variable, not the one you asked about.

**Answer** sends what you typed and the cell goes on: the fact is added, the search runs again, and
the proof is printed under the report. **Skip** sends the decline; the cell ends saying the
question needs a value, is marked failed, and the session stands for the next cell. Closing the
notebook, stopping the cell, or restarting the session answers every box the same way, so no cell is
left waiting for a value that can no longer come.

## Settings

| Setting | Default | What it is |
| --- | --- | --- |
| `microExpert.projectDir` | empty | The micro-expert folder the cells run in, absolute or relative to the workspace folder. Empty uses the workspace folder the notebook is in, then the notebook's own folder. |
| `microExpert.domain` | `data` | The domain folder served: the `--domain` a run would pass. |
| `microExpert.interpreterPath` | empty | The MiniScript interpreter that runs `src/notebook.ms`. Empty reads `MINISCRIPT_EXE_PATH` from the project's `.env`, then takes the interpreter on `PATH`. |

A session holds the interpreter, folder and domain it started with, so changing one of them starts
the next cell's session afresh and the cells before it lose the facts they added.

## The file

A `.kbnb` is JSON: a version and a list of cells, each with its kind, language and source.

```json
{
	"version": 1,
	"cells": [
		{ "kind": "markdown", "language": "markdown", "source": "# The family" },
		{ "kind": "code", "language": "micro-expert-kb", "source": "is-parent-of(?p, tim)" }
	]
}
```

It is the shape the MiniScript 2 extension's `.msnb` notebooks use, so either extension can open the
other's file. Outputs are not saved: running a cell again is how its answer comes back.
