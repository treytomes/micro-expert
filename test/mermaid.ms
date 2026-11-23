// Cases for the Mermaid exporter: what the schema makes an edge and what it makes a value on
// a node, the ids and labels a renderer is handed, and the diagram the shipped family draws.

run = function(t, mermaid, knowledge, schemaLoader, factsLoader, rulesLoader, h)
	"Checks the flowchart a fact list becomes, and that the schema and the rules are read the way their own readers read them."
	spo = function(s, p, o)
		return t.SpoTriple.make(s, p, o)
	end function
	has = function(lines, text)
		"Whether the diagram holds this line exactly."
		return lines.indexOf(text) != null
	end function
	holds = function(lines, piece)
		"Whether any line holds this piece of text."
		for line in lines
			if line.indexOf(piece) != null then return true
		end for
		return false
	end function
	node = function(id, label)
		"One node's line, as the diagram writes it."
		return "  " + id + char(91) + char(34) + label + char(34) + char(93)
	end function
	lineY = function(lines, text)
		"The y coordinate of the picture's text for this node, or null when it is not in the picture."
		for line in lines
			if line.indexOf(">" + text + "<") != null then
				at = line.indexOf("y='")
				return val(line[at + 3:].split("'")[0])
			end if
		end for
		return null
	end function

	types = {
		"is-parent-of": ["text", "text"],
		"married-to": ["text", "text"],
		"has-gender": ["text", "unique(male|female)"],
		"has-birthdate": ["text", "unique(date)"],
		"has-age": ["text", "number"],
	}

	// ── An edge, and a value on a node ───────────────────────────────────────

	family = [spo("bill", "is-parent-of", "tim"), spo("bill", "has-gender", "male")]
	drawn = mermaid.build(family, types)
	h.check("a flowchart starts the diagram", drawn[0] == "flowchart TD")
	h.check("a text object is another node", has(drawn, node("tim", "Tim")))
	h.check("a relation is an edge between its two nodes",
		has(drawn, "  bill -->|is parent of| tim"))
	h.check("a value the schema does not type as text goes on its subject's label",
		has(drawn, node("bill", "Bill<br/>male")))
	h.check("a value is not a node of its own", not has(drawn, node("male", "Male")))
	h.check("the diagram is the header, two nodes and one edge", drawn.len == 4)

	// unique(...) says how many values a pair takes, not what a value is, so a field it wraps
	// is still read by the type inside it - here an enumeration, there a date, there a number.
	h.check("a date is a value too",
		has(mermaid.build([spo("bill", "has-birthdate", "1972-01-30")], types),
			node("bill", "Bill<br/>1972-01-30")))

	both = mermaid.build([spo("bill", "has-gender", "male"), spo("bill", "has-birthdate", "1972-01-30")], types)
	h.check("two values sit on one label in the order the facts hold them",
		has(both, node("bill", "Bill<br/>male · 1972-01-30")))

	h.check("a number is written as the fact stores it",
		has(mermaid.build([spo("bill", "has-age", 54)], types), node("bill", "Bill<br/>54")))

	// ── What the schema does not name ────────────────────────────────────────

	h.check("a predicate the schema does not name is an edge",
		has(mermaid.build([spo("bill", "likes", "tim")], types), "  bill -->|likes| tim"))

	untyped = mermaid.build([spo("bill", "has-gender", "male")], null)
	h.check("no schema draws every object as a node",
		has(untyped, node("male", "Male")) and has(untyped, "  bill -->|has gender| male"))

	// ── Ids a renderer takes ─────────────────────────────────────────────────

	h.check("a name with a space is an id with an underscore",
		has(mermaid.build([spo("New York", "is-parent-of", "tim")], types),
			node("New_York", "New York")))

	h.check("an id that would start with a digit gets a prefix",
		holds(mermaid.build([spo("2019-04-01", "is-parent-of", "tim")], types), "n_2019_04_01["))

	clash = mermaid.build([spo("a b", "is-parent-of", "tim"), spo("a_b", "is-parent-of", "anna")], types)
	h.check("two names that spell one id are numbered apart",
		has(clash, node("a_b", "A b")) and has(clash, node("a_b2", "A_b")))

	h.check("a quote in a name is escaped rather than ending the label",
		holds(mermaid.build([spo("he said " + char(34) + "hi" + char(34), "is-parent-of", "tim")], types),
			"#quot;hi#quot;"))

	// ── The relations the rules say read both ways ───────────────────────────
	// A rule whose head is its own one condition with the fields swapped is the knowledge base
	// saying the relation is symmetric, so a stored fact of it is not an arrow.

	marriage = [spo("walter", "married-to", "doris")]
	says = knowledge.parseRules(t, ["married-to(?y, ?x) => married-to(?x, ?y)",
		"is-child-of(?x, ?y) => is-parent-of(?y, ?x)"])
	h.check("a symmetric rule draws its relation with a plain link",
		has(mermaid.build(marriage, types, says), "  walter ---|married to| doris"))
	h.check("and a one-way rule leaves the arrow",
		has(mermaid.build([spo("bill", "is-child-of", "tim")], types, says),
			"  bill -->|is child of| tim"))
	h.check("a rule about one person is not a symmetry",
		has(mermaid.build(marriage, types,
			knowledge.parseRules(t, ["married-to(walter, ?x) => married-to(?x, walter)"])),
			"  walter -->|married to| doris"))
	h.check("and a diagram drawn without rules keeps every arrow",
		has(mermaid.build(marriage, types), "  walter -->|married to| doris"))

	// ── The same diagram as a picture ────────────────────────────────────────
	// The SVG is laid out here rather than by a renderer, so the checks read the document:
	// a box per node, a line per relation, an arrowhead only where the relation has one.

	picture = mermaid.svg(family, types)
	h.check("an SVG document starts the picture", picture[0][:4] == "<svg")
	h.check("and closes it", picture[picture.len - 1] == "</svg>")
	boxes = 0
	for line in picture
		if line.indexOf("<rect") != null then boxes = boxes + 1
	end for
	h.check("every node is a box, and the page is one more", boxes == 3)
	h.check("a relation is a line across the picture", holds(picture, "<line"))
	h.check("a one-way relation carries the arrowhead", holds(picture, "marker-end"))
	h.check("the lines are drawn light and their labels dark, so a label reads over them",
		holds(picture, "stroke='#9ca3af'") and holds(picture, "fill='#1f2937'"))
	h.check("a label is drawn with a white halo under it", holds(picture, "paint-order='stroke'"))
	// Two boxes in one row have a 40px gap between them, which a label is wider than, so the
	// label of a relation across that gap is written in the corridor below the row instead of
	// underneath the boxes that are painted over it.
	neighbours = mermaid.svg(marriage, types)
	h.check("a label on a short relation is written below the row, clear of the boxes",
		lineY(neighbours, "married to") > 40 + 68)
	h.check("a relation a rule gives both ways does not",
		not holds(mermaid.svg(marriage, types, says), "marker-end"))
	h.check("a parent is drawn above its child", lineY(picture, "Bill") < lineY(picture, "Tim"))
	h.check("a name is escaped for the picture, not pasted into it",
		holds(mermaid.svg([spo("a & b", "is-parent-of", "tim")], types), "A &amp; b"))

	// ── Terms ────────────────────────────────────────────────────────────────

	h.check("a fact that still holds a variable is not drawn",
		mermaid.build([spo(t.var("x"), "is-parent-of", "tim")], types).len == 1)

	// ── The shipped domain ───────────────────────────────────────────────────
	// The same files the program loads, read through the same loaders, so the exporter is
	// checked against the family rather than only against facts a case invents.

	shippedTypes = schemaLoader.build()
	h.check("data/schema.kb loads for the exporter", not (shippedTypes isa error))
	if shippedTypes isa error then return

	agree = 1
	for predicate in shippedTypes.indexes
		if mermaid.plainType(shippedTypes[predicate][1]) != knowledge.plainType(shippedTypes[predicate][1]) then
			agree = 0
		end if
	end for
	h.check("unique(...) is read the way the schema's own reader reads it", agree)

	shipped = factsLoader.build(t, null, shippedTypes)
	shippedRules = rulesLoader.build(t)
	h.check("data/facts.kb and data/rules.kb load for the exporter",
		not (shipped isa error) and not (shippedRules isa error))
	if (shipped isa error) or (shippedRules isa error) then return

	whole = mermaid.build(shipped, shippedTypes, shippedRules)
	nodes = 0
	edges = 0
	for line in whole
		if line.indexOf(char(91)) != null then nodes = nodes + 1
		if line.indexOf("---") != null or line.indexOf("-->") != null then edges = edges + 1
	end for
	h.check("the family is fifteen people", nodes == 15)
	h.check("and twenty-four stored relations", edges == 24)
	// The other thirty facts are the two values on each of the fifteen labels: one gender, then
	// one birthdate, so every label is a name and a <br/> and a pair joined by ' · '.
	labelled = 0
	pairs = 0
	for line in whole
		if line.indexOf("<br/>") != null then labelled = labelled + 1
		if line.indexOf(" · ") != null then pairs = pairs + 1
	end for
	h.check("every one of the 54 facts reaches the diagram", edges + labelled + pairs == 54)
	h.check("a person's gender and birthdate are on the node",
		holds(whole, "Walter<br/>male · 1948-03-14"))
	h.check("a parent edge is drawn from the fact itself",
		has(whole, "  walter -->|is parent of| bill"))
	h.check("the shipped rule makes a marriage no one's arrow",
		has(whole, "  walter ---|married to| doris"))
	shippedPicture = mermaid.svg(shipped, shippedTypes, shippedRules)
	boxes = 0
	for line in shippedPicture
		if line.indexOf("<rect") != null then boxes = boxes + 1
	end for
	h.check("the family's picture is the same fifteen boxes", boxes == 16)

	// ── Where the labels land ────────────────────────────────────────────────
	// The placement is the picture's one real layout decision, so it is checked against the
	// document the module wrote rather than against its intentions: the boxes are read from the
	// rects it drew, a label from the rectangle its text covers, and no label may land under a
	// box or on top of another label.

	attribute = function(line, name)
		"The number an SVG attribute holds, as in x='40'."
		at = line.indexOf(name + "='")
		if at == null then return null
		rest = line[at + name.len + 2:]
		return val(rest[:rest.indexOf("'")])
	end function
	rectOf = function(x, y, width, height)
		return {"x": x, "y": y, "width": width, "height": height}
	end function
	meet = function(a, b)
		"Says whether two rectangles share any part of the page."
		return not (a.x + a.width <= b.x or b.x + b.width <= a.x or
			a.y + a.height <= b.y or b.y + b.height <= a.y)
	end function
	boxesOf = function(lines)
		"The box drawn for each node."
		found = []
		for line in lines
			if line.indexOf("<rect") == null or line.indexOf("rx='8'") == null then continue
			found.push(rectOf(attribute(line, "x"), attribute(line, "y"),
				attribute(line, "width"), attribute(line, "height")))
		end for
		return found
	end function
	labelsOf = function(lines)
		"The rectangle each relation label's text covers, at the width the module plans with."
		found = []
		for line in lines
			if line.indexOf("paint-order='stroke'") == null then continue
			text = line[line.indexOf(">") + 1:line.indexOf("</text>")]
			width = text.len * 5 + 6
			found.push(rectOf(attribute(line, "x") - floor(width / 2),
				attribute(line, "y") - 9, width, 12))
		end for
		return found
	end function

	pictureBoxes = boxesOf(shippedPicture)
	pictureLabels = labelsOf(shippedPicture)
	hidden = 0
	for label in pictureLabels
		for box in pictureBoxes
			if meet(label, box) then hidden = hidden + 1
		end for
	end for
	crowded = 0
	if pictureLabels.len > 1 then
		for index in range(0, pictureLabels.len - 2)
			for later in range(index + 1, pictureLabels.len - 1)
				if meet(pictureLabels[index], pictureLabels[later]) then crowded = crowded + 1
			end for
		end for
	end if
	h.check("the family's picture writes a label for every relation", pictureLabels.len == 24)
	// A label is only legible if nothing is drawn after it, so the document has to hold every
	// line and every box before its first label.
	firstLabel = null
	lastLine = null
	lastBox = null
	for index in range(0, shippedPicture.len - 1)
		line = shippedPicture[index]
		if line.indexOf("paint-order='stroke'") != null and firstLabel == null then firstLabel = index
		if line.indexOf("<line") != null then lastLine = index
		if line.indexOf("rx='8'") != null then lastBox = index
	end for
	h.check("every line and box is drawn before the first label, so nothing can cross one",
		firstLabel != null and lastLine != null and lastBox != null and
			firstLabel > lastLine and firstLabel > lastBox)

	// A relation drawn along a row has only a narrow gap between its boxes, so its label belongs
	// in the corridor under that row rather than above it, where it would read as belonging to
	// whatever is above. The corridor is the space between this row's boxes and the next row's.
	corridor = null
	for first in pictureBoxes
		for second in pictureBoxes
			if second.y > first.y then
				if corridor == null or second.y - first.y < corridor then corridor = second.y - first.y
			end if
		end for
	end for
	// Lines and labels are written in the same order as the relations, so the nth line's label is
	// the nth label - which pairs a label with its line even when another relation's label happens
	// to sit at the same x.
	alongRow = []
	lineIndex = 0
	for line in shippedPicture
		if line.indexOf("<line") == null then continue
		if attribute(line, "y1") == attribute(line, "y2") then
			alongRow.push({"x": (attribute(line, "x1") + attribute(line, "x2")) / 2,
				"middle": attribute(line, "y1"), "index": lineIndex})
		end if
		lineIndex = lineIndex + 1
	end for
	// An empty list would pass the check below without checking anything, so the picture having
	// a relation drawn along a row at all is part of what is asserted.
	inCorridor = alongRow.len > 0
	for row in alongRow
		beside = pictureLabels[row.index]
		under = beside.y + 9
		if abs(row.x - (beside.x + beside.width / 2)) > 1 then inCorridor = 0
		if under < row.middle + pictureBoxes[0].height / 2 then inCorridor = 0
		if under > row.middle + corridor - pictureBoxes[0].height / 2 then inCorridor = 0
	end for
	h.check("a relation along a row keeps its label in the corridor under that row, not above it",
		inCorridor == 1)
	h.check("and no label lands under a box", hidden == 0)
	h.check("or on top of another label", crowded == 0)

	// ── Two labels under one row ─────────────────────────────────────────────
	// Two people can hold more than one relation that reads both ways - married, and working
	// together - so two labels want the one place in the corridor under their row. The first
	// takes it; the second steps down inside that corridor rather than to the corridor above the
	// row, which is where a label reads as belonging to whatever is above it.
	together = [spo("walter", "married-to", "doris"), spo("walter", "works-with", "doris")]
	togetherTypes = {"married-to": ["text", "text"], "works-with": ["text", "text"]}
	both = mermaid.svg(together, togetherTypes,
		knowledge.parseRules(t, ["married-to(?y, ?x) => married-to(?x, ?y)",
			"works-with(?y, ?x) => works-with(?x, ?y)"]))
	pair = labelsOf(both)
	floorOfRow = 0
	for box in boxesOf(both)
		if box.y + box.height > floorOfRow then floorOfRow = box.y + box.height
	end for
	stepped = 0
	if pair.len == 2 and pair[0].x == pair[1].x then
		first = pair[0].y + 9
		second = pair[1].y + 9
		if second > first and second < first + 40 and second > floorOfRow then stepped = 1
	end if
	h.check("two relations between one pair are written as two labels, one under the other",
		pair.len == 2 and pair[0].x == pair[1].x)
	h.check("the second of them steps down inside the corridor under the row, not above it",
		stepped == 1)
end function
