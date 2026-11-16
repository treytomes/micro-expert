// spo.ms — Subject-Predicate-Object triples, the atom of a rule base.
//
//   import "spo"
//   t = spo.SpoTriple.make("trey", "avoids", "gluten")
//   print t.text                 // trey | avoids | gluten
//   t = spo.SpoTriple.parse("trey | avoids | gluten")
//   if t isa error then print t.message

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
	"Formats the triple as 'subject | predicate | object', the fact-file shape."
	return "spo(" + self.parts.join(" | ") + ")"
end function

SpoTriple.parts = function
	"Returns the triple as the list [subject, predicate, object]."
	return [self.subject, self.predicate, self.object]
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
