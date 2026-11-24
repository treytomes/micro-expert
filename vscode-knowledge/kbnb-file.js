// kbnb-file.js — a `.kbnb` notebook as it sits in the file: JSON, one entry per cell.
//
// The shape is the `.msnb` one - a version and a list of cells, each a kind, a language and
// its source - so either extension could read the other's file. A cell's kind is what tells
// the two apart here: a code cell is knowledge, read by the engine, and a markdown cell is
// the explanation between them.

const LANGUAGE = "micro-expert-kb";

function emptyCell() {
	return { kind: "code", language: LANGUAGE, source: "" };
}

function readNotebook(bytes) {
	const text = Buffer.from(bytes).toString("utf8").trim();
	if (!text) return { version: 1, cells: [emptyCell()] };

	let raw;
	try {
		raw = JSON.parse(text);
	} catch (error) {
		throw new Error(`Not a Micro-Expert notebook: ${error.message}`);
	}
	if (!raw || !Array.isArray(raw.cells)) {
		throw new Error("Not a Micro-Expert notebook: it has no cells.");
	}

	const cells = raw.cells.map((cell) => {
		const source = Array.isArray(cell && cell.source)
			? cell.source.join("")
			: String((cell && cell.source) || "");
		const markdown = cell && (cell.kind === "markdown" || cell.cell_type === "markdown");
		return {
			kind: markdown ? "markdown" : "code",
			language: markdown ? "markdown" : LANGUAGE,
			source,
		};
	});
	if (!cells.length) cells.push(emptyCell());
	return { version: 1, cells };
}

function writeNotebook(cells) {
	const raw = cells.map((cell) => ({
		kind: cell.kind === "markdown" ? "markdown" : "code",
		language: cell.language || LANGUAGE,
		source: cell.source,
	}));
	return Buffer.from(`${JSON.stringify({ version: 1, cells: raw }, null, "\t")}\n`, "utf8");
}

module.exports = { readNotebook, writeNotebook, LANGUAGE };
