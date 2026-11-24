// The engine process a `.kbnb` notebook talks to, against the real engine: a cell's text,
// its warning, the diagram it draws, and the question that holds the cell open until a
// value arrives - because what this module does with the markers is only meaningful against
// what src/notebook.ms writes.

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");

const { KbnbSession } = require("../kbnb-session");

const root = path.resolve(__dirname, "../..");

function fromEnvFile() {
	try {
		const text = fs.readFileSync(path.join(root, ".env"), "utf8");
		const at = text
			.split("\n")
			.map((entry) => entry.replace(/\r$/, ""))
			.find((entry) => entry.startsWith("MINISCRIPT_EXE_PATH"));
		if (!at) return "";
		return at
			.slice(at.indexOf("=") + 1)
			.trim()
			.replace(/^"(.*)"$/, "$1");
	} catch (error) {
		return "";
	}
}

const interpreter = [
	process.env.MINISCRIPT_EXE_PATH,
	fromEnvFile(),
	path.join(root, "3rd-party/miniscript-win/miniscript.exe"),
	path.join(root, "3rd-party/miniscript-linux/miniscript"),
	path.join(root, "3rd-party/miniscript-mac/miniscript"),
]
	.filter(Boolean)
	.map((candidate) => (path.isAbsolute(candidate) ? candidate : path.join(root, candidate)))
	.find((candidate) => fs.existsSync(candidate));

const entry = path.join(root, "src", "notebook.ms");
const skip =
	interpreter && fs.existsSync(entry)
		? false
		: "no MiniScript interpreter and no src/notebook.ms";

function start(t) {
	const session = new KbnbSession({
		command: interpreter,
		args: [entry, "--domain", "data"],
		cwd: root,
		env: { ...process.env, NO_COLOR: "1" },
	});
	t.after(() => session.dispose());
	return session;
}

test("a cell's answer is what it printed, and a warning is told apart from it", { skip, timeout: 120000 }, async (t) => {
	const session = start(t);

	// A fact is a cell that finishes quietly: nothing refused, nothing asked.
	const answer = await session.run("is-parent-of(gale, susan)");
	assert.equal(answer.success, true);
	assert.equal(answer.failed, false);

	// A line the engine refuses is still a cell that finished: the warning is the mark, and
	// the cell's own text says why.
	const refused = await session.run("is-parent-of(susan");
	assert.equal(refused.success, true);
	assert.equal(refused.failed, true);
	assert.notEqual(refused.text.trim(), "");

	const again = await session.run("is-parent-of(gale, ?who)");
	assert.equal(again.success, true);
	assert.equal(again.failed, false);
	assert.match(again.text, /is-parent-of\(gale, susan\)/);
});

test("a fact one cell adds is there in the next", { skip, timeout: 120000 }, async (t) => {
	const session = start(t);

	const added = await session.run("is-parent-of(gale, susan)");
	assert.equal(added.success, true);

	const asked = await session.run("is-parent-of(gale, ?who)");
	assert.equal(asked.success, true);
	assert.match(asked.text, /is-parent-of\(gale, susan\)/);
});

test("a cell of /mermaid draws the fence and the picture", { skip, timeout: 120000 }, async (t) => {
	const session = start(t);

	const drawn = await session.run("/mermaid");
	assert.equal(drawn.success, true);
	assert.match(drawn.text, /```mermaid/);
	assert.equal(drawn.draws.length, 1);
	assert.equal(drawn.draws[0].mime, "image/svg+xml");
	assert.match(drawn.draws[0].text, /<svg/);
});

test("a question asks, and the answer completes the cell", { skip, timeout: 120000 }, async (t) => {
	const session = start(t);
	const asked = [];

	const answered = await session.run("is-parent-of(?p, susan)", {
		onAsk: (ask) => {
			asked.push(ask);
			return "walter";
		},
	});

	assert.equal(asked.length, 1);
	assert.match(asked[0].prompt, /\?p =/);
	assert.equal(answered.success, true);
	assert.equal(answered.failed, false);
	assert.match(answered.text, /is-parent-of\(walter, susan\)/);
});

test("the reason a value is wanted is text before the ask", { skip, timeout: 120000 }, async (t) => {
	const session = start(t);
	let before = "";
	let asked = null;

	const result = await session.run("is-uncle-of(oliver, ?p)", {
		onText: (text) => {
			before = text;
		},
		onAsk: (ask) => {
			asked = { text: before, prompt: ask.prompt, why: ask.why };
			return null;
		},
	});

	// The box under the cell would say what it wants without saying why, so the report that
	// leads to it is the cell's text before the ask - including the note that a name ending in
	// ' is the rule's own variable, which is the one thing the prompt itself cannot explain.
	assert.match(asked.text, /no solution found at depth 8/);
	assert.match(asked.text, /a fact like is-uncle-of\(oliver, \?p\)/);
	assert.match(asked.text, /through rule is-uncle-of/);
	assert.match(asked.text, /not one you asked about/);
	assert.equal(asked.prompt.trim(), "?p' =");
	// The box carries the reason itself, so it still explains the value once the report above
	// has scrolled away: what ?p' stands for, taken from the predicate's own name.
	assert.equal(asked.why, "the parent of ?p, needed to answer is-uncle-of(oliver, ?p)");
	assert.equal(result.failed, true);
});

test("a declined question ends its cell, and the next cell runs", { skip, timeout: 120000 }, async (t) => {
	const session = start(t);

	const declined = await session.run("is-parent-of(?p, susan)", { onAsk: () => null });
	assert.equal(declined.success, true);
	assert.equal(declined.failed, true);
	assert.match(declined.text, /needs a value/);

	const after = await session.run("is-parent-of(?p, susan)", { onAsk: () => "walter" });
	assert.equal(after.success, true);
	assert.equal(after.failed, false);
	assert.match(after.text, /is-parent-of\(walter, susan\)/);
});

test("a stopped session says so instead of waiting", { skip, timeout: 120000 }, async (t) => {
	const session = start(t);
	session.dispose();
	// The exit is what closes the pipe, and it is a moment behind the kill.
	for (let waited = 0; waited < 100 && session.running; waited++) {
		await new Promise((resolve) => setTimeout(resolve, 50));
	}
	assert.equal(session.running, false);

	const stopped = await session.run("is-parent-of(?p, susan)");
	assert.equal(stopped.success, false);
	assert.notEqual(stopped.error, "");
});
