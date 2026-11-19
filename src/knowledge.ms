// knowledge.ms — the parser for the knowledge base's data files: data/facts.kb and
// data/rules.kb at the repo root.
//
// A fact is one triple on a line, predicate(subject, object):
//
//   parent-of(george, anna)
//
// A rule is a head and a body joined by '=>':
//
//   uncle-of(?x, ?y) => and(parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male))
//
// The body is one condition, or a comma-delimited list of them, which means all of
// them must hold — the same thing and(...) says out loud. and(...) nests, and an
// entry may run on to the next line inside its parentheses, or after a rule's arrow.
//
// A condition is a fact, or a constraint such as ?x != ?y. A value is a name, a
// number, or a ?x variable. Blank lines and lines starting with // are skipped, and
// an entry that will not parse names its line.
//
// or(...) holds a body's alternatives: any one of them may hold instead, and each
// alternative is a body of its own, so or(and(a, b), c) reads as it looks. not(...)
// is still reserved: a body holding one is refused, so adding it later is a
// deliberate change to the engine rather than a line that quietly means nothing.
//
// Nothing here imports triples.ms. The parsers are handed the caller's copy, so the
// terms they build are the ones the caller's solver recognizes, and they return the
// pieces Rule.make takes, so they never need the Rule class either.

parseRules = function(triples, lines)
	"Reads the lines of a rules document into {head, body} pieces, or an error naming the line."
	pieces = []
	for entry in entries(lines)
		piece = parseRule(triples, entry.text)
		if piece isa error then return err("line " + entry.line + ": " + piece.message)
		pieces.push(piece)
	end for
	return pieces
end function

parseFacts = function(triples, lines)
	"Reads the lines of a facts document into triples, or an error naming the line."
	facts = []
	for entry in entries(lines)
		fact = parseFact(triples, entry.text)
		if fact isa error then return err("line " + entry.line + ": " + fact.message)
		facts.push(fact)
	end for
	return facts
end function

loadFacts = function(triples, source, relative)
	"Reads the facts file at relative from the module at source and returns its triples, or an error."
	lines = readData(source, relative)
	if lines isa error then return lines
	facts = parseFacts(triples, lines)
	if facts isa error then return err(file.name(relative) + " " + facts.message)
	return facts
end function

loadRules = function(triples, source, relative)
	"Reads the rules file at relative from the module at source and returns its {head, body} pieces, or an error."
	lines = readData(source, relative)
	if lines isa error then return lines
	pieces = parseRules(triples, lines)
	if pieces isa error then return err(file.name(relative) + " " + pieces.message)
	return pieces
end function

readData = function(source, relative)
	"The lines of the data file at relative, or an error naming it and the path tried."
	path = dataPath(source, relative)
	lines = file.readLines(path)
	if lines isa error then return err(file.name(relative) + ": could not read " + path + ": " + lines.message)
	return lines
end function

entries = function(lines)
	"Every entry a data document holds: its text, and the line it started on."
	found = []
	at = 0
	while at < lines.len
		started = at + 1
		text = ""
		// Gather the physical lines one entry spans: it continues while a call is
		// still open, or while the line ends with a rule's arrow.
		while true
			text = text + " " + stripComment(lines[at])
			at = at + 1
			if not needsMore(text) then break
			if at >= lines.len then break
		end while
		text = trimSpace(text)
		if text != "" then found.push({"text": text, "line": started})
	end while
	return found
end function

parseRule = function(triples, text)
	"Reads one rule, 'head => body', into {head, body}, or an error."
	pieces = text.split("=>")
	if pieces.len != 2 then return err("expected 'head => body': " + text)
	head = parseFact(triples, pieces[0])
	if head isa error then return head
	body = parseBody(triples, pieces[1])
	if body isa error then return body
	return {"head": head, "body": body}
end function

parseBody = function(triples, text)
	"Reads a body: one condition, a comma-delimited list of them, or and(...) or or(...) around either."
	text = trimSpace(text)
	if text == "" then return err("a rule needs a condition, after '=>'")
	// A comma that is not inside a call separates conditions, so the list is read
	// first and each piece may itself be a grouping.
	parts = splitTopLevel(text)
	if parts.len > 1 then
		conditions = []
		for part in parts
			more = parseBody(triples, part)
			if more isa error then return more
			conditions = conditions + more
		end for
		return conditions
	end if
	called = parseCall(text)
	// A grouping call is a body of its own; anything else is one condition, read by
	// parseCondition so a constraint is not mistaken for a call.
	if called isa error then return oneCondition(triples, text)
	if isGrouping(called.name) then return parseGrouping(triples, called)
	return oneCondition(triples, text)
end function

oneCondition = function(triples, text)
	"Reads one condition as the one-item body a rule takes."
	condition = parseCondition(triples, text)
	if condition isa error then return condition
	return [condition]
end function

isGrouping = function(name)
	"Says whether a name groups conditions rather than naming one; not is reserved for later."
	return ["and", "or", "not"].indexOf(name) != null
end function

parseGrouping = function(triples, called)
	"Reads a grouping call: and(...) flattens into the conditions it holds, and or(...) becomes one condition holding its alternatives."
	if called.name == "or" then
		if called.args.len == 0 then return err("or(...) needs at least one condition")
		alternatives = []
		for arg in called.args
			alternative = parseBody(triples, arg)
			if alternative isa error then return alternative
			alternatives.push(alternative)
		end for
		return [triples.Or.make(alternatives)]
	end if
	if called.name != "and" then
		return err(called.name + "(...) is not supported yet: join conditions with commas or and(...)")
	end if
	if called.args.len == 0 then return err("and(...) needs at least one condition")
	conditions = []
	for arg in called.args
		part = parseBody(triples, arg)
		if part isa error then return part
		conditions = conditions + part
	end for
	return conditions
end function

parseCondition = function(triples, text)
	"Reads one condition: a fact, or a '?x != ?y' constraint."
	text = trimSpace(text)
	differ = text.split("!=")
	if differ.len == 2 then
		left = termOf(triples, differ[0])
		right = termOf(triples, differ[1])
		if left == null or right == null then return err("expected '?x != ?y': " + text)
		return triples.NotEqual.make(left, right)
	end if
	return parseFact(triples, text)
end function

parseFact = function(triples, text)
	"Reads 'predicate(subject, object)' into a triple, or an error."
	called = parseCall(text)
	if called isa error then return called
	if called.args.len != 2 then
		return err("expected 'predicate(subject, object)': " + trimSpace(text))
	end if
	predicate = termOf(triples, called.name)
	subject = termOf(triples, called.args[0])
	object = termOf(triples, called.args[1])
	if predicate == null or subject == null or object == null then
		return err("a fact cannot have an empty field: " + trimSpace(text))
	end if
	return triples.SpoTriple.make(subject, predicate, object)
end function

// ── Reading a call ───────────────────────────────────────────────────────────

parseCall = function(text)
	"Reads 'name(arg, arg, ...)' into {name, args}, or an error when the text is not one call."
	text = trimSpace(text)
	openAt = text.indexOf("(")
	if openAt == null then return err("expected a call, 'predicate(subject, object)': " + text)
	name = trimSpace(text[:openAt])
	if name == "" then return err("expected a name before '(': " + text)
	depth = 0
	closeAt = null
	// The first '(' is the call's, so its matching ')' has to end the text: a stray
	// ')(' would otherwise be read as two calls and invent a triple.
	for at in range(openAt, text.len - 1)
		c = text[at]
		if c == "(" then
			depth = depth + 1
		else if c == ")" then
			depth = depth - 1
			if depth == 0 then
				closeAt = at
				break
			end if
		end if
	end for
	if closeAt == null then return err("unclosed '(' in " + text)
	if trimSpace(text[closeAt + 1:]) != "" then return err("unexpected text after ')': " + text)
	inner = text[openAt + 1:closeAt]
	if trimSpace(inner) == "" then return {"name": name, "args": []}
	return {"name": name, "args": splitTopLevel(inner)}
end function

splitTopLevel = function(text)
	"One trimmed piece per comma that is not inside a call, so a nested call stays whole."
	pieces = []
	current = ""
	depth = 0
	for c in text
		if c == "(" then
			depth = depth + 1
		else if c == ")" then
			depth = depth - 1
		else if c == "," and depth == 0 then
			pieces.push(trimSpace(current))
			current = ""
			continue
		end if
		current = current + c
	end for
	pieces.push(trimSpace(current))
	return pieces
end function

// ── Terms ────────────────────────────────────────────────────────────────────

termOf = function(triples, text)
	"One term: a ?x becomes a Var, a number reads as a number, anything else as its text."
	text = trimSpace(text)
	if text == "" then return null
	if text[:1] == "?" then return triples.Var.make(text)
	if isNumber(text) then return val(text)
	return text
end function

isNumber = function(text)
	"Says whether the text is a plain number, which val alone cannot tell: val of a name is 0."
	digits = 0
	dots = 0
	for at in range(0, text.len - 1)
		c = text[at]
		if c == "-" then
			if at != 0 then return false
		else if c == "." then
			dots = dots + 1
			if dots > 1 then return false
		else if c < "0" or c > "9" then
			return false
		else
			digits = digits + 1
		end if
	end for
	return digits > 0
end function

// ── Finding a data file ──────────────────────────────────────────────────────

dataPath = function(source, relative)
	"Finds a data file at relative, from the folder the module at source was loaded in."
	at = source.indexOf(" line ")
	if at != null then source = source[:at]
	folder = file.parent(source)
	entry = file.parent(shellArgs[0])
	// source is written relative to the entry script's own folder while the working
	// directory may be further up, so the module's folder is read both ways before the
	// working directory itself: main.ms and sample.ms live in src/, bench/ runs from
	// the root, and a script of your own may sit anywhere.
	folders = [folder]
	if entry != "" then folders.push(file.parent(file.child(entry, source)))
	folders.push("")
	for base in folders
		path = relative
		if base != "" then path = file.child(base, relative)
		if file.exists(path) then return path
	end for
	return relative
end function

// ── Lines ────────────────────────────────────────────────────────────────────

needsMore = function(text)
	"Says whether this much of an entry is unfinished: an open call, or an arrow at the end of it."
	if parenDepth(text) > 0 then return true
	return trimSpace(text)[-2:] == "=>"
end function

parenDepth = function(text)
	"How many '(' are still open at the end of the text."
	depth = 0
	for c in text
		if c == "(" then
			depth = depth + 1
		else if c == ")" then
			depth = depth - 1
		end if
	end for
	return depth
end function

stripComment = function(line)
	"One line without its // comment."
	at = line.indexOf("//")
	if at == null then return line
	return line[:at]
end function

trimSpace = function(text)
	"Trims leading and trailing spaces and tabs."
	start = 0
	while start < text.len
		if not isSpace(text[start]) then break
		start = start + 1
	end while
	last = text.len - 1
	while last >= start
		if not isSpace(text[last]) then break
		last = last - 1
	end while
	return text[start:last + 1]
end function

isSpace = function(c)
	return c == " " or c == char(9)
end function
