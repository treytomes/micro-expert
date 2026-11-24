// kbnb.js against a fake `vscode` small enough to hold in a hand: what a save writes, what
// two runs of a notebook do about each other, and what a cell's question looks like until it
// is answered. The module reads `vscode` when it is loaded and there is no extension host
// here, so the one name is answered from this file; the engine process is stood in for too,
// since a session that answers from a function keeps the controller's own work - the queue,
// the boxes, the executions - what the tests see.

const { test, beforeEach } = require("node:test");
const assert = require("node:assert/strict");
const Module = require("module");

const CODE = 1;
const MARKUP = 2;
const LANGUAGE = "micro-expert-kb";
const NOTEBOOK_TYPE = "micro-expert-notebook";
const ASK_MIME = "application/kbnb-ask+json";
const STDOUT_MIME = "application/vnd.code.notebook.stdout";

// What the fake recorded, as the tests look at it: a save's provider, the controller's
// handler, the renderer's message handler, and the sessions the controller started.
let recorded;

function reset() {
	recorded = {
		serializers: new Map(),
		controllers: [],
		renderer: null,
		sessions: [],
	};
}

class NotebookCellOutputItem {
	constructor(value, mime) {
		this.value = value;
		this.mime = mime;
	}

	static stdout(text) {
		return new NotebookCellOutputItem(text, STDOUT_MIME);
	}

	static error(error) {
		return new NotebookCellOutputItem(error.message, "application/vnd.code.notebook.error");
	}

	static text(value, mime) {
		return new NotebookCellOutputItem(value, mime);
	}
}

class NotebookCellOutput {
	constructor(items) {
		this.items = items;
	}
}

class NotebookCellData {
	constructor(kind, value, languageId) {
		this.kind = kind;
		this.value = value;
		this.languageId = languageId;
	}
}

class NotebookData {
	constructor(cells) {
		this.cells = cells;
	}
}

const disposable = () => ({ dispose() {} });

// Only what register reaches for: the window and the two commands it opens a notebook with
// are the extension's, not the controller's, and no test runs them.
const vscode = {
	NotebookCellKind: { Code: CODE, Markup: MARKUP },
	NotebookCellData,
	NotebookData,
	NotebookCellOutput,
	NotebookCellOutputItem,
	notebooks: {
		createNotebookController(id, notebookType, label, handler) {
			const controller = { id, notebookType, label, handler, dispose() {} };
			recorded.controllers.push(controller);
			return controller;
		},
		createRendererMessaging(id) {
			const messaging = { id, handler: null };
			recorded.renderer = messaging;
			return {
				onDidReceiveMessage(handler) {
					messaging.handler = handler;
					return disposable();
				},
			};
		},
	},
	workspace: {
		registerNotebookSerializer(notebookType, provider, options) {
			recorded.serializers.set(notebookType, { provider, options });
			return disposable();
		},
		onDidCloseNotebookDocument: disposable,
		onDidChangeConfiguration: disposable,
	},
	commands: { registerCommand: disposable },
};

const load = Module._load;
Module._load = function (request, parent, isMain) {
	if (request === "vscode") return vscode;
	return load.apply(this, arguments);
};

// The controller only ever asks a session to run a cell, so the process's own honesty - the
// markers, the answer lines - is kbnb-session.test.js's subject against the real engine.
class FakeSession {
	constructor(options) {
		this.options = options;
		this.running = true;
		this.stopped = false;
		recorded.sessions.push(this);
	}

	run(source, handlers) {
		return behaviour(this, source, handlers || {});
	}

	stop() {
		this.stopped = true;
		this.running = false;
	}

	dispose() {
		this.stop();
	}
}

const sessionPath = require.resolve("../kbnb-session");
require.cache[sessionPath] = {
	id: sessionPath,
	filename: sessionPath,
	loaded: true,
	exports: { KbnbSession: FakeSession },
};

const kbnb = require("../kbnb");

let behaviour;

beforeEach(() => {
	reset();
	behaviour = async (session, source) => result(source);
});

function result(source, extra) {
	return { success: true, error: null, text: `ran ${source}`, failed: false, draws: [], ...extra };
}

function register() {
	kbnb.register(
		{ subscriptions: [] },
		{
			resolveInterpreter: () => ({ command: "/fake/miniscript" }),
			projectDirFor: () => "/fake/project",
			domainFor: () => "data",
		}
	);
}

function controller() {
	const registered = recorded.controllers[recorded.controllers.length - 1];
	assert.ok(registered, "register started a notebook controller");
	return registered;
}

function notebookFor(uri) {
	return { uri: { toString: () => uri } };
}

function codeCell(source) {
	return { kind: CODE, document: { getText: () => source } };
}

// The execution a cell is handed: what it drew, whether it was started and how it ended. A
// token that is already cancelled stands for the cell VS Code stopped while it waited.
function controlFor({ cancelled = false } = {}) {
	const executions = [];
	return {
		executions,
		createNotebookCellExecution(cell) {
			const listeners = [];
			const execution = {
				cell,
				executionOrder: 0,
				outputs: [],
				started: false,
				ended: null,
				replaceOutput(outputs) {
					execution.outputs = outputs;
					return Promise.resolve();
				},
				start() {
					execution.started = true;
				},
				end(ok) {
					execution.ended = ok;
				},
				token: {
					isCancellationRequested: cancelled,
					onCancellationRequested(listener) {
						listeners.push(listener);
						return disposable();
					},
				},
				cancel() {
					execution.token.isCancellationRequested = true;
					for (const listener of [...listeners]) listener();
				},
			};
			executions.push(execution);
			return execution;
		},
	};
}

async function until(ready) {
	for (let tries = 0; tries < 500; tries++) {
		if (ready()) return;
		await new Promise((resolve) => setTimeout(resolve, 1));
	}
	throw new Error("the test's condition never held");
}

test("a save writes the file's bytes, through the file's own writer", () => {
	register();
	const { provider } = recorded.serializers.get(NOTEBOOK_TYPE);
	assert.ok(provider, "the notebook type has a serializer");
	// The writer takes the notebook's data and nothing else: the queue's helper is a name and
	// a piece of work, so a registration that pointed at it would take two.
	assert.equal(provider.serializeNotebook.length, 1);

	const data = new vscode.NotebookData([
		new vscode.NotebookCellData(MARKUP, "# The family", "markdown"),
		new vscode.NotebookCellData(CODE, "is-parent-of(?p, tim)", LANGUAGE),
	]);

	// A save is the file's bytes and they are here at once: the queue's helper returns a
	// promise instead, and a name shared with it would have handed the notebook itself to the
	// queue in place of the writer.
	const saved = provider.serializeNotebook(data);
	assert.equal(Buffer.isBuffer(saved), true);
	assert.deepEqual(JSON.parse(saved.toString("utf8")), {
		version: 1,
		cells: [
			{ kind: "markdown", language: "markdown", source: "# The family" },
			{ kind: "code", language: LANGUAGE, source: "is-parent-of(?p, tim)" },
		],
	});

	const back = provider.deserializeNotebook(saved);
	assert.equal(back.cells.length, 2);
	assert.equal(back.cells[0].kind, MARKUP);
	assert.equal(back.cells[0].value, "# The family");
	assert.equal(back.cells[1].kind, CODE);
	assert.equal(back.cells[1].value, "is-parent-of(?p, tim)");
	assert.equal(back.cells[1].languageId, LANGUAGE);
});

test("two runs of a notebook happen one after the other, each with its own answer", async () => {
	register();
	const running = controller();
	const notebook = notebookFor("file:///one.kbnb");
	const events = [];
	behaviour = async (session, source) => {
		events.push(`start ${source}`);
		await new Promise((resolve) => setTimeout(resolve, 5));
		events.push(`end ${source}`);
		return result(source);
	};

	const first = controlFor();
	const second = controlFor();
	const a = running.handler([codeCell("first")], notebook, first);
	const b = running.handler([codeCell("second")], notebook, second);
	await Promise.all([a, b]);

	// The queue is the point: the second run's own engine lines cannot arrive while the
	// first still holds the process.
	assert.deepEqual(events, ["start first", "end first", "start second", "end second"]);
	assert.equal(first.executions[0].outputs[0].items[0].value, "ran first");
	assert.equal(second.executions[0].outputs[0].items[0].value, "ran second");
	assert.equal(first.executions[0].ended, true);
	assert.equal(second.executions[0].ended, true);
	// One process per notebook, shared by both runs.
	assert.equal(recorded.sessions.length, 1);
});

test("a run that follows a failed one still runs", async () => {
	register();
	const running = controller();
	const notebook = notebookFor("file:///one.kbnb");
	const events = [];
	behaviour = async (session, source) => {
		events.push(source);
		if (source === "first") throw new Error("the process went away");
		return result(source);
	};

	const first = controlFor();
	const second = controlFor();
	const a = running.handler([codeCell("first")], notebook, first).catch((error) => error);
	const b = running.handler([codeCell("second")], notebook, second);
	await Promise.all([a, b]);

	// The failure was that cell's, and the session it left behind is where the next one
	// starts, so the queue lets go of it instead of refusing everything after it.
	assert.match((await a).message, /went away/);
	assert.deepEqual(events, ["first", "second"]);
	assert.equal(second.executions[0].outputs[0].items[0].value, "ran second");
});

test("a run stopped while it waits its turn ends without running", async () => {
	register();
	const running = controller();
	const notebook = notebookFor("file:///one.kbnb");
	const events = [];
	behaviour = async (session, source) => {
		events.push(source);
		await new Promise((resolve) => setTimeout(resolve, 5));
		return result(source);
	};

	const first = controlFor();
	const second = controlFor({ cancelled: true });
	const a = running.handler([codeCell("first")], notebook, first);
	const b = running.handler([codeCell("second")], notebook, second);
	await Promise.all([a, b]);

	assert.deepEqual(events, ["first"]);
	assert.equal(second.executions[0].started, true);
	assert.equal(second.executions[0].ended, false);
	assert.equal(second.executions[0].outputs.length, 0);
});

test("a question is a box while it waits, and the answer is what the cell goes on with", async () => {
	register();
	const running = controller();
	const notebook = notebookFor("file:///one.kbnb");
	let answer = null;
	behaviour = async (session, source, handlers) => {
		answer = handlers.onAsk({ id: "1", prompt: "?p =", why: "the parent of ?p" });
		const value = await answer;
		return result(source, { text: `is-parent-of(${value}, susan)` });
	};

	const control = controlFor();
	const run = running.handler([codeCell("is-parent-of(?p, susan)")], notebook, control);
	await until(() => answer);

	const execution = control.executions[0];
	const box = execution.outputs.find((output) => output.items[0].mime === ASK_MIME);
	assert.ok(box, "the cell draws the box while the question waits");
	const ask = JSON.parse(box.items[0].value.toString("utf8"));
	assert.equal(ask.prompt, "?p =");
	assert.equal(ask.why, "the parent of ?p");

	recorded.renderer.handler({
		message: { type: "kbnb-answer", id: "1", value: "walter" },
		editor: { notebook },
	});
	await run;

	// The box is gone once it is answered: what the answer did is in the text itself.
	assert.equal(execution.outputs.some((output) => output.items[0].mime === ASK_MIME), false);
	assert.equal(execution.outputs[0].items[0].value, "is-parent-of(walter, susan)");
	assert.equal(execution.ended, true);
});

test("a stopped cell declines the question it is waiting at", async () => {
	register();
	const running = controller();
	const notebook = notebookFor("file:///one.kbnb");
	let answer = null;
	behaviour = async (session, source, handlers) => {
		answer = handlers.onAsk({ id: "1", prompt: "?p =", why: "" });
		const value = await answer;
		return result(source, { text: `value ${value}` });
	};

	const control = controlFor();
	const run = running.handler([codeCell("is-parent-of(?p, susan)")], notebook, control);
	await until(() => answer);
	control.executions[0].cancel();
	await run;

	// A question's answer is the only way the process gives the cell back, so a stop takes
	// the process with the box, and the cell ends at the value it got: none.
	assert.equal(recorded.sessions[0].stopped, true);
	assert.equal(control.executions[0].outputs[0].items[0].value, "value null");
});
