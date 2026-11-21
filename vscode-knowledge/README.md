# Micro-Expert Knowledge for Visual Studio Code

Syntax highlighting for the `.kb` files the expert system reasons over: the family's
facts and rules in `data/facts.kb` and `data/rules.kb`.

## What you get

- A TextMate grammar (scope `source.micro-expert-kb`) registered for `.kb` files.
- Comment lines, the rule arrow `=>`, constraints (`not-equal`), variables (`?x`), predicate
  names, numbers, the schema's field types (`number`, `text`, `boolean`, `date`, `time`,
  `datetime`), and the `and(...)` / `or(...)` / `not(...)` groupings each read in their own
  way.
- A language configuration: `//` toggles comments, parentheses match and auto-close.

## Try it

Open this folder in VS Code and press `F5`. The checked-in `.vscode/launch.json` starts an
Extension Development Host on the repo root, with this folder as the development
extension; open `data/rules.kb` there to see it highlighted.

## Package it

From the repo root, `build-kb-ext.bat` (or `build-kb-ext.sh` on Linux) packages this
folder with `vsce` and writes `out/micro-expert-knowledge.vsix`; install it with
`code --install-extension vscode-knowledge/out/micro-expert-knowledge.vsix`.
`.vscodeignore` keeps the development files out of the package.

## License

MIT — see [LICENSE](LICENSE). Copyright © 2026 Trey Tomes.
