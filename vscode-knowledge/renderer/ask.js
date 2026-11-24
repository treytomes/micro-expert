// renderer/ask.js — the box a cell waiting for a value shows, drawn in the cell where the
// prompt happened. It posts what was typed back to the extension that started the engine;
// the extension writes it to the session as `<<kbnb:answer:N>> value`, or a decline, and the
// cell goes on from there.
//
// A renderer is a module with `activate`, and the messaging it uses is the one the extension
// listens for: see createRendererMessaging("kbnb-ask") in kbnb.js.

export function activate(context) {
	return {
		renderOutputItem(outputItem, element) {
			let ask;
			try {
				ask = outputItem.json();
			} catch (error) {
				return;
			}

			const wrap = document.createElement("div");
			wrap.style.cssText = [
				"display:flex",
				"flex-direction:column",
				"gap:2px",
				"padding:4px 0",
				"font-family:var(--vscode-editor-font-family)",
				"font-size:var(--vscode-editor-font-size)",
			].join(";");

			const label = document.createElement("span");
			// The engine writes "  ?p = " as the prompt it is waiting at; the box follows it.
			label.textContent = String(ask.prompt || "").trim() || "value";
			label.style.cssText = "white-space:pre;opacity:.9";

			const input = document.createElement("input");
			input.type = "text";
			input.setAttribute("aria-label", label.textContent);
			input.style.cssText = [
				"flex:0 1 22em",
				"min-width:6em",
				"padding:2px 6px",
				"color:var(--vscode-input-foreground)",
				"background:var(--vscode-input-background)",
				"border:1px solid var(--vscode-input-border,transparent)",
				"border-radius:2px",
				"font:inherit",
			].join(";");

			const answer = document.createElement("button");
			answer.type = "submit";
			answer.textContent = "Answer";
			answer.style.cssText = buttonStyle(true);

			const decline = document.createElement("button");
			decline.type = "button";
			decline.textContent = "Skip";
			decline.title = "The question is left without a value, and the cell ends.";
			decline.style.cssText = buttonStyle(false);

			const form = document.createElement("form");
			form.style.cssText = "display:flex;align-items:center;gap:6px;margin:0";
			form.append(label, input, answer, decline);
			wrap.append(form);

			// What a value there stands for, under the box: the report in the cell above says
			// the same thing at length, and a cell scrolled past leaves the box on its own.
			const why = String(ask.why || "").trim();
			if (why) {
				const reason = document.createElement("div");
				reason.textContent = why;
				reason.style.cssText = [
					"color:var(--vscode-descriptionForeground)",
					"font-size:.92em",
					"white-space:pre-wrap",
				].join(";");
				wrap.append(reason);
			}

			element.append(wrap);

			// One answer per box: the second click would be an answer to a question that is no
			// longer waiting, and the extension would rightly ignore it.
			let settled = false;
			function settle(value, said) {
				if (settled) return;
				settled = true;
				context.postMessage({ type: "kbnb-answer", id: String(ask.id), value });
				input.disabled = true;
				answer.disabled = true;
				decline.disabled = true;
				label.textContent = said;
			}

			form.addEventListener("submit", (event) => {
				event.preventDefault();
				const value = input.value;
				settle(value, `${label.textContent} ${value}`);
			});
			decline.addEventListener("click", () => settle(null, `${label.textContent} (skipped)`));

			input.focus();
		},
	};
}

function buttonStyle(primary) {
	return [
		"padding:2px 8px",
		"font:inherit",
		"border:1px solid var(--vscode-button-border,transparent)",
		"border-radius:2px",
		primary
			? "color:var(--vscode-button-foreground);background:var(--vscode-button-background)"
			: "color:var(--vscode-button-secondaryForeground);background:var(--vscode-button-secondaryBackground)",
	].join(";");
}
