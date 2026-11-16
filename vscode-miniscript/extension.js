const fs = require("fs");
const path = require("path");
const vscode = require("vscode");

const DEFAULT_INTERPRETER = "miniscript";

function quote(value) {
	return `"${value}"`;
}

async function runActiveFile() {
	const editor = vscode.window.activeTextEditor;
	if (!editor || editor.document.languageId !== "miniscript") {
		vscode.window.showWarningMessage("Open a MiniScript file to run it.");
		return;
	}

	const document = editor.document;
	if (document.isDirty && !(await document.save())) {
		vscode.window.showWarningMessage(
			`Could not save ${path.basename(document.uri.fsPath)}; not running it.`
		);
		return;
	}

	const configured = String(
		vscode.workspace.getConfiguration("miniscript2").get("interpreterPath", "") || ""
	).trim();
	if (configured && !fs.existsSync(configured)) {
		vscode.window.showErrorMessage(
			`MiniScript interpreter not found: ${configured}. Check the miniscript2.interpreterPath setting.`
		);
		return;
	}
	const interpreter = configured || DEFAULT_INTERPRETER;

	const folder = vscode.workspace.getWorkspaceFolder(document.uri);
	const cwd = folder ? folder.uri.fsPath : path.dirname(document.uri.fsPath);
	const terminal = vscode.window.createTerminal({
		name: `MiniScript: ${path.basename(document.uri.fsPath)}`,
		cwd,
	});
	terminal.show();
	terminal.sendText(`${quote(interpreter)} ${quote(document.uri.fsPath)}`);
}

function activate(context) {
	context.subscriptions.push(
		vscode.commands.registerCommand("miniscript2.runFile", runActiveFile)
	);
}

function deactivate() {}

module.exports = { activate, deactivate };
