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
	"Parses 'subject | predicate | object'; returns a triple or an error value."
	fields = line.split("|")
	if fields.len != 3 then
		return err("malformed triple: expected 'subject | predicate | object': " + line)
	end if

	subject = trimSpace(fields[0])
	predicate = trimSpace(fields[1])
	object = trimSpace(fields[2])
	if subject == "" then return err("malformed triple: empty subject: " + line)
	if predicate == "" then return err("malformed triple: empty predicate: " + line)
	if object == "" then return err("malformed triple: empty object: " + line)

	return SpoTriple.make(subject, predicate, object)
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
