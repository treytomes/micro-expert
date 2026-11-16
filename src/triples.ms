// triples.ms — the terms and the two triplet shapes the knowledge base is built from.
//
// The classes live together on purpose: a module that imports another module gets
// its own copy of it, and each copy carries its own class maps, so `isa` would
// fail against a SpoTriple built in a different copy. One module, one class each.
//
//   import "triples"
//   spo = triples.SpoTriple.make("trey", "avoids", "gluten")
//   oav = triples.OavTriple.make("gluten", "contains", "gliadin")
//   print oav.toSpo.text           // spo(gluten | has-contains | gliadin)
//   print triples.SpoTriple.parse("trey | avoids | gluten").text
//   print triples.SpoTriple.parse(oav.toSpo.text).text   // display form reads back
//   print triples.OavTriple.parse("oav(gluten | contains | gliadin)").text
//   print triples.SpoTriple.make(triples.var("x"), "child", "?y").text
//   // spo(?x | child | ?y)

// ── Var: a logic variable, written ?x ────────────────────────────────────────

Var = {}

Var.make = function(name)
	"Builds a logic variable; 'x' and '?x' both name ?x."
	if name[:1] == "?" then name = name[1:]
	v = new Var
	v.name = name
	return v
end function

Var.text = function
	"Formats the variable as '?name'."
	return "?" + self.name
end function

var = function(name)
	"Shorthand for Var.make, for use inside triple fields."
	return Var.make(name)
end function

termText = function(term)
	"Renders one term: a Var as '?x', anything else as it is."
	if term isa Var then return term.text
	return term
end function

renderParts = function(parts)
	"Renders triple fields the way display text shows them."
	texts = []
	for part in parts
		texts.push(termText(part))
	end for
	return texts.join(" | ")
end function

// ── SpoTriple: subject, predicate, object ─────────────────────────────────────

SpoTriple = {}

SpoTriple.make = function(subject, predicate, object)
	"Builds a triple from its subject, predicate, and object."
	t = new SpoTriple
	t.subject = subject
	t.predicate = predicate
	t.object = object
	return t
end function

SpoTriple.parse = function(line)
	"Parses 'a | b | c' or 'spo(a | b | c)'; '?x' fields become Vars. Error on anything else."
	fields = parseLine(line, "spo", ["subject", "predicate", "object"])
	if fields isa error then return fields
	return SpoTriple.make(fields[0], fields[1], fields[2])
end function

SpoTriple.text = function
	"Formats the triple for display as 'spo(subject | predicate | object)'."
	return "spo(" + renderParts(self.parts) + ")"
end function

SpoTriple.parts = function
	"Returns the triple as the list [subject, predicate, object]."
	return [self.subject, self.predicate, self.object]
end function

// ── OavTriple: object, attribute, value ───────────────────────────────────────

OavTriple = {}

OavTriple.make = function(object, attribute, value)
	"Builds a triplet from its object, attribute, and value."
	t = new OavTriple
	t.object = object
	t.attribute = attribute
	t.value = value
	return t
end function

OavTriple.parse = function(line)
	"Parses 'a | b | c' or 'oav(a | b | c)'; '?x' fields become Vars. Error on anything else."
	fields = parseLine(line, "oav", ["object", "attribute", "value"])
	if fields isa error then return fields
	return OavTriple.make(fields[0], fields[1], fields[2])
end function

OavTriple.text = function
	"Formats the triplet for display as 'oav(object | attribute | value)'."
	return "oav(" + renderParts(self.parts) + ")"
end function

OavTriple.parts = function
	"Returns the triplet as the list [object, attribute, value]."
	return [self.object, self.attribute, self.value]
end function

OavTriple.toSpo = function
	"Converts to a SpoTriple: a literal attribute becomes a 'has-' predicate."
	// 'has-' is a naming convention for literal attributes. A variable attribute
	// has no literal name to prefix, so it becomes the predicate itself:
	// oav(?o | ?a | ?v) -> spo(?o | ?a | ?v).
	if self.attribute isa Var then
		return SpoTriple.make(self.object, self.attribute, self.value)
	end if
	return SpoTriple.make(self.object, "has-" + self.attribute, self.value)
end function

// ── Parsing ───────────────────────────────────────────────────────────────────

parseLine = function(line, shape, names)
	"Reads 'a | b | c' or 'shape(a | b | c)' into three trimmed fields, or an error."
	text = trimSpace(line)

	// Another shape's display text would otherwise be read as three fields, with
	// 'oav(a' quietly becoming the subject.
	other = otherShapeIn(text, shape)
	if other != null then
		return err("malformed " + shape + ": looks like " + other + "(...): " + line)
	end if

	prefix = shape + "("
	if text[:prefix.len] == prefix then
		if text[-1] != ")" then return err(badLine(line, shape, names))
		text = trimSpace(text[prefix.len:-1])
	end if

	fields = text.split("|")
	if fields.len != 3 then return err(badLine(line, shape, names))

	for i in range(0, 2)
		fields[i] = trimSpace(fields[i])
		if fields[i] == "" then
			return err("malformed " + shape + ": empty " + names[i] + ": " + line)
		end if
		fields[i] = termOf(fields[i])
	end for
	return fields
end function

termOf = function(text)
	"Turns a '?x' field into a Var, leaving every other field a plain string."
	if text[:1] == "?" then return Var.make(text)
	return text
end function

otherShapeIn = function(text, shape)
	"Returns the other triplet shape's name when text is wrapped as one, else null."
	for name in ["spo", "oav"]
		if name != shape then
			if text[:name.len + 1] == name + "(" then return name
		end if
	end for
	return null
end function

badLine = function(line, shape, names)
	"Builds the shared 'expected this or that' message for one shape."
	expected = names.join(" | ")
	return "malformed " + shape + ": expected '" + expected + "' or '" +
		shape + "(" + expected + ")': " + line
end function

// ── Helpers ───────────────────────────────────────────────────────────────────

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
