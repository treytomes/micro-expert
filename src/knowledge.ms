// knowledge.ms — the parser for the knowledge base's data files: data/facts.kb and
// data/rules.kb at the repo root.
//
// A fact is one triple on a line, predicate(subject, object):
//
//   is-parent-of(george, anna)
//
// A predicate is lower case, its sections joined by '-', each section letters and digits,
// and the first section starting with a letter: is-parent-of, has-1-child, married-to. The
// shape is checked with the one function that knows it, triples.ms's predicateProblem, and
// a name that is not one is refused here with its line; the same check closes the prompt's
// own door, since a typed line is read by the solver. Nothing in the search needs it - it
// is what lets an answer be said, since a sentence is the name with its dashes opened.
//
// A rule is a head and a body joined by '=>':
//
//   is-uncle-of(?x, ?y) => and(is-parent-of(?p, ?y), is-sibling-of(?x, ?p), has-gender(?x, male))
//
// The body is one condition, or a comma-delimited list of them, which means all of
// them must hold — the same thing and(...) says out loud. and(...) nests, and an
// entry may run on to the next line inside its parentheses, or after a rule's arrow.
//
// A condition is a fact, or a constraint: not-equal(?x, ?y) asks that two terms differ,
// equal(?n, 18) that they are the same one, and less-than-or-equal(?n, 18) compares two
// numbers rather than proving anything, so it holds only when both sides are numbers and
// text never passes for a zero. equal is the one that can bind: a side still unbound takes
// the other's value. Constraints are written as calls like every other condition. A value
// is a name, a number, or a ?x variable. Blank lines and lines starting with // are
// skipped, and an entry that will not parse names its line.
//
// or(...) holds a body's alternatives: any one of them may hold instead, and each
// alternative is a body of its own, so or(and(a, b), c) reads as it looks. not(...)
// holds a body that must have no proof, which is how a rule says what the facts do
// not: not(is-sibling-of(?x, ?q)) holds when nothing in the graph is ?x's sibling. It
// takes one condition, so not(a, b) is refused rather than read as not(and(a, b)).
//
// data/schema.kb is the third file, and it is a table rather than knowledge:
//
//   has-age(text, unique(number))
//
// one line per predicate, stored or derived, giving the type of each field in the order
// a fact writes them. A type is number, text, boolean, date, time, datetime, or a '|'
// list of the values allowed. The
// prompt checks what is typed, and what is asked, against it, so a fact no rule could
// ever reach is refused at the door; the solver never reads it, and a predicate it does
// not name is accepted as written.
//
// unique(...) around one field's type says that field holds at most one value for each
// of the other: has-birthdate(text, unique(date)) is one birthdate per person, not a list.
// It is a property of the pair rather than of the value - 24 fits an age wherever it
// stands - so it is checked against the facts already held, by the prompt before it
// stores one and by the facts loader over the whole file. A predicate a rule concludes
// has no place where a fact is added, so unique(...) on a derived predicate is refused
// when the program starts instead of loaded and quietly left unenforced.
//
// The same file format is written back by the prompt's /save-* commands, through
// factsLines, rulesLines and schemaLines, so a file a session saves is one it can load.
//
// Nothing here imports triples.ms. The parsers are handed the caller's copy, so the
// terms they build are the ones the caller's solver recognizes, and they return the
// pieces Rule.make takes, so they never need the Rule class either.
//
// The date, time and datetime types themselves are datetimes.ms's. This file imports it for
// the one check that has to read a text as a date; a caller that wants the value object
// reaches it through schema.receive, which hands the reader on.

import "datetimes"

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

loadFacts = function(triples, source, relative, types=null)
	"Reads the facts file at relative from the module at source and returns its triples, or an error."
	return loadFactsAt(triples, resolvePath(relative, source), types)
end function

loadFactsAt = function(triples, path, types=null)
	"Reads the facts file at path and returns its triples, or an error; types, when given, refuses a file that stores one pair twice."
	lines = readLines(path)
	if lines isa error then return lines
	facts = parseFacts(triples, lines)
	if facts isa error then return err(file.name(path) + " " + facts.message)
	// Two lines can each fit the schema and still be one too many for a unique(...) field,
	// since what that field limits is the pair, not the value, so the file is read as a
	// whole rather than line by line.
	repeated = uniqueRepeats(types, facts)
	if repeated isa error then return err(file.name(path) + " " + repeated.message)
	return facts
end function

loadSchema = function(source, relative)
	"Reads the schema file at relative from the module at source and returns its field types, or an error."
	return loadSchemaAt(resolvePath(relative, source))
end function

loadSchemaAt = function(path)
	"Reads the schema file at path and returns its field types, or an error."
	lines = readLines(path)
	if lines isa error then return lines
	types = parseSchema(lines)
	if types isa error then return err(file.name(path) + " " + types.message)
	return types
end function

parseSchema = function(lines)
	"Reads the lines of a schema document into {predicate: [field type, field type]}, or an error naming the line."
	types = {}
	for entry in entries(lines)
		parsed = parseSchemaEntry(entry.text)
		if parsed isa error then return err("line " + entry.line + ": " + parsed.message)
		types[parsed.predicate] = parsed.types
	end for
	return types
end function

parseSchemaEntry = function(text)
	"Reads 'predicate(field type, field type)' into {predicate, types}, or an error."
	called = parseCall(text)
	if called isa error then return called
	if called.args.len != 2 then
		return err("expected 'predicate(field type, field type)': " + trimSpace(text))
	end if
	types = []
	for arg in called.args
		type = trimSpace(arg)
		if type == "" then return err("a field type cannot be empty: " + trimSpace(text))
		// The field is kept as it is written, unique(...) and all, so schemaLines writes back
		// the line this read; what the wrapper means is read off it where it is used.
		checked = checkedFieldType(type)
		if checked isa error then return err(checked.message + ": " + trimSpace(text))
		types.push(type)
	end for
	return {"predicate": called.name, "types": types}
end function

// ── One field's type ─────────────────────────────────────────────────────────
// A field type is a type, or unique(...) around one. The wrapped form is kept as text
// rather than taken apart into a record, because the file is the form it has to be
// written back in and every reader but two wants the type alone.

isUniqueField = function(type)
	"Says whether a field type is written unique(...), so the field holds at most one value per subject."
	if type == null then return false
	if type.len <= 8 then return false
	return type[:7] == "unique(" and type[-1:] == ")"
end function

plainType = function(type)
	"The type a field is checked against, with a unique(...) wrapper taken off."
	if not isUniqueField(type) then return type
	return trimSpace(type[7:-1])
end function

checkedFieldType = function(type)
	"Says a field type is a whole one, or what is wrong with a unique(...) that wraps too much."
	if type[:7] != "unique(" then return true
	if type[-1:] != ")" then return err("unique(...) needs a closing ')'")
	inner = trimSpace(type[7:-1])
	if inner == "" then return err("unique(...) needs one field type")
	// One field, so nothing nests inside it: unique(unique(number)) asks the same question
	// twice and a call in its place asks a different one.
	if inner.indexOf("(") != null or inner.indexOf(")") != null then
		return err("unique(...) wraps one field type, not another call")
	end if
	if inner.indexOf(",") != null then return err("unique(...) wraps one field type")
	return true
end function

schemaMisfit = function(types, triple)
	"How the triple misses the schema, as 'the object should be a number', or null when it fits."
	if types == null then return null
	if types.hasIndex(triple.predicate) == 0 then return null
	fields = types[triple.predicate]
	problem = fieldProblem("subject", triple.subject, fields[0])
	if problem != null then return problem
	return fieldProblem("object", triple.object, fields[1])
end function

fieldProblem = function(slot, term, type)
	"Says how one field misses its type, or null when it fits."
	if fieldFits(term, type) then return null
	return "the " + slot + " should be " + typeText(type)
end function

fieldFits = function(term, type)
	"Says whether one field fits one type; a variable fits any, since it is not a value yet."
	if not (term isa number) and not (term isa string) then return true
	// unique(...) says how many, not what, so it is not part of what a value has to be.
	type = plainType(type)
	if type == "number" then return term isa number
	if type == "text" then return term isa string
	// A boolean is the word true or the word false, since that is how one is written in
	// a fact; MiniScript's own true and false are the numbers 1 and 0, so they belong to
	// number rather than here.
	if type == "boolean" then return term == "true" or term == "false"
	// A date, time or datetime is text in one shape, and the reader that builds the object
	// is what says whether it is one, so the check and the object agree.
	if datetimes.dateTypes.indexOf(type) != null then return not (datetimes.receive(term, type) isa error)
	return type.split("|").indexOf(term) != null
end function

typeText = function(type)
	"How one type reads in a message: 'a number', 'text', 'true or false' or 'one of: male, female'."
	type = plainType(type)
	if type == "number" then return "a number"
	if type == "text" then return "text"
	if type == "boolean" then return "true or false"
	if type == "date" then return "a date"
	if type == "time" then return "a time"
	if type == "datetime" then return "a date and time"
	return "one of: " + type.split("|").join(", ")
end function

// ── One value per subject ────────────────────────────────────────────────────
// unique(...) is the schema's one statement about how many values a pair may take, and it
// is the one check that a single term cannot answer: a value that fits its type can still
// be the second one for this subject. So it is checked against the facts already held,
// not by fieldFits, and the subject slot is read first, the way schemaMisfit reads it, so
// a fact that breaks both names the first.

sameValue = function(a, b)
	"Says whether two fields hold the same value; a variable is not a value, so it matches nothing."
	if a isa number then return (b isa number) and a == b
	if a isa string then return (b isa string) and a == b
	return false
end function

uniqueTaken = function(types, facts, triple)
	"The fact a triple would take the place of, as {at, held, message}, or null when the pair is free."
	if types == null then return null
	if not (triple.predicate isa string) then return null
	if types.hasIndex(triple.predicate) == 0 then return null
	// range(0, -1) counts down here rather than being empty, so the empty case is said out
	// loud instead of being asked of the loop.
	if facts.len == 0 then return null
	fields = types[triple.predicate]
	for slot in [0, 1]
		if not isUniqueField(fields[slot]) then continue
		for at in range(0, facts.len - 1)
			known = facts[at]
			// Only another fact of the same predicate can stand in this one's place, and the two
			// have to agree in the field that is not the unique one: the subject limits a unique
			// object, and the object limits a unique subject.
			if not (known.predicate isa string) then continue
			if known.predicate != triple.predicate then continue
			if slot == 1 then
				if not sameValue(known.subject, triple.subject) then continue
				// The same value again is the fact already held, which the caller reports in its
				// own words rather than as a value to take the place of.
				if sameValue(known.object, triple.object) then continue
				return {"at": at, "held": known,
					"message": "the object is already taken: " + known.text}
			end if
			if not sameValue(known.object, triple.object) then continue
			if sameValue(known.subject, triple.subject) then continue
			return {"at": at, "held": known, "message": "the subject is already taken: " + known.text}
		end for
	end for
	return null
end function

uniqueClash = function(types, facts, triple)
	"How a fact would give a unique(...) field a second value, naming the fact that holds the first, or null when it would not."
	taken = uniqueTaken(types, facts, triple)
	if taken == null then return null
	return taken.message
end function

uniqueRepeats = function(types, facts)
	"Reads a whole file for a unique(...) field that two facts fill, as an error naming the second, or null when no pair repeats."
	if types == null then return null
	if facts.len == 0 then return null
	// Each fact is held against the ones before it, so it is never compared with itself,
	// and the error names the line a reader would delete.
	for at in range(0, facts.len - 1)
		clash = uniqueClash(types, facts[:at], facts[at])
		if clash != null then return err(facts[at].text + ": " + clash)
	end for
	return null
end function

derivedUniques = function(types, rules)
	"Says which unique(...) a rule's head leaves unenforceable, as an error naming it, or null when every one is on a stored predicate."
	if types == null then return null
	for rule in rules
		name = rule.head.predicate
		if not (name isa string) then continue
		if types.hasIndex(name) == 0 then continue
		for slot in [0, 1]
			if isUniqueField(types[name][slot]) then
				return err(name + " is concluded by a rule, so a second value is never added to be refused: " +
					"take unique(...) off its schema line")
			end if
		end for
	end for
	return null
end function

loadRules = function(triples, source, relative)
	"Reads the rules file at relative from the module at source and returns its {head, body} pieces, or an error."
	return loadRulesAt(triples, resolvePath(relative, source))
end function

loadRulesAt = function(triples, path)
	"Reads the rules file at path and returns its {head, body} pieces, or an error."
	lines = readLines(path)
	if lines isa error then return lines
	pieces = parseRules(triples, lines)
	if pieces isa error then return err(file.name(path) + " " + pieces.message)
	return pieces
end function

readLines = function(path)
	"The lines of the data file at path, or an error naming it."
	lines = file.readLines(path)
	if lines isa error then return err(file.name(path) + ": could not read " + path + ": " + lines.message)
	return lines
end function

// ── Writing a data file ──────────────────────────────────────────────────────
// The prompt's /save-* commands write what it holds through these, in the format this
// module reads back: one fact per line, one rule per line as 'head => body', and one
// predicate per line for the schema. A rule's body is written as the comma list
// Rule.text prints, which is the implied and(...) the file may have spelled out.

factsLines = function(facts)
	"One line per fact, in the facts-file form."
	lines = []
	for fact in facts
		lines.push(fact.text)
	end for
	return lines
end function

rulesLines = function(rules)
	"One line per rule, in the rules-file form 'head => conditions'."
	lines = []
	for rule in rules
		conditions = []
		for condition in rule.body
			conditions.push(condition.text)
		end for
		lines.push(rule.head.text + " => " + conditions.join(", "))
	end for
	return lines
end function

schemaLines = function(types)
	"One line per predicate, in the schema-file form 'predicate(field type, field type)'."
	lines = []
	if types == null then return lines
	for predicate in types.indexes
		lines.push(predicate + "(" + types[predicate].join(", ") + ")")
	end for
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
	"Reads a body: one condition, a comma-delimited list of them, or and(...), or(...) or not(...) around either."
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
	"Says whether a name groups conditions rather than naming one."
	return ["and", "or", "not"].indexOf(name) != null
end function

parseGrouping = function(triples, called)
	"Reads a grouping call: and(...) flattens into its conditions, or(...) becomes one condition holding alternatives, and not(...) one condition holding a body that must not hold."
	if called.name == "not" then
		// One body, so several conditions have to be joined out loud: not(a, b) would
		// leave the reader guessing whether it negates either or both.
		if called.args.len != 1 then
			return err("not(...) takes one condition; write not(and(a, b)) for several")
		end if
		body = parseBody(triples, called.args[0])
		if body isa error then return body
		return [triples.Not.make(body)]
	end if
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
	"Reads one condition: a fact, or a constraint call such as not-equal(?x, ?y), built by the caller's triples module."
	constraint = triples.constraintOf(trimSpace(text))
	if constraint != null then return constraint
	return parseFact(triples, text)
end function

parseFact = function(triples, text)
	"Reads 'predicate(subject, object)' into a triple, or an error."
	called = parseCall(text)
	if called isa error then return called
	if called.args.len != 2 then
		return err("expected 'predicate(subject, object)': " + trimSpace(text))
	end if
	// The name rule is the solver's, because the sentence a result reads as is built from
	// it; a file is held to it here, so a name no result could say never gets stored.
	problem = triples.predicateProblem(called.name)
	if problem != null then return err(problem + ": " + trimSpace(text))
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
	"One term: the caller's reading of it, so a number is a number here as it is at the prompt."
	text = trimSpace(text)
	if text == "" then return null
	return triples.termOf(text)
end function

// ── Finding a data file ──────────────────────────────────────────────────────

resolvePath = function(relative, source=null)
	"Where a data path is read or written: as given when it is there, else found from the module or the entry script."
	if source == null then source = info(@resolvePath).sourceLoc
	path = expandHome(relative)
	if file.exists(path) then return path
	return dataPath(source, path)
end function

expandHome = function(path)
	"A path with a leading ~/ replaced by the user's home folder, when one is set."
	if path.len < 2 then return path
	if path[:2] != "~/" and path[:2] != "~\\" then return path
	home = null
	if env.hasIndex("HOME") then home = env["HOME"]
	if home == null and env.hasIndex("USERPROFILE") then home = env["USERPROFILE"]
	if home == null then return path
	return file.child(home, path[2:])
end function

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

withExtension = function(path)
	"Adds .kb to a name that has no extension, so /save-facts family writes family.kb."
	if path == "" then return path
	if file.name(path).indexOf(".") == null then return path + ".kb"
	return path
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
