// extension.js — what the extension starts. The `.kb` grammar is declared in package.json;
// this file registers the notebook and reads the two settings a session needs: the engine's
// project folder, and the interpreter that runs it.

const fs = require("fs");
const path = require("path");
const vscode = require("vscode");
const kbnb = require("./kbnb");

function setting(name, fallback = "") {
	const value = vscode.workspace.getConfiguration("microExpert").get(name);
	return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

// One value out of a project's .env: the last line setting it, with quotes and a trailing
// CR from a file written on Windows removed. Nothing here needs the rest of that file.
function readEnvValue(dir, key) {
	let text;
	try {
		text = fs.readFileSync(path.join(dir, ".env"), "utf8");
	} catch (error) {
		return "";
	}
	let found = "";
	for (const line of text.split("\n")) {
		const entry = line.replace(/\r$/, "").trim();
		if (!entry || entry.startsWith("#") || !entry.includes("=")) continue;
		const at = entry.indexOf("=");
		if (entry.slice(0, at).trim() !== key) continue;
		found = entry
			.slice(at + 1)
			.trim()
			.replace(/^"(.*)"$/, "$1")
			.replace(/^'(.*)'$/, "$1");
	}
	return found;
}

// The folder whose src/notebook.ms the notebook's cells run through. The setting wins, then
// the workspace folder the notebook sits in, then the notebook's own folder - so a `.kbnb`
// opened inside a micro-expert checkout needs nothing said.
function projectDirFor(uri) {
	const configured = setting("projectDir");
	if (configured) {
		if (path.isAbsolute(configured)) return configured;
		const folder = vscode.workspace.getWorkspaceFolder(uri);
		if (folder) return path.join(folder.uri.fsPath, configured);
		return configured;
	}
	const folder = vscode.workspace.getWorkspaceFolder(uri);
	if (folder) return folder.uri.fsPath;
	if (uri && uri.scheme === "file") return path.dirname(uri.fsPath);
	const folders = vscode.workspace.workspaceFolders || [];
	return folders.length ? folders[0].uri.fsPath : process.cwd();
}

// The engine to start, or the sentence saying what is missing instead of starting nothing
// and leaving the cell to fail with a spawn error nobody can act on.
function resolveInterpreter(project) {
	const entry = path.join(project, "src", "notebook.ms");
	if (!fs.existsSync(entry)) {
		return {
			command: "",
			problem:
				`No micro-expert engine in ${project}: src/notebook.ms is not there. ` +
				"Open the project folder, or set microExpert.projectDir to it.",
		};
	}
	const named = setting("interpreterPath") || readEnvValue(project, "MINISCRIPT_EXE_PATH");
	if (named) {
		if (!fs.existsSync(named)) {
			return {
				command: "",
				problem:
					`The MiniScript interpreter was not found: ${named}. ` +
					`Set microExpert.interpreterPath, or MINISCRIPT_EXE_PATH in ${path.join(project, ".env")}.`,
			};
		}
		return { command: named };
	}
	// Nothing named: the interpreter on PATH, which the engine's own scripts assume.
	return { command: "miniscript" };
}

function domainFor() {
	return setting("domain", "data");
}

function activate(context) {
	kbnb.register(context, { resolveInterpreter, projectDirFor, domainFor });
}

function deactivate() {}

module.exports = { activate, deactivate };
