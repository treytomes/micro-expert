// triples.ms — the two triplet shapes the knowledge base is built from.
//
// Both classes live here on purpose: a module that imports another module gets
// its own copy of it, and each copy carries its own class maps, so `isa` would
// fail against a SpoTriple built in a different copy. One module, one class each.
//
//   import "triples"
//   spo = triples.SpoTriple.make("trey", "avoids", "gluten")
//   oav = triples.OavTriple.make("gluten", "contains", "gliadin")
//   print oav.toSpo.text           // spo(gluten | has-contains | gliadin)
//   print triples.SpoTriple.parse("trey | avoids | gluten").text
//   print triples.SpoTriple.parse(oav.toSpo.text).text   // display form reads back

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
	"Parses 'a | b | c' or the display form 'spo(a | b | c)'; triple or error value."
	fields = parseLine(line, "spo", ["subject", "predicate", "object"])
	if fields isa error then return fields
	return SpoTriple.make(fields[0], fields[1], fields[2])
end function

SpoTriple.text = function
	"Formats the triple for display as 'spo(subject | predicate | object)'."
	return "spo(" + self.parts.join(" | ") + ")"
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

OavTriple.text = function
	"Formats the triplet for display as 'oav(object | attribute | value)'."
	return "oav(" + self.parts.join(" | ") + ")"
end function

OavTriple.parts = function
	"Returns the triplet as the list [object, attribute, value]."
	return [self.object, self.attribute, self.value]
end function

OavTriple.toSpo = function
	"Converts to a SpoTriple: the attribute becomes a 'has-' predicate."
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
	end for
	return fields
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
