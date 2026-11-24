// kbnb.js — the VS Code side of a Micro-Expert notebook: the `.kbnb` serializer, the
// controller that runs a cell against the engine, the question a cell asks, and the two
// commands that open a notebook and restart its session. kbnb-session.js holds the process
// and its markers, and kbnb-file.js the file itself, so this file only turns cells, their
// output and their questions into what VS Code asks for.

const path = require("path");
const vscode = require("vscode");
const { readNotebook, writeNotebook, LANGUAGE } = require("./kbnb-file");
const { KbnbSession } = require("./kbnb-session");

const NOTEBOOK_TYPE = "micro-expert-notebook";
// The renderer that draws a question: it is declared in package.json, and the id here is
// what the message it posts comes back through.
const RENDERER_ID = "kbnb-ask";
const ASK_MIME = "application/kbnb-ask+json";
// A new notebook's one cell is a question, and the hint above it is markdown: a line starting
// with // is not a line the engine reads, so the same words in a code cell were refused as a
// command and the cell was marked failed.
const STARTER = "is-parent-of(?p, tim)";
const STARTER_NOTE =
	"Shift+Enter runs a cell: a fact, a rule as `head => conditions`, or a question.";

function codeCell(source) {
	return new vscode.NotebookCellData(vscode.NotebookCellKind.Code, source, LANGUAGE);
}

function deserialize(bytes) {
	const file = readNotebook(bytes);
	const cells = file.cells.map((cell) =>
		cell.kind === "markdown"
			? new vscode.NotebookCellData(vscode.NotebookCellKind.Markup, cell.source, "markdown")
			: codeCell(cell.source)
	);
	return new vscode.NotebookData(cells);
}

function serialize(data) {
	return writeNotebook(
		data.cells.map((cell) => ({
			kind: cell.kind === vscode.NotebookCellKind.Markup ? "markdown" : "code",
			language: cell.languageId,
			source: cell.value,
		}))
	);
}

// A cell waiting at a question: the ask's number, the prompt it is waiting at, and what a
// value there stands for - drawn by the renderer as a box that explains itself. The answer
// names the number, so a box answered late cannot become the value of a later question.
// A cell's text as the output VS Code draws as its own.
function stdout(text) {
	return new vscode.NotebookCellOutput([vscode.NotebookCellOutputItem.stdout(text)]);
}

function askOutput(ask) {
	return new vscode.NotebookCellOutput([
		new vscode.NotebookCellOutputItem(Buffer.from(JSON.stringify(ask), "utf8"), ASK_MIME),
	]);
}

function register(context, { resolveInterpreter, projectDirFor, domainFor }) {
	const controller = vscode.notebooks.createNotebookController(
		"microExpert-notebook",
		NOTEBOOK_TYPE,
		"Micro-Expert",
		(cells, notebook, control) => execute(cells, notebook, control)
	);
	controller.supportedLanguages = [LANGUAGE];
	controller.supportsExecutionOrder = true;
	context.subscriptions.push(controller);

	context.subscriptions.push(
		vscode.workspace.registerNotebookSerializer(
			NOTEBOOK_TYPE,
			{ deserializeNotebook: deserialize, serializeNotebook: serialize },
			{ transientOutputs: true }
		)
	);

	// notebook uri -> the engine process its cells share.
	const sessions = new Map();
	// `${notebook uri}\0${ask}` -> what the box's answer resolves.
	const waiting = new Map();
	let order = 0;

	// The renderer posts back what was typed into a box, and the cell that asked goes on
	// from there. A message with no box waiting - answered twice, or after the cell was
	// stopped - resolves nothing.
	context.subscriptions.push(
		vscode.notebooks.createRendererMessaging(RENDERER_ID).onDidReceiveMessage((event) => {
			const message = event && event.message;
			if (!message || message.type !== "kbnb-answer" || !event.editor) return;
			const key = `${event.editor.notebook.uri.toString()}\u0000${String(message.id)}`;
			const resolve = waiting.get(key);
			if (!resolve) return;
			waiting.delete(key);
			resolve(typeof message.value === "string" ? message.value : null);
		})
	);

	// Every box a notebook is waiting at is answered the same way, so a stopped or closed
	// notebook does not leave a cell waiting for an answer that can no longer come.
	function settle(notebook, value = null) {
		const prefix = `${notebook.uri.toString()}\u0000`;
		for (const [key, resolve] of waiting) {
			if (!key.startsWith(prefix)) continue;
			waiting.delete(key);
			resolve(value);
		}
	}

	function sessionFor(notebook, project, interpreter) {
		const key = notebook.uri.toString();
		let session = sessions.get(key);
		if (session && !session.running) {
			sessions.delete(key);
			session = undefined;
		}
		if (!session) {
			// src/notebook.ms is the entry the engine serves cells through; the project
			// folder is its cwd, so the domain's paths are the ones a run would find.
			session = new KbnbSession({
				command: interpreter.command,
				args: [path.join(project, "src", "notebook.ms"), "--domain", domainFor(project)],
				cwd: project,
				env: { ...process.env, NO_COLOR: "1" },
			});
			sessions.set(key, session);
		}
		return session;
	}

	async function execute(cells, notebook, control) {
		const project = projectDirFor(notebook.uri);
		const interpreter = resolveInterpreter(project);
		const notebookKey = notebook.uri.toString();

		for (const cell of cells) {
			if (cell.kind !== vscode.NotebookCellKind.Code) continue;

			const execution = control.createNotebookCellExecution(cell);
			execution.executionOrder = ++order;
			execution.start(Date.now());

			if (interpreter.problem) {
				await execution.replaceOutput([
					new vscode.NotebookCellOutput([
						vscode.NotebookCellOutputItem.error(new Error(interpreter.problem)),
					]),
				]);
				execution.end(false, Date.now());
				continue;
			}

			const session = sessionFor(notebook, project, interpreter);
			const cancellation = execution.token.onCancellationRequested(() => {
				// A notebook's stop kills the engine rather than the cell: a question's answer
				// is the only way the engine gives the cell back, so the box is declined and
				// the process is taken away with it.
				session.stop();
				settle(notebook, null);
			});

			// What the cell has said so far is drawn as it arrives: a question's report is
			// printed before the ask, and the box under it says the same thing in one line for
			// when that report has scrolled away. A box is taken away once it is answered, since
			// what the answer did appears in the text itself.
			let printed = "";
			const boxes = new Map();
			const redraw = () => {
				const outputs = printed ? [stdout(printed)] : [];
				for (const box of boxes.values()) outputs.push(box);
				execution.replaceOutput(outputs).catch(() => {});
			};

			const result = await session.run(cell.document.getText(), {
				onText: (text) => {
					printed = text;
					redraw();
				},
				onAsk: (ask) =>
					new Promise((resolve) => {
						const key = `${notebookKey}\u0000${ask.id}`;
						boxes.set(key, askOutput(ask));
						redraw();
						waiting.set(key, (value) => {
							boxes.delete(key);
							redraw();
							resolve(value);
						});
					}),
			});
			cancellation.dispose();

			// What the cell printed, as the run ended with it: the last text drawn above is the
			// same one, so the final output is rebuilt from the result rather than kept aside.
			const outputs = result.text ? [stdout(result.text)] : [];
			for (const draw of result.draws) {
				outputs.push(
					new vscode.NotebookCellOutput([
						vscode.NotebookCellOutputItem.text(draw.text, draw.mime),
					])
				);
			}
			if (!result.success) {
				outputs.push(
					new vscode.NotebookCellOutput([
						vscode.NotebookCellOutputItem.error(new Error(result.error)),
					])
				);
			}
			await execution.replaceOutput(outputs);
			// A warning is what the engine marks a cell with: the line that was refused is in
			// the cell's own text, so the cell ends failed without a second error under it.
			execution.end(result.success && !result.failed, Date.now());
		}
	}

	async function newNotebook() {
		const data = new vscode.NotebookData([
			new vscode.NotebookCellData(vscode.NotebookCellKind.Markup, STARTER_NOTE, "markdown"),
			codeCell(STARTER),
		]);
		const notebook = await vscode.workspace.openNotebookDocument(NOTEBOOK_TYPE, data);
		await vscode.window.showNotebookDocument(notebook);
	}

	function restartNotebook() {
		const editor = vscode.window.activeNotebookEditor;
		const notebook = editor ? editor.notebook : undefined;
		if (!notebook || notebook.notebookType !== NOTEBOOK_TYPE) {
			vscode.window.showWarningMessage("Open a Micro-Expert notebook to restart its session.");
			return;
		}
		const key = notebook.uri.toString();
		const session = sessions.get(key);
		if (session) {
			session.dispose();
			sessions.delete(key);
		}
		settle(notebook, null);
		vscode.window.showInformationMessage(
			"Knowledge session restarted. The facts a cell added are gone, and the next cell starts from the domain's files."
		);
	}

	function forget(notebook) {
		const key = notebook.uri.toString();
		const session = sessions.get(key);
		if (session) {
			session.dispose();
			sessions.delete(key);
		}
		settle(notebook, null);
	}

	context.subscriptions.push(
		vscode.commands.registerCommand("microExpert.newNotebook", newNotebook),
		vscode.commands.registerCommand("microExpert.restartNotebook", restartNotebook),
		vscode.workspace.onDidCloseNotebookDocument(forget),
		vscode.workspace.onDidChangeConfiguration((event) => {
			const changed = [
				"microExpert.interpreterPath",
				"microExpert.projectDir",
				"microExpert.domain",
			].some((setting) => event.affectsConfiguration(setting));
			if (!changed) return;
			// A session holds the interpreter, the folder and the domain it started with, so a
			// setting that changes starts the next cell's session afresh.
			for (const session of sessions.values()) session.dispose();
			sessions.clear();
			for (const key of [...waiting.keys()]) {
				const resolve = waiting.get(key);
				waiting.delete(key);
				resolve(null);
			}
		})
	);

	return { controller, sessions };
}

// Only the registration: the serializer, the cells and the questions are this file's own, and
// nothing outside it can name them without a `vscode` to build them with.
module.exports = { register };
