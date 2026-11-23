// mermaid.ms — a knowledge base's facts as a Mermaid flowchart, or as a picture of it.
//
// A facts file is a graph already, so nothing here decides what a fact means: it decides
// only what shape to draw it as. A fact whose object field the schema types as text names
// another entity - is-parent-of, married-to - so it is an edge between two nodes. Any other
// object is a value that belongs to its subject - has-gender's male|female, has-birthdate's
// date, has-age's number - so it goes on that subject's label rather than standing in the
// picture as a node called "male":
//
//   import "mermaid"
//   for line in globals["mermaid"].build(facts, types, rules)   // Mermaid text
//       print line
//   end for
//   for line in globals["mermaid"].svg(facts, types, rules)     // the same, as SVG
//       print line
//   end for
//
// build answers the flowchart a renderer outside the program draws: a Markdown fence on
// GitHub, a docs site, the Mermaid preview in VS Code. svg answers a whole SVG document of
// the same diagram, laid out here rather than by Mermaid, so the picture needs no renderer
// installed and no network. Neither checks that a renderer accepts what it wrote - the suite
// checks the lines, not the picture.
//
// A predicate the schema does not name is drawn as an edge, the way the schema takes an
// unknown predicate as it is written: a fact nobody typed the type of still relates two
// things. types may be null, which reads every fact that way - a session that loaded no
// schema has nothing better to go on.
//
// rules, when they are given, are what say a relation reads the same both ways. A rule such as
//
//   married-to(?y, ?x) => married-to(?x, ?y)
//
// is the knowledge base saying so, so a fact of that predicate is drawn with a plain link
// (---), and in the picture with no arrowhead: facts.kb stores a marriage once, in one
// direction, and the reverse is what the rule adds. Nothing is undirected without a rule, so
// a predicate with no rule around it keeps its arrow, and a caller with no rules passes none.
//
// A fact that still holds a variable is not drawn: a session holds ground facts, and a Var is
// not a node's name, so the fact is skipped rather than given a made-up one.
//
// Nothing here imports triples.ms. A fact is read for its .subject, .predicate and .object,
// and those are strings or numbers whatever class built them, so the solver's copy problem -
// two copies of a class never agree - cannot reach this module. A rule is read the same way:
// its .head and .body, and the .text of a variable, which is "?x" whether or not the class
// that built it is this module's.

// The brackets a node's label sits in are made rather than quoted: "[" after a '+' reads as an
// index to this interpreter.
quote = char(34)
openBracket = char(91)
closeBracket = char(93)

// The picture's grid: one row per generation, one column per node in a row.
boxWidth = 180
boxHeight = 68
columnStep = 220
rowStep = 120
margin = 40
// A label's baseline sits this far above its line, so the line reads as broken by the words.
labelRise = 5
// The box a label's text covers stands this far above its baseline and is this tall: the two
// numbers labelRect plans with, so the placement reasons about the same box the halo covers.
labelAbove = 9
labelHeight = 12
// Air between a box and a label written under its row, and the step from one such label to a
// second one in the same corridor.
labelGap = 10
corridorStep = 20

build = function(facts, types=null, rules=null)
	"One Mermaid flowchart of a fact list: an edge per relation, a node per entity, and every other value on its subject's label."
	drawing = shape(facts, types, rules)
	lines = ["flowchart TD"]
	for name in drawing.nodes
		lines.push(nodeLine(idFor(drawing, name), labelOf(drawing, name)))
	end for
	for edge in drawing.edges
		arrow = "-->"
		if drawing.symmetric.indexOf(edge.predicate) != null then arrow = "---"
		lines.push("  " + idFor(drawing, edge.subject) + " " + arrow + "|" +
			edgeText(edge.predicate) + "| " + idFor(drawing, edge.object))
	end for
	return lines
end function

svg = function(facts, types=null, rules=null)
	"The same diagram as one SVG document, a line at a time, to be written to a .svg file."
	return svgLines(shape(facts, types, rules))
end function

// ── What the diagram is made of ─────────────────────────────────────────────

shape = function(facts, types=null, rules=null)
	"What both renderings draw: the nodes in the order the facts first mention them, the relations between them, the values on each, and the relations the rules give both ways."
	drawing = blank()
	for fact in facts
		subject = termValue(fact.subject)
		predicate = termValue(fact.predicate)
		object = termValue(fact.object)
		if subject == null or predicate == null or object == null then continue
		addNode(drawing, subject)
		if isEntity(types, predicate) then
			addNode(drawing, object)
			drawing.edges.push({"subject": subject, "predicate": predicate, "object": object})
		else
			// The values of one subject stay in the order the facts hold them, so a label
			// reads the way /facts lists: gender, then birthdate, then whatever follows.
			if drawing.attributes.hasIndex(subject) == 0 then drawing.attributes[subject] = []
			drawing.attributes[subject].push(object)
		end if
	end for
	drawing.symmetric = symmetricNames(rules)
	return drawing
end function

// ── What the schema says a field is ─────────────────────────────────────────
// A field type is read the way knowledge.ms reads it, unique(...) and all: the wrapper says
// how many values a pair takes, not what a value has to be, so it is not part of the shape.
// The schema reader refuses a unique(...) it cannot read, so what arrives here is well formed,
// and the suite pins this against the reader's own plainType over data/schema.kb.

plainType = function(type)
	"One field type with a unique(...) wrapper taken off, as the schema's reader reads it."
	if type[:7] != "unique(" then return type
	return trimmed(type[7:-1])
end function

isEntity = function(types, predicate)
	"Says whether a fact of this predicate relates two things, rather than giving its subject a value."
	if types == null then return true
	if types.hasIndex(predicate) == 0 then return true
	fields = types[predicate]
	if not (fields isa list) or fields.len < 2 then return true
	return plainType(fields[1]) == "text"
end function

// ── The relations that read both ways ───────────────────────────────────────
// A rule whose head is its own one condition with the fields swapped is the only statement in
// this format that says a relation is symmetric, so it is the one looked for. Everything else
// keeps its arrow: a rule about one person, a body of several conditions, and a constraint are
// all read as saying something narrower, and an arrow is never wrong - it is the stored
// direction of a fact that was stored in one.

symmetricNames = function(rules)
	"The predicates a rule proves both ways round, as a list of names; empty for no rules."
	names = []
	if rules == null then return names
	for rule in rules
		shown = symmetricWay(rule)
		if shown != null and names.indexOf(shown) == null then names.push(shown)
	end for
	return names
end function

symmetricWay = function(rule)
	"The predicate this rule says the same both ways, or null when it says anything else."
	if not rule.hasIndex("head") then return null
	if not (rule.head.predicate isa string) then return null
	if rule.body.len != 1 then return null
	condition = rule.body[0]
	if not condition.hasIndex("predicate") then return null
	if condition.predicate != rule.head.predicate then return null
	first = rule.head.subject
	second = rule.head.object
	// Both fields of the head have to be variables, or the rule says something about one
	// person rather than about the relation.
	if (first isa string) or (first isa number) then return null
	if (second isa string) or (second isa number) then return null
	if first.text != condition.object.text then return null
	if second.text != condition.subject.text then return null
	return rule.head.predicate
end function

// ── Nodes, ids and labels ───────────────────────────────────────────────────
// A renderer takes an id and a label, and the two are not the same string: the label is
// whatever a reader should see, and the id is what the edges name, so it has to be a shape
// the renderer accepts and no two nodes share. Names arrive from the facts, so both are
// worked out here rather than trusted.

blank = function()
	"The state one diagram is built in: the nodes in the order they first appear, the edges, the values waiting for a label, and the relations the rules give both ways."
	return {"nodes": [], "edges": [], "attributes": {}, "ids": {}, "used": {}, "symmetric": []}
end function

addNode = function(drawing, name)
	"A node, in the order the facts first mention it."
	if drawing.nodes.indexOf(name) == null then drawing.nodes.push(name)
end function

idFor = function(drawing, name)
	"The renderer's id for a node: the name spelled as one, and numbered apart if two names spell the same."
	if drawing.ids.hasIndex(name) then return drawing.ids[name]
	base = sanitized(name)
	id = base
	suffix = 2
	while drawing.used.hasIndex(id)
		id = base + str(suffix)
		suffix = suffix + 1
	end while
	drawing.used[id] = name
	drawing.ids[name] = id
	return id
end function

sanitized = function(name)
	"A name as a renderer's id: anything that is not a letter or digit becomes an underscore, and a leading digit gets an 'n_' before it."
	id = ""
	for c in name
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") then
			id = id + c
		else
			id = id + "_"
		end if
	end for
	if id == "" then return "n"
	if id[0] >= "0" and id[0] <= "9" then return "n_" + id
	return id
end function

labelOf = function(drawing, name)
	"The text a node shows: its name capitalized, and every value the facts hang on it after it."
	shown = capitalized(name)
	if drawing.attributes.hasIndex(name) == 0 then return mermaidEscaped(shown)
	return mermaidEscaped(shown + "<br/>" + drawing.attributes[name].join(" · "))
end function

capitalized = function(name)
	"A name as a label opens: its first letter upper case, the rest as the fact holds it."
	if name.len == 0 then return name
	return name[:1].upper + name[1:]
end function

mermaidEscaped = function(text)
	"The text as a quoted Mermaid label takes it: a double quote would end the label, so it is written as #quot;."
	out = ""
	for c in text
		if c == quote then
			out = out + "#quot;"
		else
			out = out + c
		end if
	end for
	return out
end function

nodeLine = function(id, label)
	"One node's line: the id, and the label in brackets and quotes."
	return "  " + id + openBracket + quote + label + quote + closeBracket
end function

edgeText = function(predicate)
	"A predicate as an edge label, with its dashes opened to spaces so it reads as words. A predicate name holds no quote to escape."
	return predicate.split("-").join(" ")
end function

// ── The same diagram as a picture ───────────────────────────────────────────
// Mermaid is text for a renderer; this is the picture itself, so it has to be laid out here.
// The layout is the one a family tree wants and any graph tolerates: one row per generation,
// rows centered under each other, a node's generation counted one step below every node a
// one-way relation points from. A symmetric relation is not a generation - a marriage does not
// put one spouse below the other - so it is left out of the counting and drawn as a plain line.
//
// Every line is drawn from box to box and the boxes are painted after it, so a line runs under
// the node it arrives at and only its arrowhead shows at the edge. Attributes are written with
// single quotes, since this interpreter's strings have no escape for a double one.
//
// The document is written in three passes - every line, then every box, then every label - so
// what a reader reads is the last thing painted. A label drawn as its own line was written
// could be crossed by any relation drawn after it, which is the one thing a label exists to
// avoid.
//
// The three greys are a hierarchy rather than a palette: the relations are the lightest thing on
// the page so they read as the scaffolding, their labels are the darkest so they stay legible
// where lines cross, and a node's own border sits between the two so a box is never mistaken for
// an edge.

svgLines = function(drawing)
	"One SVG document of a diagram, a line at a time."
	place = layout(drawing)
	width = place.width
	height = place.height
	lines = ["<svg xmlns='http://www.w3.org/2000/svg' width='" + width + "' height='" + height +
		"' viewBox='0 0 " + width + " " + height + "' font-family='system-ui, sans-serif'>"]
	lines.push("  <defs><marker id='arrow' viewBox='0 0 10 10' refX='9' refY='5' markerWidth='6' markerHeight='6' orient='auto-start-reverse'><path d='M 0 0 L 10 5 L 0 10 z' fill='#9ca3af'/></marker></defs>")
	lines.push("  <rect x='0' y='0' width='" + width + "' height='" + height + "' fill='#ffffff'/>")
	// Where a label may not go: a node's box, with a little margin so a label never touches the
	// border it is near, and every label already placed, so two relations do not write over
	// each other where their lines cross.
	boxes = []
	for name in drawing.nodes
		box = place.at[name]
		boxes.push({"x": box.x - 4, "y": box.y - 4, "width": boxWidth + 8, "height": boxHeight + 8})
	end for
	placed = []
	labels = []
	for edge in drawing.edges
		from = place.at[edge.subject]
		to = place.at[edge.object]
		start = edgeStart(from, to)
		finish = edgeEnd(from, to)
		marker = ""
		if drawing.symmetric.indexOf(edge.predicate) == null then marker = " marker-end='url(#arrow)'"
		lines.push("  <line x1='" + start.x + "' y1='" + start.y + "' x2='" + finish.x +
			"' y2='" + finish.y + "' stroke='#9ca3af' stroke-width='1.5'" + marker + "/>")
		text = xml(edgeText(edge.predicate))
		spot = labelSpot(start, finish, text, boxes, placed)
		placed.push(spot.rect)
		// Held back rather than written here: every label is drawn once every line and every box
		// is on the page, so a relation cannot run across another relation's words.
		labels.push("  <text x='" + spot.x + "' y='" + spot.y + "' text-anchor='middle' font-size='10'" +
			" paint-order='stroke' stroke='#ffffff' stroke-width='5' stroke-linejoin='round'" +
			" fill='#1f2937'>" + text + "</text>")
	end for
	for name in drawing.nodes
		box = place.at[name]
		center = box.x + floor(boxWidth / 2)
		lines.push("  <rect x='" + box.x + "' y='" + box.y + "' width='" + boxWidth +
			"' height='" + boxHeight + "' rx='8' fill='#eef2ff' stroke='#4b5563'/>")
		lines.push("  <text x='" + center + "' y='" + (box.y + 28) +
			"' text-anchor='middle' font-size='14' font-weight='600' fill='#111827'>" +
			xml(capitalized(name)) + "</text>")
		if drawing.attributes.hasIndex(name) then
			lines.push("  <text x='" + center + "' y='" + (box.y + 47) +
				"' text-anchor='middle' font-size='10' fill='#4b5563'>" +
				xml(drawing.attributes[name].join(" · ")) + "</text>")
		end if
	end for
	// The labels last, above the lines and the boxes both: what is written is what is read,
	// whatever the geometry underneath is doing. The white halo then masks the line each label
	// sits on, so the line breaks around the words instead of running through them.
	for label in labels
		lines.push(label)
	end for
	lines.push("</svg>")
	return lines
end function

layout = function(drawing)
	"Where each node's box sits, and how big the page has to be."
	rank = assignRanks(drawing)
	rows = {}
	maxRank = 0
	for name in drawing.nodes
		if rows.hasIndex(rank[name]) == 0 then rows[rank[name]] = []
		rows[rank[name]].push(name)
		if rank[name] > maxRank then maxRank = rank[name]
	end for
	columns = 1
	for at in rows.indexes
		if rows[at].len > columns then columns = rows[at].len
	end for
	place = {}
	for at in rows.indexes
		row = rows[at]
		startX = margin + floor((columns - row.len) * columnStep / 2)
		for index in range(0, row.len - 1)
			place[row[index]] = {"x": startX + index * columnStep, "y": margin + at * rowStep}
		end for
	end for
	width = margin * 2 + columns * columnStep - (columnStep - boxWidth)
	height = margin * 2 + (maxRank + 1) * rowStep - (rowStep - boxHeight)
	return {"at": place, "width": width, "height": height}
end function

assignRanks = function(drawing)
	"How far down the picture each node sits: one step below every node a one-way relation points from, so a parent stands above a child."
	rank = {}
	for name in drawing.nodes
		rank[name] = 0
	end for
	// One pass per node settles a chain of any length. A relation that runs back up the
	// picture cannot be a generation, so the counting stops at the number of nodes: a cycle in
	// the data leaves the ranks it settled on rather than growing one without end.
	passes = drawing.nodes.len
	while passes > 0
		moved = 0
		for edge in drawing.edges
			if drawing.symmetric.indexOf(edge.predicate) != null then continue
			wanted = rank[edge.subject] + 1
			if wanted > rank[edge.object] and wanted < drawing.nodes.len then
				rank[edge.object] = wanted
				moved = 1
			end if
		end for
		passes = passes - 1
		if moved == 0 then break
	end while
	return rank
end function

labelSpot = function(start, finish, text, boxes, placed)
	"Where an edge's label goes: along its line, at the first place no box covers and no label is written over - and never inside a box, which is the one thing that hides a label outright."
	shares = [0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8, 0.1, 0.9]
	// A label may sit a little above or below its line, which is another way past a box the line
	// runs into without leaving the part of the picture the line belongs to.
	lifts = [0, -14, 14]
	// Two boxes in one row have only the gap between them to be written in, and a label is wider
	// than that gap - so it goes into the corridor under the row. Two places there are tried
	// before the corridor above the row: a label above its own row reads as belonging to
	// whatever is above it, so it is the last resort rather than the second choice. Clearing the
	// box takes the half-height to its bottom, the air below it, and the rise back to the
	// baseline; the second place is one line further down, still inside the space between rows.
	if start.y == finish.y then
		below = floor(boxHeight / 2) + labelGap + labelAbove + labelRise
		shares = [0.5]
		lifts = [below, below + corridorStep, -below]
	end if
	crowded = null
	for lift in lifts
		for share in shares
			x = start.x + (finish.x - start.x) * share
			y = start.y + (finish.y - start.y) * share - labelRise + lift
			rect = labelRect(x, y, text)
			if not uncovered(rect, boxes) then continue
			spot = {"x": floor(x), "y": floor(y), "rect": rect}
			if uncovered(rect, placed) then return spot
			// Off the boxes but on another label: kept for the case where nothing along the line
			// is free of both, since two labels meeting is legible and one under a box is not.
			if crowded == null then crowded = spot
		end for
	end for
	if crowded != null then return crowded
	// Nothing along the line is off the boxes at all, which is a line drawn straight through a
	// generation. The middle is written in and the box is left to paint over it.
	x = (start.x + finish.x) / 2
	y = (start.y + finish.y) / 2 - labelRise
	return {"x": floor(x), "y": floor(y), "rect": labelRect(x, y, text)}
end function

labelRect = function(x, y, text)
	"The rectangle a label covers, from the baseline it is drawn at, so it can be kept clear of what is already there; five pixels a character is wide enough for 10px system-ui."
	width = text.len * 5 + 6
	return {"x": floor(x - width / 2), "y": floor(y - labelAbove), "width": width, "height": labelHeight}
end function

uncovered = function(rect, taken)
	"Says whether a rectangle is clear of everything already drawn: a box, or another label."
	for other in taken
		if touching(rect, other) then return false
	end for
	return true
end function

touching = function(a, b)
	"Says whether two rectangles meet, with a margin, so two labels that would nearly touch are moved apart too."
	if a.x + a.width + 2 < b.x then return false
	if b.x + b.width + 2 < a.x then return false
	if a.y + a.height + 2 < b.y then return false
	if b.y + b.height + 2 < a.y then return false
	return true
end function

edgeStart = function(from, to)
	"The point a line leaves a box at: the side facing the box it is going to."
	center = from.y + floor(boxHeight / 2)
	if to.y > from.y then return {"x": from.x + floor(boxWidth / 2), "y": from.y + boxHeight}
	if to.y < from.y then return {"x": from.x + floor(boxWidth / 2), "y": from.y}
	if to.x >= from.x then return {"x": from.x + boxWidth, "y": center}
	return {"x": from.x, "y": center}
end function

edgeEnd = function(from, to)
	"The point a line reaches a box at: the side facing where it came from, which is where a box painted over the line leaves the arrowhead showing."
	center = to.y + floor(boxHeight / 2)
	if from.y < to.y then return {"x": to.x + floor(boxWidth / 2), "y": to.y}
	if from.y > to.y then return {"x": to.x + floor(boxWidth / 2), "y": to.y + boxHeight}
	if from.x <= to.x then return {"x": to.x, "y": center}
	return {"x": to.x + boxWidth, "y": center}
end function

xml = function(text)
	"The text as XML content or a single-quoted attribute takes it: the four characters that would end it are written as entity references."
	out = ""
	for c in text
		if c == "&" then
			out = out + "&amp;"
		else if c == "<" then
			out = out + "&lt;"
		else if c == ">" then
			out = out + "&gt;"
		else if c == quote then
			out = out + "&quot;"
		else if c == "'" then
			out = out + "&apos;"
		else
			out = out + c
		end if
	end for
	return out
end function

// ── Terms ───────────────────────────────────────────────────────────────────

termValue = function(term)
	"A fact's field as the text a diagram writes, or null when it is not a value at all."
	if term isa number then return str(term)
	if term isa string then return term
	return null
end function

trimmed = function(text)
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
