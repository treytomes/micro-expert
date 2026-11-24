// The `.kbnb` file itself: JSON a list of cells, read back as cells and written out as
// JSON. No `vscode` here, so what the file holds can be pinned on its own.

const { test } = require("node:test");
const assert = require("node:assert/strict");

const { readNotebook, writeNotebook } = require("../kbnb-file");

test("a notebook file is its cells, in order and as themselves", () => {
	const bytes = writeNotebook([
		{ kind: "code", language: "micro-expert-kb", source: "is-parent-of(?p, susan)" },
		{ kind: "markdown", language: "markdown", source: "# The family" },
		{ kind: "code", language: "micro-expert-kb", source: "is-parent-of(walter, susan)" },
	]);

	const file = readNotebook(bytes);
	assert.equal(file.version, 1);
	assert.equal(file.cells.length, 3);
	assert.deepEqual(file.cells[0], {
		kind: "code",
		language: "micro-expert-kb",
		source: "is-parent-of(?p, susan)",
	});
	assert.equal(file.cells[1].kind, "markdown");
	assert.equal(file.cells[2].source, "is-parent-of(walter, susan)");
});

test("a cell's source may be the lines of it, as VS Code writes it", () => {
	const file = readNotebook(
		Buffer.from(JSON.stringify({ version: 1, cells: [{ cell_type: "code", source: ["a\n", "b\n"] }] }))
	);
	assert.equal(file.cells[0].source, "a\nb\n");
	assert.equal(file.cells[0].language, "micro-expert-kb");
});

test("an empty file is one empty cell, and a file that is not one says so", () => {
	assert.deepEqual(readNotebook(Buffer.from("   \n")).cells, [
		{ kind: "code", language: "micro-expert-kb", source: "" },
	]);
	assert.throws(() => readNotebook(Buffer.from("{ not json")), /Not a Micro-Expert notebook/);
	assert.throws(() => readNotebook(Buffer.from("{}")), /no cells/);
});
