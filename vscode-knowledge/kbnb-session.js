// kbnb-session.js — the engine process a `.kbnb` notebook talks to, and the markers it speaks.
//
// src/notebook.ms in micro-expert is the other end, so this file knows only the marks: a
// cell between two, the output it prints between two, the pictures it draws, and the ask a
// question makes when it needs a value before a proof can go on.
//
//   <<kbnb:cell>>                what this file writes: a cell's source, then its end
//   <<kbnb:end>>
//   <<kbnb:out>>                 what the engine writes: the cell's text, with the ask
//   <<kbnb:end-out>>             inside it where the prompt happened, then the mark of a
//   <<kbnb:failed>>              warning, then the picture the cell drew - the draw block
//   <<kbnb:draw:image/svg+xml>>  comes after the output has ended, not inside it, since a
//   <<kbnb:end-draw>>            notebook draws the picture beside the text
//   <<kbnb:ask:1>>               a question waiting for a value: the prompt and what a value
//   ?p =                          there stands for, then its end
//   the parent of ?p, needed to answer is-uncle-of(oliver, ?p)
//   <<kbnb:end-ask>>
//   <<kbnb:done>>                the cell is over, whatever it did
//
// The answer the ask waits for is `<<kbnb:answer:1>> walter` or `<<kbnb:decline:1>>`, and
// this file writes it the moment the caller's onAsk answers - the engine holds the cell
// open until then, which is what lets a proof go on with the value.
//
// No `vscode` here: what the process is and what it says is all this module knows, so it can
// be run by node on its own, and the tests do exactly that against the real engine.

const { spawn } = require("child_process");

const CELL_START = "<<kbnb:cell>>";
const CELL_END = "<<kbnb:end>>";
const OUT_START = "<<kbnb:out>>";
const OUT_END = "<<kbnb:end-out>>";
const DRAW_START = "<<kbnb:draw:";
const DRAW_END = "<<kbnb:end-draw>>";
const ASK_START = "<<kbnb:ask:";
const ASK_END = "<<kbnb:end-ask>>";
const ANSWER_START = "<<kbnb:answer:";
const DECLINE_START = "<<kbnb:decline:";
const FAILED = "<<kbnb:failed>>";
const DONE = "<<kbnb:done>>";

// Lines arrive as the pipe gives them, which is not a line at a time: a chunk may hold half
// a line or six of them. The reader keeps the part-written one and hands out whole lines as
// they arrive, waiting when there is none, so the protocol below reads as a sequence.
class Lines {
	constructor() {
		this.waiting = [];
		this.pending = [];
		this.closed = false;
	}

	push(line) {
		const waiting = this.waiting.shift();
		if (waiting) waiting(line);
		else this.pending.push(line);
	}

	close() {
		this.closed = true;
		while (this.waiting.length) this.waiting.shift()(null);
	}

	next() {
		if (this.pending.length) return Promise.resolve(this.pending.shift());
		if (this.closed) return Promise.resolve(null);
		return new Promise((resolve) => this.waiting.push(resolve));
	}
}

function marker(line, prefix) {
	return line.startsWith(prefix) && line.endsWith(">>") ? line.slice(prefix.length, -2) : null;
}

class KbnbSession {
	constructor({ command, args = [], cwd, env }) {
		this.lines = new Lines();
		this.stderr = "";
		this.stray = [];
		this.exited = null;
		this.problem = null;

		this.child = spawn(command, args, { cwd, env, stdio: ["pipe", "pipe", "pipe"] });
		this.child.stdout.setEncoding("utf8");
		let rest = "";
		this.child.stdout.on("data", (chunk) => {
			rest += chunk;
			let at;
			while ((at = rest.indexOf("\n")) !== -1) {
				const line = rest.slice(0, at).replace(/\r$/, "");
				rest = rest.slice(at + 1);
				this.lines.push(line);
			}
		});
		this.child.stderr.setEncoding("utf8");
		this.child.stderr.on("data", (chunk) => {
			this.stderr += chunk;
		});
		this.child.on("error", (error) => {
			this.problem = error.message;
			this.lines.close();
		});
		this.child.on("exit", (code, signal) => {
			this.exited = { code, signal };
			this.lines.close();
		});
	}

	get running() {
		return !this.exited && !this.problem;
	}

	write(line) {
		if (!this.running) return;
		try {
			this.child.stdin.write(line);
		} catch (error) {
			this.problem = error.message;
		}
	}

	// The cell's own result: what it printed, whether a line of it was refused, the pictures
	// it drew, and - when the engine never finished the cell - what went wrong instead.
	// onText is handed the cell's text so far as each line arrives, and onAsk each question
	// the cell waits at - with the prompt and what a value there stands for, since a box that
	// outlives the report above it has to explain itself.
	async run(source, { onAsk, onText } = {}) {
		if (!this.running) {
			return { success: false, error: this.endReason(), text: "", failed: false, draws: [] };
		}
		this.write(`${CELL_START}\n${source}\n${CELL_END}\n`);

		const text = [];
		const draws = [];
		const blocks = [];
		let failed = false;
		let drawing = null;
		let asking = null;

		while (true) {
			const line = await this.lines.next();
			if (line === null) {
				return {
					success: false,
					error: this.endReason(),
					text: text.join("\n"),
					failed,
					draws,
				};
			}

			// A block is opened by its mark and closed by the matching end, and one may sit
			// inside another: the ask is written inside the output, where the prompt happened,
			// so the text after it belongs to the output again, not to nothing. The diagram is
			// not nested - its block comes after <<kbnb:end-out>> and is the picture itself.
			const enclosing = blocks.length ? blocks[blocks.length - 1] : "idle";

			if (line === OUT_START) {
				blocks.push("out");
				continue;
			}
			if (line === OUT_END || line === DRAW_END) {
				if (enclosing === "draw" && drawing) {
					draws.push({ mime: drawing.mime, text: drawing.text.join("\n") });
					drawing = null;
				}
				blocks.pop();
				continue;
			}
			if (line === FAILED) {
				failed = true;
				continue;
			}
			if (line === DONE) break;

			const mime = marker(line, DRAW_START);
			if (mime !== null) {
				drawing = { mime, text: [] };
				blocks.push("draw");
				continue;
			}

			const id = marker(line, ASK_START);
			if (id !== null) {
				asking = { id, lines: [] };
				blocks.push("ask");
				continue;
			}
			if (line === ASK_END) {
				const ask = asking || { id: "", lines: [] };
				asking = null;
				blocks.pop();
				// The first line is the prompt; anything after it is what a value there stands
				// for, which the box shows so the question explains itself.
				const [prompt = "", ...why] = ask.lines;
				// The engine holds the cell here until this answers, so nothing else can be
				// read from it in the meantime.
				const value = onAsk
					? await onAsk({ id: ask.id, prompt, why: why.join(" ").trim() })
					: null;
				if (value === null || value === undefined) {
					this.write(`${DECLINE_START}${ask.id}>>\n`);
				} else {
					this.write(`${ANSWER_START}${ask.id}>> ${String(value).replace(/\r?\n/g, " ")}\n`);
				}
				continue;
			}

			if (enclosing === "draw" && drawing) drawing.text.push(line);
			else if (enclosing === "ask" && asking) asking.lines.push(line);
			else if (enclosing === "out") {
				text.push(line);
				if (onText) onText(text.join("\n"));
			}
			// A line outside every block is not part of a cell: it is the engine saying
			// something about itself - a domain file it could not read - and it belongs to the
			// error the cell ends with rather than to its output.
			else this.stray.push(line);
		}

		return { success: true, error: null, text: text.join("\n"), failed, draws };
	}

	endReason() {
		const said = this.stray.join("\n").trim();
		if (said) return said;
		if (this.problem) return this.problem;
		if (this.stderr.trim()) return this.stderr.trim();
		if (this.exited) {
			const how = this.exited.signal
				? `signal ${this.exited.signal}`
				: `exit ${this.exited.code}`;
			return `The knowledge session ended (${how}).`;
		}
		return "The knowledge session ended.";
	}

	stop() {
		if (this.running) this.child.kill();
	}

	dispose() {
		this.stop();
	}
}

module.exports = { KbnbSession };
