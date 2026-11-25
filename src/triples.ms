// triples.ms — the terms, the triple, and the reasoner over them.
//
// The classes live together on purpose: a module that imports another module gets
// its own copy of it, and each copy carries its own class maps, so `isa` would
// fail against a SpoTriple built in a different copy. One module, one class each.
//
//   import "triples"
//   spo = triples.SpoTriple.make("trey", "avoids", "gluten")
//   print spo.text                          // avoids(trey, gluten)
//   print triples.SpoTriple.parse("avoids(trey, gluten)").text   // reads back
//   print triples.SpoTriple.parse("won-prize(bill, sprint) @ 2002-04-05 ~ 80%").text
//   print triples.SpoTriple.parse("trey | avoids | gluten").text // same triple
//   print triples.SpoTriple.make(triples.var("x"), "child", triples.var("y")).text
//   // child(?x, ?y)
//   print triples.unify(triples.SpoTriple.parse("child(?x, ?y)"),
//       triples.SpoTriple.parse("child(susan, bill)"))   // {"x": "susan", "y": "bill"}
//
// The calendar a date is counted on is temporal.ms's, imported here for the one reading a
// constraint makes of one: whether a value is a date at all, which its reader is what says.

import "temporal"

// ── List combinators ─────────────────────────────────────────────────────────
// Small list operations, so the functions below can say what they do with a list
// rather than walk it. mapWith hands each item and one shared argument to f.

mapWith = function(items, f, arg=null)
	"One result per item, in order; f takes the item and the argument."
	results = []
	for item in items
		results.push(f(item, arg))
	end for
	return results
end function

// ── Quotes ───────────────────────────────────────────────────────────────────
// A field may be written in double quotes: has-home-town(guid, "Dallas, TX"). The quotes
// are syntax, not part of the value - they say where the value ends when it holds a
// character the form would otherwise read itself (a comma, a bracket, a '|', the '//' that
// opens a comment) - and they promise the field is text: "Dallas" is the text Dallas, and
// "7" is the text 7, where the number is written bare. There is no escape, so a value
// cannot hold a double quote.
//
// needsQuotes is the other half of the same rule: a value is written in quotes when the
// bare spelling would read back as something else, so what a triple displays as is a line
// that reads back as the same triple.

quoteChar = char(34)

isQuoted = function(text)
	"Says whether a field is written in quotes, which are syntax and not part of its value."
	if not (text isa string) then return false
	return text.len >= 2 and text[:1] == quoteChar and text[-1] == quoteChar
end function

bareText = function(text)
	"What a field spells without its quotes: the value itself when it has none."
	if not isQuoted(text) then return text
	return text[1:-1]
end function

balancedQuotes = function(text)
	"Says whether every quote is closed, so an open one is refused rather than swallowing the rest of the line."
	count = 0
	for c in text
		if c == quoteChar then count = count + 1
	end for
	return count * 0.5 == floor(count * 0.5)
end function

indexOfOutside = function(text, needle, brackets=true)
	"Where needle first stands outside quotes and brackets, or null when it does not."
	if text.len < needle.len then return null
	depth = 0
	quoted = false
	for at in range(0, text.len - needle.len)
		c = text[at]
		if c == quoteChar then
			quoted = not quoted
		else if quoted then
			continue
		else if brackets and c == "(" then
			depth = depth + 1
		else if brackets and c == ")" then
			depth = depth - 1
		else if depth == 0 and text[at:at + needle.len] == needle then
			return at
		end if
	end for
	return null
end function

splitOutside = function(text, separator, brackets=true)
	"One piece per separator that stands outside quotes and brackets."
	pieces = []
	current = ""
	depth = 0
	quoted = false
	for c in text
		if c == quoteChar then
			quoted = not quoted
		else if not quoted then
			if brackets and c == "(" then
				depth = depth + 1
			else if brackets and c == ")" then
				depth = depth - 1
			else if c == separator and depth == 0 then
				pieces.push(current)
				current = ""
				continue
			end if
		end if
		current = current + c
	end for
	pieces.push(current)
	return pieces
end function

needsQuotes = function(text)
	"Says whether a value has to be written in quotes to read back as itself."
	if not (text isa string) then return false
	if text.len == 0 then return true
	// A leading '?' would read as a variable, and a number-like text as a number.
	if text[:1] == "?" then return true
	if isNumber(text) then return true
	// The form trims the space around a field, so a value's own edges would be lost.
	if text != trimSpace(text) then return true
	// Each of these means something else in one of the two forms: a comma separates
	// fields, a bracket opens or closes a call, a '|' separates the pipe form's fields.
	for c in text
		if c == "," or c == "(" or c == ")" or c == "|" or c == quoteChar then return true
	end for
	// '//' opens a comment in a data file, and an arrow has its own meaning in a rule.
	return text.indexOf("//") != null or text.indexOf("=>") != null
end function

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


isVar = function(term)
	"Says whether a term is still a variable rather than a value."
	return term isa Var
end function

// A term can be a call. 'add-hours(has-time(session, ?now), 9)' is the moment nine hours from
// now, and it stands where a moment stands - after a question's '@'. The names are reserved:
// a call is a value rather than a condition, so a body line called 'add-hours' is refused
// rather than proved, and neither name is ever stored as a fact. The two build the moment
// arithmetic a question needs, and nothing about the clock is kept - the time is different the
// next time it is asked.
Call = {}

Call.make = function(name, args)
	"Builds a call: the name it is written under, and its arguments as terms."
	c = new Call
	c.name = name
	c.args = args
	return c
end function

Call.text = function
	"Writes the call the way it was read: add-hours(has-time(session, ?now), 9)."
	written = []
	for arg in self.args
		written.push(termText(arg))
	end for
	return self.name + "(" + written.join(", ") + ")"
end function

callNames = {"has-time": 1, "add-hours": 1}

callFields = {"has-time": 2, "add-hours": 2}

callProblem = function(term)
	"Says what is wrong with a call's shape, or null when it is written as its name takes it."
	if not (term isa Call) then return null
	wanted = callFields[term.name]
	if term.args.len != wanted then
		return term.name + " takes " + wanted + " fields, not " + term.args.len
	end if
	for arg in term.args
		problem = callProblem(arg)
		if problem != null then return problem
	end for
	return null
end function

isCallName = function(name)
	"Says whether a name is a call's, which reads the clock rather than a fact."
	return name isa string and callNames.hasIndex(name) != 0
end function

termText = function(term)
	if term isa Call then return term.text
	"Renders one term: a Var as '?x', a value in quotes when it needs them, and anything else as it is."
	if term isa Var then return term.text
	if needsQuotes(term) then return quoteChar + term + quoteChar
	return term
end function

// ── SpoTriple: subject, predicate, object ─────────────────────────────────────

SpoTriple = {}

SpoTriple.make = function(subject, predicate, object, at=null, confidence=100, source=null,
	fetched=null)
	"Builds a triple from its subject, predicate, and object, with the annotations a fact may carry: when it holds, how confident we are, and which service answered it and when."
	t = new SpoTriple
	t.subject = subject
	t.predicate = predicate
	t.object = object
	// A fact that says nothing about time is not time-bound, and one that says nothing about
	// its confidence is fully confident. The fields are always there, so a reader never has
	// to know which of them an old line carried.
	t.at = at
	t.confidence = confidence
	// A fact a service answered says which service and endpoint gave it and the day it was read;
	// nothing else sets these, and a typed fact leaves them null.
	t.source = source
	t.fetched = fetched
	return t
end function

SpoTriple.parse = function(line)
	"Parses 'predicate(subject, object)' or 'subject | predicate | object', with the '@' and '~' annotations a fact may carry after it; '?x' fields become Vars."
	// The annotations follow the triple, so what comes before the first sign is the line read
	// here and what comes from it on is read apart: a fact typed at the prompt and one read
	// from a file are the same fact, because this module is where both doors read the form.
	signAt = indexOfAnnotation(line)
	callText = line
	written = ""
	if signAt != null then
		callText = line[:signAt]
		written = line[signAt:]
	end if
	fields = parseLine(callText)
	if fields isa error then return fields
	// A predicate that cannot be said is refused with the line it came on, here and not
	// later: this is the one reader a typed fact, question or rule comes through.
	if fields[1] isa string then
		problem = predicateProblem(fields[1])
		if problem != null then return err(problem + ": " + callText)
	end if
	triple = SpoTriple.make(fields[0], fields[1], fields[2])
	if written == "" then return triple
	read = readAnnotations(written)
	if read isa error then return read
	triple.at = read.at
	triple.confidence = read.confidence
	triple.source = read.source
	triple.fetched = read.fetched
	return triple
end function

sameClaim = function(one, other)
	"Says whether two facts make the same claim - the same subject, predicate, object, moment and confidence - whatever service answered them, or on what day."
	return termText(one.subject) == termText(other.subject) and
		termText(one.predicate) == termText(other.predicate) and
		termText(one.object) == termText(other.object) and
		one.at == other.at and one.confidence == other.confidence
end function


SpoTriple.parseBare = function(line)
	"SpoTriple.parse with no annotations, for a rule's head and conditions, which are written bare: only a stored fact carries one."
	if indexOfAnnotation(line) != null then
		return err("an annotation belongs to a fact, not to a rule's head or condition: " + line)
	end if
	return SpoTriple.parse(line)
end function

// ── A fact's annotations ─────────────────────────────────────────────────────
// The three signs are read from the text after the call, left to right, and each sign opens one
// annotation: '@' reads a moment, '~' reads a percentage, and '#' reads who answered the fact and
// the day it was read. Each may come at most once, and nothing else may follow them, since a
// fact that said more than the form holds would be read as something it does not say.
//
// '#' is what a service's answer carries: a fact that came from a provider names the service and
// endpoint that gave it and the day they were asked, so it can be told from a typed fact and
// weighed by how stale it is. A fact nobody was asked for carries neither.
//
// A moment is what temporal.ms reads - a date, a time, a datetime, or a span in brackets - and
// its text is kept as it was written rather than as the value it stands for: '@ 2019-04' stays
// 2019-04, the way a reader typed it.
//
// The reader lives here rather than in knowledge.ms because both doors to a fact come through
// this module: a line in a facts file and a line typed at the prompt are read by the same code,
// so the two cannot drift into accepting different things.

indexOfAnnotation = function(text)
	"Where the first '@', '~' or '#' stands outside quotes and the call's brackets, or null when there is none."
	first = null
	for sign in ["@", "~", "#"]
		at = indexOfOutside(text, sign, true)
		if at == null then continue
		if first == null or at < first then first = at
	end for
	return first
end function

readAnnotations = function(text)
	"Reads the annotations after a fact, '@ ', '~ ' and '# ', into {at, confidence, source, fetched}, or says what is wrong with them."
	at = null
	confidence = 100
	source = null
	fetched = null
	seenAt = false
	seenConfidence = false
	seenSource = false
	rest = trimSpace(text)
	while rest != ""
		sign = rest[:1]
		if sign != "@" and sign != "~" and sign != "#" then
			return err("a fact's annotations are '@', '~' and '#': " + trimSpace(text))
		end if
		if sign == "@" then
			if seenAt then return err("a fact takes one '@': " + trimSpace(text))
			seenAt = true
			moment = readAtTerm(rest[1:])
			if moment isa error then return moment
			at = moment.text
			rest = moment.rest
		else if sign == "~" then
			if seenConfidence then return err("a fact takes one '~': " + trimSpace(text))
			seenConfidence = true
			percent = readConfidence(rest[1:])
			if percent isa error then return percent
			confidence = percent.value
			rest = percent.rest
		else
			if seenSource then return err("a fact takes one '#': " + trimSpace(text))
			seenSource = true
			said = readSource(rest[1:])
			if said isa error then return said
			source = said.source
			fetched = said.fetched
			rest = said.rest
		end if
		rest = trimSpace(rest)
	end while
	return {"at": at, "confidence": confidence, "source": source, "fetched": fetched}
end function

readSource = function(text)
	"Reads '<service>/<endpoint> <day>' from the front of text, as {source, fetched, rest}, or says what is wrong with it."
	text = trimSpace(text)
	stop = 0
	while stop < text.len and not isSpace(text[stop])
		stop = stop + 1
	end while
	name = text[:stop]
	if name == "" then
		return err("'#' needs the service and endpoint that answered, as in '# open-meteo/forecast'")
	end if
	if name.indexOf("/") == null then
		return err("'#' names a service and an endpoint, as in '# open-meteo/forecast': " + name)
	end if
	moment = readMoment(text[stop:])
	if moment isa error then return moment
	return {"source": name, "fetched": moment.text, "rest": moment.rest}
end function

readAtTerm = function(text)
	"Reads what follows '@' in a question or a fact: a moment as readMoment reads one, a variable standing for one, or a call that works one out - the forms a question names the hour with."
	text = trimSpace(text)
	// A call stands where a moment stands, and its arguments can hold the variables a moment
	// cannot: add-hours(has-time(session, ?now), 9) is nine hours after the clock.
	for name in callNames.indexes
		if text[:name.len + 1] == name + "(" then
			depth = 0
			endAt = null
			for at in range(0, text.len - 1)
				c = text[at]
				if c == "(" then
					depth = depth + 1
				else if c == ")" then
					depth = depth - 1
					if depth == 0 then
						endAt = at
						break
					end if
				end if
			end for
			if endAt == null then return err("'@' needs the call to close: " + text)
			written = text[:endAt + 1]
			called = termOf(written)
			problem = callProblem(called)
			if problem != null then return err(problem + ": " + written)
			return {"text": called, "rest": text[endAt + 1:]}
		end if
	end for
	if text[:1] != "?" then return readMoment(text)
	// A variable ends at the first space or at the next annotation's sign, so '@ ?when ~ 80%'
	// would still be two annotations rather than one name with a sign in it.
	last = text.len
	for at in range(0, text.len - 1)
		c = text[at]
		if c == " " or c == "@" or c == "~" or c == "#" then
			last = at
			break
		end if
	end for
	written = trimSpace(text[:last])
	if written.len < 2 then return err("'@' needs a date, a time, a span, or a variable to hold one: " + text)
	return {"text": Var.make(written), "rest": text[last:]}
end function

readMoment = function(text)
	"Reads one date, time, datetime or span from the front of text, as {text, rest}, or says what is wrong with it."
	text = trimSpace(text)
	if text == "" then return err("'@' needs a date, a time or a span")
	// A span is one piece of text between brackets, so where it ends is its own ']': the two
	// moments inside it are separated by a comma, and either may hold a space of its own.
	if text[:1] == "[" then
		closeAt = text.indexOf("]")
		if closeAt == null then
			return err("'@' needs a date, a time or a span in brackets: " + text)
		end if
		written = trimSpace(text[:closeAt + 1])
		span = temporal.TimeSpan.receive(written)
		if span isa error then return err(span.message)
		return {"text": written, "rest": text[closeAt + 1:]}
	end if
	// A moment holds neither sign, so it ends where the next annotation opens, and the space
	// a datetime has is its own: what is left is one piece of text and the reader says
	// whether it is a moment, rather than the piece being guessed at its spaces.
	last = text.len
	for at in range(0, text.len - 1)
		if text[at] == "@" or text[at] == "~" or text[at] == "#" then
			last = at
			break
		end if
	end for
	written = trimSpace(text[:last])
	momentValue = temporal.DateTime.receive(written)
	if momentValue isa error then return err("'@' needs a date, a time or a span: " + written)
	return {"text": written, "rest": text[last:]}
end function

readConfidence = function(text)
	"Reads '<number>%' from the front of text, as {value, rest}, or says what is wrong with it."
	text = trimSpace(text)
	stop = 0
	while stop < text.len and not isSpace(text[stop]) and text[stop] != "@" and text[stop] != "~" and text[stop] != "#"
		stop = stop + 1
	end while
	written = text[:stop]
	if written.len < 2 or written[-1] != "%" then
		return err("a confidence is a number and the sign '%', as in '~ 80%': " + text)
	end if
	spelled = written[:-1]
	if not spelledNumber(spelled) then
		return err("a confidence is a number and the sign '%', as in '~ 80%': " + text)
	end if
	value = val(spelled)
	if value < 0 or value > 100 then
		return err("a confidence runs from 0% to 100%: " + text)
	end if
	return {"value": value, "rest": text[stop:]}
end function

spelledNumber = function(text)
	"Says whether text spells a decimal number in the plain shape a confidence is written in."
	if text.len == 0 then return false
	start = 0
	if text[:1] == "-" then start = 1
	if text.len <= start then return false
	digits = 0
	dots = 0
	for at in range(start, text.len - 1)
		c = text[at]
		if c >= "0" and c <= "9" then
			digits = digits + 1
		else if c == "." then
			dots = dots + 1
			if dots > 1 then return false
		else
			return false
		end if
	end for
	return digits > 0
end function

SpoTriple.text = function
	"Formats the fact as the line that reads back as itself: 'predicate(subject, object)', then the annotations it carries."
	// The annotations are part of the line because they are part of the fact: two readings
	// that differ only in when they hold are two facts, and a fact is known by its text.
	// The moment comes first and the confidence second, so a fact reads one way whatever
	// order the two were written in; a fact that says nothing about either stays bare.
	line = termText(self.predicate) + "(" + termText(self.subject) + ", " +
		termText(self.object) + ")"
	// A fact's moment is text and is written as it was read; a question's can still be a
	// variable, which is written the way a variable is.
	if self.at isa string then
		line = line + " @ " + self.at
	else if self.at != null then
		line = line + " @ " + termText(self.at)
	end if
	if self.confidence != 100 then line = line + " ~ " + str(self.confidence) + "%"
	if self.source != null then
		line = line + " # " + self.source
		if self.fetched != null then line = line + " " + self.fetched
	end if
	return line
end function

SpoTriple.parts = function
	"Returns the triple as the list [subject, predicate, object]."
	return [self.subject, self.predicate, self.object]
end function

SpoTriple.sentence = function
	"Formats the fact as a sentence, 'oliver has uncle zed': the predicate's dashes read as spaces, and the annotations follow in words."
	// A variable predicate is not a name, so the triple keeps the fact form that shows
	// the variable itself rather than inventing a word for it.
	if not (self.predicate isa string) then return self.text
	said = termText(self.subject) + " " + self.predicate.split("-").join(" ") + " " +
		termText(self.object)
	// The annotation is part of the fact, so the sentence says it too: two readings of one value
	// at different hours would otherwise be the same sentence twice.
	if self.at isa string then
		when = self.at
		if self.at[:1] == "[" then
			said = said + " during " + when
		else
			said = said + " at " + when
		end if
	end if
	if self.confidence != 100 then said = said + ", " + str(self.confidence) + "% confident"
	if self.source != null then said = said + ", according to " + self.source
	return said
end function

// ── Predicate names ──────────────────────────────────────────────────────────
// A predicate is written in lower case as sections joined by '-', each section letters
// and digits, and the first section starting with a letter: is-parent-of, has-1-child,
// married-to. Nothing in the search depends on that - the shape is what makes a result
// sayable, since a sentence is the name with its dashes opened to spaces - so a name that
// is not one is refused where the line is read, and the knowledge base holds only names a
// result can say. knowledge.ms checks the same rule on the data files and the schema.
//
// A variable is not a name: ?p(susan, tim) asks what relates the two, and there is
// nothing yet to say.

predicateProblem = function(name)
	"Says what is wrong with a predicate name, as 'a predicate starts with a letter', or null when it is one."
	// A variable is not a name: ?p(susan, tim) asks what relates the two.
	if name[:1] == "?" then return null
	sections = name.split("-")
	for at in range(0, sections.len - 1)
		section = sections[at]
		// Every dash separates two sections, so each one has to be there.
		if section == "" then return "a predicate is sections joined by '-', and none is empty"
		for c in section
			// A name is lower case, so the letters stop at z: an upper-case one is refused here.
			if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9")) then
				return "a predicate is lower-case letters and digits, joined by '-'"
			end if
		end for
		// A leading digit would read as a number, so the name starts with a letter and
		// only the sections after it may open with one.
		if at == 0 and section[0] >= "0" and section[0] <= "9" then
			return "a predicate starts with a letter"
		end if
	end for
	return null
end function

// ── Unification ───────────────────────────────────────────────────────────────

// Bindings are extended, never edited: every step returns a new map, so a match
// that fails partway leaves the caller's bindings alone and no defensive copy is
// needed anywhere above.

copyBinds = function(binds)
	"Returns a copy of a bindings map; null becomes an empty map."
	if binds == null then return {}
	return binds + {}
end function

withBinding = function(binds, name, value)
	"A copy of the bindings with one entry added or replaced - never the map itself."
	copied = copyBinds(binds)
	copied[name] = value
	return copied
end function

unify = function(pattern, fact, binds=null)
	"Unifies a pattern against a fact, returning the bindings it adds, or null."
	working = copyBinds(binds)
	if pattern isa SpoTriple then
		if not (fact isa SpoTriple) then return null
		matched = unifyParts(pattern.parts, fact.parts, working)
		if matched == null then return null
		atMatched = unifyAt(pattern, fact, matched)
		if atMatched == null then return null
		return atMatched
	end if
	matches = unifyTerms(pattern, fact, working)
	if matches == null then return null
	return resolveBindings(matches)
end function

unifyParts = function(leftParts, rightParts, binds)
	"Unifies the fields of two triples in turn, left to right; resolved when done."
	if leftParts.len == 0 then return resolveBindings(binds)
	extended = unifyTerms(leftParts[0], rightParts[0], binds)
	if extended == null then return null
	return unifyParts(leftParts[1:], rightParts[1:], extended)
end function

unifyTerms = function(left, right, binds)
	"The bindings extended so the two terms agree, or null when they cannot."
	left = deref(left, binds)
	right = deref(right, binds)
	if left == right then return binds
	if left isa Var and right isa Var then
		// Binding one variable to another is how a rule's fresh variable meets the question's,
		// so it is what most unifications end in. What it must not do is extend a map that
		// holds a cycle: deref stops on a variable that is still a key only when the alias leads
		// back to itself, and naming it again would hand the next walk the same ring.
		if binds.hasIndex(left.name) or binds.hasIndex(right.name) then return binds
		return withBinding(binds, left.name, right)
	end if
	if left isa Var then return withBinding(binds, left.name, right)
	if right isa Var then return withBinding(binds, right.name, left)
	return null
end function

unifyAt = function(pattern, fact, binds)
	"The bindings extended so a goal's '@' agrees with a fact's, or null when they cannot: a variable takes the moment the fact holds, and a moment asked for is the one the fact covers - inside the span when it holds for a span."
	if pattern.at == null then return binds
	if fact.at == null then return null
	if pattern.at isa Var then return withBinding(binds, pattern.at.name, fact.at)
	// A call works out the moment it stands for, and what it settled - the clock it read - comes
	// with it, so a question can name the hour as an offset from now.
	if pattern.at isa Call then
		evaluated = evaluate(pattern.at, binds)
		if evaluated == null then return null
		binds = evaluated.binds
		asked = evaluated.value
		if not (asked isa string) then return null
	else
		// A stored moment is text and is compared as the text it was written as; termText would
		// quote a span, since a span holds a comma of its own.
		asked = pattern.at
	end if
	if asked == fact.at then return binds
	// A question about an instant is asking for the reading that covers it: three hours from
	// now lands on the hour whose span holds it, not on a line that says the same thing.
	if asked[:1] != "[" and fact.at[:1] == "[" then
		moment = temporal.DateTime.receive(asked)
		if moment isa error then return null
		span = temporal.TimeSpan.receive(fact.at)
		if span isa error then return null
		if span.contains(moment) == true then return binds
	end if
	return null
end function

deref = function(term, binds)
	"Follows bindings until a non-variable or an unbound variable, and stops at a cycle."
	if not (term isa Var) then return term
	// No bindings yet means nothing is bound, so the variable derefs to itself. The top
	// level of a query derefs a goal's predicate with null binds (candidateFacts,
	// predicatesMeet), and only a variable predicate ever reaches this line.
	if binds == null then return term
	if not binds.hasIndex(term.name) then return term
	current = binds[term.name]
	if not (current isa Var) then return current
	if not binds.hasIndex(current.name) then return current
	// Two hops in, the map can be holding a cycle, so the names walked are kept from here on:
	// a variable met twice is taken to stand for itself, and the walk ends where it started
	// instead of overflowing the stack. A single hop never builds the map, since the solver's
	// own bindings are a forest and one hop is where most of them end.
	seen = {term.name: 1, current.name: 1}
	while binds.hasIndex(current.name)
		current = binds[current.name]
		if not (current isa Var) then return current
		if seen.hasIndex(current.name) then return current
		seen[current.name] = 1
	end while
	return current
end function

resolveBindings = function(binds)
	"Resolves every binding through the others, so no value is a bound variable."
	resolved = {}
	for name in binds.indexes
		resolved[name] = deref(binds[name], binds)
	end for
	return resolved
end function

substitute = function(term, binds)
	"Applies bindings: a new triple with resolved fields and the annotations it carries, or the resolved term."
	if binds == null then return term
	if term isa SpoTriple then
		// The moment can be a variable in a question - '@ ?when' - so it is resolved here with
		// the fields; a fact's moment is text, and deref leaves it as it is.
		return SpoTriple.make(deref(term.subject, binds), deref(term.predicate, binds),
			deref(term.object, binds), substitute(term.at, binds), term.confidence, term.source,
			term.fetched)
	end if
	if term isa Call then
		args = []
		for arg in term.args
			args.push(substitute(arg, binds))
		end for
		return Call.make(term.name, args)
	end if
	return deref(term, binds)
end function

answerTriple = function(goal, binds, at=null, confidence=100, source=null, fetched=null)
	"One answer's triple: the goal with its bindings applied, carrying every annotation of the fact it was proved from."
	settled = substitute(goal, binds)
	if not (settled isa SpoTriple) then return settled
	if at == null and confidence == 100 and source == null then return settled
	return SpoTriple.make(settled.subject, settled.predicate, settled.object, at, confidence, source,
		fetched)
end function

// ── Constraints ──────────────────────────────────────────────────────────────
// A rule body is a list of goals, and it may also hold constraints: conditions that are
// checked against the bindings rather than proved by search. They are written as calls
// like everything else - not-equal(?x, ?y), equal(?n, 18), less-than-or-equal(?n, 18),
// years-since(?b, ?n) - and their names are reserved, so no fact and no question can use one
// as a predicate.

// not-equal and equal read their two terms as they are, whatever type they hold: not-equal
// asks that they differ, equal that they are the same one. Their names are reserved like a
// comparison's: a term never means "check this" in a body and "assert this" as a fact.
//
// equal is the one constraint that can bind. The others only agree or disagree with what the
// conditions before them settled; equal settles a side that is still a variable, so a body
// may write equal(?n, 18) before anything has bound ?n and go on with ?n as 18.
notEqualName = "not-equal"
equalName = "equal"

NotEqual = {}

NotEqual.make = function(left, right)
	"Builds a 'these two terms must differ' constraint."
	c = new NotEqual
	c.left = left
	c.right = right
	return c
end function

NotEqual.text = function
	"Says how the constraint reads: not-equal(?x, ?y)."
	return notEqualName + "(" + termText(self.left) + ", " + termText(self.right) + ")"
end function

Equal = {}

Equal.make = function(left, right)
	"Builds a 'these two terms must be the same one' constraint."
	c = new Equal
	c.left = left
	c.right = right
	return c
end function

Equal.text = function
	"Says how the constraint reads: equal(?x, ?y)."
	return equalName + "(" + termText(self.left) + ", " + termText(self.right) + ")"
end function

// A comparison is the one constraint that reads its terms arithmetically. Text would
// put "9" after "18", and MiniScript will not compare a string with a number at all,
// so a side that is not a number ends the branch rather than passing for a zero.

// A comparison is written as a call, like every other condition in a body, so the format
// keeps one shape: less-than-or-equal(?n, 18). The names are words, as the predicates
// are, and the symbol each stands for is what the check reads.
comparisonNames = {
	"less-than": "<",
	"less-than-or-equal": "<=",
	"greater-than": ">",
	"greater-than-or-equal": ">=",   // this comma is required: the entry ends the line
}

Comparison = {}

Comparison.make = function(symbol, left, right)
	"Builds a numeric comparison: two terms, and the order they must stand in."
	c = new Comparison
	c.symbol = symbol
	c.left = left
	c.right = right
	return c
end function

Comparison.text = function
	"Says how the comparison reads: less-than-or-equal(?n, 18)."
	return comparisonCall(self.symbol) + "(" + termText(self.left) + ", " + termText(self.right) + ")"
end function

comparisonCall = function(symbol)
	"Names a symbol the way a body writes it: '<=' is less-than-or-equal."
	for name in comparisonNames.indexes
		if comparisonNames[name] == symbol then return name
	end for
	return symbol
end function

// years-since is the one constraint that computes: it reads a date and the whole years
// between it and the day the search runs, and binds the side that is still a variable. It is
// what lets a rule work out a value, which the goals alone cannot do - a goal proves a fact,
// and a comparison only reads numbers that are already there. An age is one use of it, a
// birthdate being a date like any other.
//
// The day is the host's today unless a caller pins one, which is what the suite does so a
// check cannot quietly change on somebody's birthday:
//
//   triples.today = {"year": 2019, "month": 4, "day": 1}

sinceName = "years-since"

today = null

dayToday = function
	"The day an age is counted from: the one a caller pinned, or the host's today."
	if today != null then return today
	parts = _dateStr(_dateVal, "yyyy-MM-dd").split("-")
	return {"year": val(parts[0]), "month": val(parts[1]), "day": val(parts[2])}
end function

dayText = function(day)
	"One day as a fact writes it: yyyy-MM-dd, the month and day padded the way a date is."
	// A caller may pin the day in the text a fact carries rather than as its three parts.
	if day isa string then return day
	month = str(day.month)
	if month.len < 2 then month = "0" + month
	date = str(day.day)
	if date.len < 2 then date = "0" + date
	return str(day.year) + "-" + month + "-" + date
end function

freshToday = function(fact)
	"Whether a question can read this fact as today's: one typed here has no day and never ages, and one a service answered is fresh the day it was fetched."
	if fact == null then return false
	if fact.source == null then return true
	return fact.fetched == dayText(dayToday())
end function


yearsSince = function(text, on)
	"The whole years from a yyyy-MM-dd date to a day, or null when that is not a date or it has not arrived yet."
	// The reader that owns the shape is what says whether the text is a date, so a value it
	// refuses is not counted here: the host would roll 2019-02-30 forward like any other day.
	date = temporal.DateTime.receive(text, "date")
	if date isa error then return null
	years = on.year - date.year
	if on.month < date.month or (on.month == date.month and on.day < date.day) then years = years - 1
	if years < 0 then return null
	return years
end function

YearsSince = {}

YearsSince.make = function(date, years)
	"Builds a 'this date is this many years before the day the search runs' constraint."
	c = new YearsSince
	c.date = date
	c.years = years
	return c
end function

YearsSince.text = function
	"Says how the constraint reads: years-since(2019-04-01, ?n)."
	return sinceName + "(" + termText(self.date) + ", " + termText(self.years) + ")"
end function

yearsSinceBinds = function(constraint, binds)
	"The bindings that make the years the date's, or null when the branch ends."
	date = constraintValue(constraint.date, binds)
	wanted = substitute(constraint.years, binds)
	if date == null then return null
	years = yearsSince(date, dayToday())
	if years == null then return null
	if wanted isa Var then return unifyTerms(constraint.years, years, binds)
	if not (wanted isa number) then return null
	if wanted != years then return null
	return binds
end function

// The clock is the machine's, read to the second and advancing with the process: _dateVal is
// fixed when the program starts, so the time since then is added to it rather than trusting the
// constant. A caller may pin the moment - triples.clock - the way triples.today pins the day,
// and the session pins one for the length of a question, so two conditions of one question
// cannot straddle a second and answer from two different nows.

startedAt = time
clock = null         // the moment a caller pinned, as the suite does
questionClock = null // the moment the question being answered runs at
sessionPlace = null  // where the machine is, when a lookup said so
machineOffset = null // how far the machine's clock stands from UTC, in seconds
placeOffsets = {}    // how far each place's clock stands from UTC, in seconds

hostNow = function
	"The machine's clock now, to the second."
	return _dateStr(_dateVal + (time - startedAt), "yyyy-MM-dd HH:mm:ss")
end function

momentNow = function
	"The moment a search runs at: the one pinned, the one its question began at, or the clock now."
	if clock != null then return clock
	if questionClock != null then return questionClock
	return hostNow()
end function

beginQuestion = function
	"Fixes the moment this question runs at, so every condition of it reads one clock."
	questionClock = hostNow()
end function

// A call is worked out when a moment is needed: '@' evaluates it, and the moment it yields
// matches a fact's the way a written one does. The clock is a value rather than a fact -
// has-time writes the moment in the field it is given, add-hours shifts one - so neither is
// stored, saved, or listed as a fact the session holds.

evaluate = function(term, binds)
	"The bindings a term leaves and the value it stands for, or null when it cannot be read yet: a call is worked out, and a variable still free is waiting."
	if binds == null then binds = {}
	if term isa Var then
		value = deref(term, binds)
		if value isa Var then return null
		return {"binds": binds, "value": value}
	end if
	if not (term isa Call) then return {"binds": binds, "value": term}
	if term.name == "has-time" then
		// has-time(<where>, ?now) is the time it is there: session is the machine's own clock,
		// a place is that place's, and neither is a fact the session keeps.
		if term.args.len != 2 then return null
		subject = evaluate(term.args[0], binds)
		if subject == null then return null
		place = subject.value
		moment = null
		if place == "session" or (sessionPlace != null and place == sessionPlace) then
			// The machine is at this place, so its own clock is the place's clock.
			moment = momentNow()
		else if machineOffset != null and place isa string and
				placeOffsets.hasIndex(place) != 0 then
			// Somewhere else: its clock is the machine's, moved by how the two stand from UTC -
			// the one part of a zone a name alone cannot give.
			moment = shiftMoment(momentNow(), (placeOffsets[place] - machineOffset) / 3600)
		end if
		if moment == null then return null
		held = deref(term.args[1], subject.binds)
		if held isa Var then
			return {"binds": withBinding(subject.binds, held.name, moment), "value": moment}
		end if
		if held == moment then return {"binds": subject.binds, "value": moment}
		return null
	end if
	if term.name == "add-hours" then
		// add-hours(moment, hours) is the moment that many hours later.
		if term.args.len != 2 then return null
		from = evaluate(term.args[0], binds)
		if from == null then return null
		by = evaluate(term.args[1], from.binds)
		if by == null or not (by.value isa number) then return null
		return {"binds": by.binds, "value": shiftMoment(from.value, by.value)}
	end if
	return null
end function

shiftMoment = function(held, hours)
	"The moment that many hours later, or null when the value is not one."
	if not (held isa string) or held[:1] == "[" then return null
	moment = temporal.DateTime.receive(held)
	if moment isa error then return null
	if moment.kind != "datetime" then return null
	return moment.addSeconds(hours * 3600).str("yyyy-MM-dd HH:mm:ss")
end function

isConstraint = function(term)
	"Says whether a term names a constraint, which a body checks rather than a line storing or asking it."
	if not (term isa string) then return false
	return term == notEqualName or term == equalName or term == sinceName or
		comparisonNames.hasIndex(term) != 0
end function

comparisonHolds = function(constraint, binds)
	"Says whether a comparison holds: both sides must be numbers, so another type cannot slip through as zero."
	left = constraintValue(constraint.left, binds)
	right = constraintValue(constraint.right, binds)
	if not (left isa number) or not (right isa number) then return false
	if constraint.symbol == "<=" then return left <= right
	if constraint.symbol == ">=" then return left >= right
	if constraint.symbol == "<" then return left < right
	return left > right
end function

holdsConstraint = function(constraint, binds)
	"Says whether a constraint holds under the current bindings."
	if constraint isa Comparison then return comparisonHolds(constraint, binds)
	if constraint isa NotEqual then
		left = constraintValue(constraint.left, binds)
		right = constraintValue(constraint.right, binds)
		if left == null or right == null then return false
		return left != right
	end if
	return false
end function

// equal is applied rather than checked: unifying its two terms returns the bindings the
// equality extends, and null when they cannot agree. unifyTerms already reads two terms the
// one way equal needs - the same value holds, and a variable takes the other side's - so an
// equal is exactly one unification whose bindings are kept.

constraintValue = function(term, binds)
	"The value a constraint field stands for: a call is worked out and anything else is read through the bindings. Null when a call cannot be read."
	if term isa Call then
		evaluated = evaluate(term, binds)
		if evaluated == null then return null
		return evaluated.value
	end if
	return substitute(term, binds)
end function

equalBinds = function(constraint, binds)
	"The bindings that make the two terms the same one, or null when they cannot be: a call on either side is worked out first, since a call is a value and not the text it is written as."
	settled = binds
	left = constraint.left
	if left isa Call then
		evaluated = evaluate(left, settled)
		if evaluated == null then return null
		settled = evaluated.binds
		left = evaluated.value
	end if
	right = constraint.right
	if right isa Call then
		evaluated = evaluate(right, settled)
		if evaluated == null then return null
		settled = evaluated.binds
		right = evaluated.value
	end if
	return unifyTerms(left, right, settled)
end function

applyConstraint = function(constraint, binds)
	"The bindings a constraint leaves, or null when the branch ends: the ones it was given, unless it bound something."
	if constraint isa Equal then return equalBinds(constraint, binds)
	if constraint isa YearsSince then return yearsSinceBinds(constraint, binds)
	if holdsConstraint(constraint, binds) then return binds
	return null
end function

// A line typed at the prompt can name a constraint instead of a predicate, and when every
// field of it is a value the line says something that can be read off: less-than(5, 3) says
// five is below three, which it is not, and years-since("1948-03-14", 78) says the years are
// 78. constraintFrom turns the parsed line into the constraint a body would check, and
// settledHolds reads it, so the prompt checks a constraint the one way a rule body does
// rather than inventing a second reading of the names.

constraintFrom = function(triple)
	"The constraint a predicate(subject, object) line names, or null when its name is not one of the constrained ones."
	name = triple.predicate
	if not (name isa string) then return null
	if name == equalName then return Equal.make(triple.subject, triple.object)
	if name == notEqualName then return NotEqual.make(triple.subject, triple.object)
	if name == sinceName then return YearsSince.make(triple.subject, triple.object)
	if comparisonNames.hasIndex(name) == 0 then return null
	return Comparison.make(comparisonNames[name], triple.subject, triple.object)
end function

settledHolds = function(constraint)
	"Says whether a constraint whose fields are all values holds, by the reading a rule body gives it; fields still holding variables are the caller's to refuse."
	// equal is the one that binds, and here there is nothing left to bind: two values are the
	// same one or they are not.
	if constraint isa Equal then
		left = constraintValue(constraint.left, null)
		right = constraintValue(constraint.right, null)
		if left == null or right == null then return false
		return left == right
	end if
	// years-since counts its date on the day the search runs, and a date the calendar does not
	// have has no years at all - which a body reads as a check that failed, not as a refusal,
	// and so does this.
	if constraint isa YearsSince then
		years = yearsSince(constraint.date, dayToday())
		if years == null then return false
		if not (constraint.years isa number) then return false
		return years == constraint.years
	end if
	// A comparison with a side that is not a number fails rather than passing for a zero, and
	// not-equal asks only that the two differ, so both are what holdsConstraint already says.
	return holdsConstraint(constraint, null)
end function

// ── Proof search ─────────────────────────────────────────────────────────────

// proveGoals answers a goal, proveConditions proves a rule body, and the two
// records they pass around have these shapes:
//
//   answer = {"goal": SpoTriple, "binds": map, "reasons": [reason]}
//   reason = {"rule": Rule or null, "conditions": [answer]}
//   results = {"list": [answer], "byText": {rendered goal: answer}}
//
// An answer keeps every way it was proved; a reason is one of them - a fact when
// rule is null, otherwise the rule plus the answers that proved its conditions.
// A results record gathers answers in order and by rendered goal, so a goal that
// is proved several ways still appears once.

// ── Alternatives ─────────────────────────────────────────────────────────────
// A condition is usually one triple, and sometimes a constraint. It can also be a
// choice: or(...) holds one body per alternative, and any one of them settles what
// the condition asks. Each alternative is a list of conditions, so or(...) nests in
// a body the way and(...) does, and may hold and(...) as one of its alternatives.
//
// A not(...) is the other grouping. It holds one body, and the condition holds when that
// body has no proof at all - it says what the facts do not, as in "nobody is ?x's
// sibling". It binds nothing and adds no step to a proof, because an absence has no
// derivation to show, only a search that came back empty.

Or = {}

Or.make = function(alternatives)
	"Builds an 'any one of these bodies holds' condition."
	o = new Or
	o.alternatives = alternatives
	return o
end function

Or.text = function
	"Reads as or(a, b), with and(...) around an alternative that holds several conditions."
	parts = []
	for alternative in self.alternatives
		parts.push(alternativeText(alternative))
	end for
	return "or(" + parts.join(", ") + ")"
end function

alternativeText = function(conditions)
	"One body as it reads: its one condition, or and(...) around several."
	texts = []
	for condition in conditions
		texts.push(condition.text)
	end for
	if texts.len == 1 then return texts[0]
	return "and(" + texts.join(", ") + ")"
end function

Not = {}

Not.make = function(body)
	"Builds a 'this body has no proof' condition."
	n = new Not
	n.body = body
	return n
end function

Not.text = function
	"Reads as not(a), with and(...) around a body that holds several conditions."
	return "not(" + alternativeText(self.body) + ")"
end function

renameCounter = {"uses": 0}

uniqueSuffix = function()
	"A suffix no other rule use has had, so one use cannot shadow another."
	renameCounter.uses = renameCounter.uses + 1
	return "_" + renameCounter.uses
end function

renameTerm = function(term, suffix)
	"Copies a term, renaming every variable: ?x becomes ?x_3."
	if term isa Var then return var(term.name + suffix)
	if term isa Call then
		args = []
		for arg in term.args
			args.push(renameTerm(arg, suffix))
		end for
		return Call.make(term.name, args)
	end if
	return term
end function

renameTriple = function(triple, suffix)
	"Copies a triple, renaming the variables in its fields."
	if triple isa SpoTriple then
		return SpoTriple.make(renameTerm(triple.subject, suffix),
			renameTerm(triple.predicate, suffix), renameTerm(triple.object, suffix))
	end if
	return triple
end function

renameConstraint = function(constraint, suffix)
	"Copies a constraint, renaming the variables it mentions."
	if constraint isa YearsSince then
		return YearsSince.make(renameTerm(constraint.date, suffix),
			renameTerm(constraint.years, suffix))
	end if
	if constraint isa Equal then
		return Equal.make(renameTerm(constraint.left, suffix),
			renameTerm(constraint.right, suffix))
	end if
	if constraint isa Comparison then
		return Comparison.make(constraint.symbol, renameTerm(constraint.left, suffix),
			renameTerm(constraint.right, suffix))
	end if
	if constraint isa NotEqual then
		return NotEqual.make(renameTerm(constraint.left, suffix),
			renameTerm(constraint.right, suffix))
	end if
	return constraint
end function

standardizeApart = function(candidate)
	"A fresh {head, body} copy of a rule, safe to use alongside other uses of it."
	suffix = uniqueSuffix()
	return {"head": renameTriple(candidate.head, suffix),
		"body": renameConditions(candidate.body, suffix)}
end function

renameConditions = function(conditions, suffix)
	"Every condition renamed, in order."
	return mapWith(conditions, @renameCondition, suffix)
end function

renameCondition = function(condition, suffix)
	"One condition renamed: a goal as a triple, a grouping by its body, a constraint as it is."
	if condition isa Not then return Not.make(renameConditions(condition.body, suffix))
	if condition isa Or then
		alternatives = []
		for alternative in condition.alternatives
			alternatives.push(renameConditions(alternative, suffix))
		end for
		return Or.make(alternatives)
	end if
	if condition isa SpoTriple then return renameTriple(condition, suffix)
	return renameConstraint(condition, suffix)
end function

canonicalText = function(triple)
	"Renders a triple with its variables numbered by first appearance, so goals that differ only in variable names render the same."
	return canonicalLabels(triple.parts, {}).join("|")
end function

canonicalLabels = function(parts, names)
	"One label per field, numbering each variable the first time it is seen."
	return mapWith(parts, @canonicalLabel, names)
end function

canonicalLabel = function(part, names)
	"One field's label: ?N for a variable, the field itself for anything else."
	if not (part isa Var) then return part
	if names.hasIndex(part.name) == 0 then names[part.name] = "?" + (names.len + 1)
	return names[part.name]
end function

goalKey = function(goal, binds)
	"Identifies a goal as it stands under the current bindings, for loop detection."
	grounded = substitute(goal, binds)
	if grounded isa SpoTriple then return canonicalText(grounded)
	return str(termText(grounded))
end function

proveGoals = function(goal, facts, rules, depth, binds=null, open=null, index=null)
	"Every answer to goal, at most depth rules deep, each with all its derivations; open is the chain of goals being proved, so a loop stops that branch, and index is the facts by predicate, built once and handed down."
	if index == null then index = factsByPredicate(facts)
	path = enterGoal(goal, binds, open)
	if path == null then return []
	results = emptyResults()
	// A call's name is answered by the clock rather than by a fact, so the time itself can be
	// asked - has-time(session, ?now) - the same way a moment is worked out inside a question.
	if isCallName(goal.predicate) then
		evaluated = evaluate(Call.make(goal.predicate, [goal.subject, goal.object]), binds)
		if evaluated != null then
			mergeAnswer(results, goal, evaluated.binds, {"rule": null, "conditions": []})
		end if
		return results.list
	end if
	// A fact is a derivation on its own; a rule is one derivation per way its body
	// proves, so both are collected from their matches and merged the same way.
	for matched in matchingFacts(goal, facts, binds, index)
		mergeAnswer(results, goal, matched.binds, {"rule": null, "conditions": []},
			matched.fact.at, matched.fact.confidence, matched.fact.source, matched.fact.fetched)
	end for
	if depth <= 0 then return results.list
	for candidate in matchingRules(goal, rules, binds)
		for proved in proveConditions(candidate.body, facts, rules, depth - 1, candidate.binds,
			path, index)
			// A conclusion holds for as long as the readings its body stood on, was read from the
			// same place, and is only as sure as the least sure of them: the annotations of the
			// first condition that carries any, and the weakest confidence. A body of bare facts
			// carries none, so it concludes nothing about when or from where, which is what a rule
			// over the family's facts says.
			at = null
			confidence = 100
			source = null
			fetched = null
			for proof in proved.proofs
				if at == null and proof.at != null then at = proof.at
				if source == null and proof.source != null then source = proof.source
				if fetched == null and proof.fetched != null then fetched = proof.fetched
				if proof.confidence < confidence then confidence = proof.confidence
			end for
			mergeAnswer(results, goal, proved.binds, {"rule": candidate.rule, "conditions": proved.proofs},
				at, confidence, source, fetched)
		end for
	end for
	return results.list
end function

emptyResults = function()
	"Where answers gather: the list in order, and the same answers by rendered goal."
	return {"list": [], "byText": {}}
end function

enterGoal = function(goal, binds, open)
	"The chain of goals being proved with this one added, or null when it is already on it."
	if open == null then open = {}
	key = goalKey(goal, binds)
	if open.hasIndex(key) then return null
	// A new map, so one branch's ancestors do not prune its siblings.
	return withBinding(open, key, 1)
end function

// A ground predicate can only meet the same one, so those pairs are ruled out before
// anything is copied or unified: standardizeApart builds a fresh copy of every rule it
// is handed, and unifying predicates that cannot agree settles nothing.

predicatesMeet = function(goal, triple, binds)
	"Says whether a goal and a candidate could still agree on their predicates."
	wanted = deref(goal.predicate, binds)
	if wanted isa Var then return true
	// The candidate's variables are renamed before it is used, so they are not this
	// goal's to resolve through its bindings; a variable predicate there meets anything.
	if triple.predicate isa Var then return true
	return wanted == triple.predicate
end function

// A goal whose subject or object has been settled can only be met by a candidate
// carrying that same one. Comparing two fields costs a fraction of the unification it
// can replace, so it happens first. The check is one-sided: a variable anywhere - in
// the goal or in the candidate - can still meet anything.

settledTerm = function(term, binds)
	"The term once the bindings are applied, or null while it is still a variable."
	if not (term isa Var) then return term
	if binds == null then return null
	value = deref(term, binds)
	if value isa Var then return null
	return value
end function

meetsSettled = function(wanted, candidate)
	"Says whether a settled field could still agree with a candidate's."
	if candidate isa Var then return true
	return wanted == candidate
end function

fieldsMeet = function(goal, triple, binds)
	"Says whether the goal's subject and object could still agree with a candidate's."
	wanted = settledTerm(goal.subject, binds)
	if wanted != null then
		if not meetsSettled(wanted, triple.subject) then return false
	end if
	wanted = settledTerm(goal.object, binds)
	if wanted != null then
		if not meetsSettled(wanted, triple.object) then return false
	end if
	return true
end function

// Looking at every fact for every goal is most of what a query costs, and most of
// those looks are hopeless: a goal names one predicate, so only the facts carrying
// it can answer. They are grouped by predicate once per query and handed down, and
// a goal whose predicate is still a variable - or a knowledge base holding a fact
// with a variable predicate - falls back to the whole list.

factsByPredicate = function(facts)
	"The facts grouped by their predicate, or null when one of them has a variable predicate and so could meet any goal."
	index = {}
	for fact in facts
		if fact.predicate isa Var then return null
		if index.hasIndex(fact.predicate) then
			index[fact.predicate].push(fact)
		else
			index[fact.predicate] = [fact]
		end if
	end for
	return index
end function

candidateFacts = function(goal, facts, binds, index)
	"The facts worth trying for this goal: the ones with its predicate, or all of them when that is not settled."
	if index == null then return facts
	wanted = deref(goal.predicate, binds)
	if wanted isa Var then return facts
	if index.hasIndex(wanted) == 0 then return []
	return index[wanted]
end function

matchingFacts = function(goal, facts, binds, index=null)
	"The bindings and the fact of every fact that meets the goal, in order: the annotations a fact carries are not in the bindings, so the fact comes back with them."
	matches = []
	for fact in candidateFacts(goal, facts, binds, index)
		if not predicatesMeet(goal, fact, binds) then continue
		if not fieldsMeet(goal, fact, binds) then continue
		matched = unify(goal, fact, binds)
		if matched != null then matches.push({"binds": matched, "fact": fact})
	end for
	return matches
end function

matchingRules = function(goal, rules, binds)
	"Every rule whose head meets the goal: the rule, a fresh copy of its body, and the bindings."
	matches = []
	for candidate in rules
		if not predicatesMeet(goal, candidate.head, binds) then continue
		fresh = standardizeApart(candidate)
		matched = unify(fresh.head, goal, binds)
		if matched != null then
			matches.push({"rule": candidate, "body": fresh.body, "binds": matched})
		end if
	end for
	return matches
end function

proveConditions = function(conditions, facts, rules, depth, binds, open=null, index=null)
	"Proves each condition in turn: a goal by search, a constraint by checking or binding, or(...) by one alternative, and not(...) by finding no proof."
	// Any one alternative settles the choice, and the rest of the body follows it,
	// so every way through an alternative is a way through the body.
	if conditions.len > 0 and (conditions[0] isa Or) then
		results = []
		for alternative in conditions[0].alternatives
			for proved in proveConditions(alternative + conditions[1:], facts, rules, depth,
				binds, open, index)
				results.push(proved)
			end for
		end for
		return results
	end if
	// A negation is met exactly when the body it holds has no proof, so one proof ends
	// the branch. It binds nothing and proves nothing, so it adds no step to the tree.
	if conditions.len > 0 and (conditions[0] isa Not) then
		if proveConditions(conditions[0].body, facts, rules, depth, binds, open, index).len > 0 then
			return []
		end if
		return proveConditions(conditions[1:], facts, rules, depth, binds, open, index)
	end if
	if conditions.len == 0 then return [{"binds": binds, "proofs": []}]
	first = conditions[0]
	if not (first isa SpoTriple) then
		// A constraint either holds or the branch ends; it proves nothing, so it
		// contributes no proof to the tree. equal can also bind, and what it leaves is
		// what the conditions after it are judged against.
		settled = applyConstraint(first, binds)
		if settled == null then return []
		return proveConditions(conditions[1:], facts, rules, depth, settled, open, index)
	end if
	results = []
	for proved in proveGoals(first, facts, rules, depth, binds, open, index)
		for rest in proveConditions(conditions[1:], facts, rules, depth, proved.binds, open,
			index)
			results.push({"binds": rest.binds, "proofs": [proved] + rest.proofs})
		end for
	end for
	return results
end function

mergeAnswer = function(results, goal, binds, reason, at=null, confidence=100, source=null,
	fetched=null)
	"One entry per answer, holding every way that answer was proved; the annotations are the fact's, or the readings' a rule's body stood on, since the goal is only a pattern."
	// The key is the whole line, so two readings of the same value at different hours, or from
	// different services, are two answers rather than one with two derivations.
	key = answerTriple(goal, binds, at, confidence, source, fetched).text
	if results.byText.hasIndex(key) == 0 then
		results.byText[key] = {"goal": goal, "binds": binds, "at": at,
			"confidence": confidence, "source": source, "fetched": fetched, "reasons": []}
		results.list.push(results.byText[key])
	end if
	results.byText[key].reasons.push(reason)
end function

speak = function(triple, nlp=0)
	"Says a triple in the form a run asked for: the sentence it reads as when nlp is on, and the fact it is otherwise."
	if nlp then return triple.sentence
	return triple.text
end function

reasonText = function(reason, nlp=0)
	"Where one derivation came from: a fact, or the rule that concluded it - said as sentences when nlp asks for them."
	if reason.rule == null then return "fact"
	if nlp then return "rule " + nlRuleText(reason.rule)
	return "rule " + reason.rule.text
end function

nlRuleText = function(rule)
	"Says a rule the way its parts answer: the head as a sentence, and so each triple of its body - a constraint has no sentence, so it keeps the form it is written in."
	conditions = []
	for condition in rule.body
		if condition isa SpoTriple then
			conditions.push(condition.sentence)
		else
			conditions.push(condition.text)
		end if
	end for
	if conditions.len == 0 then return rule.head.sentence + " => (no conditions)"
	return rule.head.sentence + " => " + conditions.join(", ")
end function

proofLines = function(answer, indent="", nlp=0)
	"Describes every derivation of an answer, with the conditions behind each, said as sentences when nlp asks for them."
	lines = []
	appendDerivations(answer.goal, answer.binds, answer.reasons, indent, lines, nlp,
		answer.at, answer.confidence, answer.source, answer.fetched)
	return lines
end function

appendDerivations = function(goal, binds, reasons, indent, lines, nlp=0, at=null, confidence=100,
	source=null, fetched=null)
	"Appends each derivation's line, then the block behind each of its conditions."
	for reason in reasons
		lines.push(indent + speak(answerTriple(goal, binds, at, confidence, source, fetched), nlp) +
			"  => " + reasonText(reason, nlp))
		appendConditions(reason.conditions, indent + "  ", lines, nlp)
	end for
end function

appendConditions = function(conditions, indent, lines, nlp=0)
	"Appends the block behind each proved condition, in order."
	for condition in conditions
		appendDerivations(condition.goal, condition.binds, condition.reasons, indent, lines, nlp,
			condition.at, condition.confidence, condition.source, condition.fetched)
	end for
end function

// ── What would be needed ──────────────────────────────────────────────────────

// A query can fail because nothing in the knowledge base matches it. Everything
// below answers the question that follows: which facts would have to be added for
// a solution to exist? There is one answer per way the goal could be proved - a
// fact with the goal's own shape, or a rule whose body still needs something - and
// each answer is the facts that way would need, with the rule that would use them.

clockNeeds = function(goal, facts, binds)
	"The fact that would give this clock a reading to stand on: a place's offset, when the session holds none it can read a clock by - today's, or a typed one."
	if binds == null then binds = {}
	place = goal.subject
	if place isa Var then
		place = deref(place, binds)
		if place isa Var then return []
	end if
	// The machine's own clock is the host's, and the place the session is located at reads from
	// it, so neither needs an offset: the offset is what another place is read against.
	if not (place isa string) then return []
	if place == "session" or (sessionPlace != null and place == sessionPlace) then return []
	if offsetHeld(place, facts) then return []
	return [{"rule": null, "needs": [
		missingFact(SpoTriple.make(place, "has-utc-offset", var("offset")), false)]}]
end function


offsetHeld = function(place, facts)
	"Whether the session holds an offset it can read a clock by: a typed one, or one a service answered today, since a place may have moved its clocks twice a year since."
	today = dayText(dayToday())
	for fact in facts
		if fact.predicate != "has-utc-offset" then continue
		if termText(fact.subject) != termText(place) then continue
		if not (fact.object isa number) then continue
		if freshToday(fact) then return true
	end for
	return false
end function


needsFor = function(goal, facts, rules, depth, binds=null, open=null)
	"Every way goal could still be answered: the facts it needs, and the rule that would use them; asked only for a goal the search could not prove."
	path = enterGoal(goal, binds, open)
	if path == null then return []
	// A clock is read from the machine and the offsets a service answered with, so a clock the
	// goal cannot read is settled by the place's offset rather than by a fact shaped like the
	// call: asking for that fact is what has a service answer with today's, where yesterday's
	// offset is not one to read a clock by.
	if goal.predicate == "has-time" then return clockNeeds(goal, facts, binds)
	// The other call's name is read from the clock too, so nothing can be added for it.
	if isCallName(goal.predicate) then return []
	// One more fact, shaped like the goal, would answer it outright.
	options = []
	if matchingFacts(goal, facts, binds).len == 0 then
		options.push({"rule": null, "needs": [missingFact(substitute(goal, binds), false)]})
	end if
	if depth <= 0 then return options
	for candidate in matchingRules(goal, rules, binds)
		for result in bodyResults(candidate, facts, rules, depth, path)
			if result.needs.len > 0 then
				options.push({"rule": candidate.rule, "needs": result.needs})
			end if
		end for
	end for
	return options
end function

needsConditions = function(conditions, facts, rules, depth)
	"Every way a body could still be met: the facts it needs, in the order it would meet them; asked only for a body no proof answered, and a body has no head, so no rule is cited."
	results = bodyRequirements(conditions, facts, rules, depth, null, {}, {}, 0)
	// A body that claims it needs nothing was met one condition at a time rather than all at
	// once - the reading bodyResults takes for a rule - so it is reported again with the
	// conditions the proofs left open.
	for result in results
		if result.needs.len == 0 then
			results = bodyRequirements(conditions, facts, rules, depth, null, {}, {}, 1)
			break
		end if
	end for
	// A condition the search already proves needs no fact, and a body whose every condition
	// is settled this way needs nothing at all: nothing is left to report.
	options = []
	for result in results
		if result.needs.len > 0 then options.push({"rule": null, "needs": result.needs})
	end for
	return options
end function

bodyResults = function(candidate, facts, rules, depth, path)
	"The ways one rule could answer the goal, re-read when a body claims it needs nothing."
	results = bodyRequirements(candidate.body, facts, rules, depth - 1, candidate.binds, path, {}, 0)
	// The goal has no proof - that is why the report is being asked for - so a body that
	// claims it needs no new fact was met one condition at a time, not all at once. Read
	// again, reporting the conditions the proofs left open, it says what it needs.
	for result in results
		if result.needs.len == 0 then
			return bodyRequirements(candidate.body, facts, rules, depth - 1, candidate.binds, path, {}, 1)
		end if
	end for
	return results
end function

bodyRequirements = function(conditions, facts, rules, depth, binds, open, newVars, reportOpen)
	"Every way of proving a rule body: the bindings it would leave, and the facts it would still need; newVars are the variables the facts found so far would bind, and a not(...) is checked rather than asked for."
	// Each alternative is a body of its own, so it is one more way this body could be
	// met, and it is reported with the facts its own conditions would need.
	if conditions.len > 0 and (conditions[0] isa Or) then
		options = []
		for alternative in conditions[0].alternatives
			for option in bodyRequirements(alternative + conditions[1:], facts, rules, depth,
				binds, open, newVars, reportOpen)
				options.push(option)
			end for
		end for
		return options
	end if
	// A negation asks for no fact: nothing added can make an absence true, so it is
	// checked against what is known, and a body it already proves rules this way out.
	if conditions.len > 0 and (conditions[0] isa Not) then
		if proveConditions(conditions[0].body, facts, rules, depth, binds, open).len > 0 then
			return []
		end if
		return bodyRequirements(conditions[1:], facts, rules, depth, binds, open, newVars, reportOpen)
	end if
	if conditions.len == 0 then return [{"binds": binds, "needs": []}]
	first = conditions[0]
	if not (first isa SpoTriple) then
		// A constraint is checked here rather than proved, so it asks for no fact; one
		// that binds still settles a variable for the conditions after it.
		settled = applyConstraint(first, binds)
		if settled != null then
			return bodyRequirements(conditions[1:], facts, rules, depth, settled, open, newVars,
				reportOpen)
		end if
		// It may be waiting on a fact this body has already listed, which would settle the
		// field it cannot read yet - the birthdate an age is counted from, say. It asks for
		// nothing itself, and the fact it waits on is already in the report. One that binds
		// settles a field of its own once it can be judged, so a condition after it waiting on
		// that field waits on the same fact: years-since gives ?n a value, and a comparison
		// reading ?n is carried along rather than ending the branch.
		if promisedBy(constraintTerms(first), binds, newVars) then
			return bodyRequirements(conditions[1:], facts, rules, depth, binds, open,
				promiseVars(newVars, settles(first)), reportOpen)
		end if
		return []
	end if
	options = []
	// The bindings a condition proves carry into the conditions after it, so each of
	// them is judged against what this one settled.
	for head in firstRequirements(first, facts, rules, depth, binds, open, newVars, reportOpen)
		for tail in bodyRequirements(conditions[1:], facts, rules, depth, head.binds, open,
			extendVars(newVars, head.needs), reportOpen)
			options.push({"binds": tail.binds, "needs": head.needs + tail.needs})
		end for
	end for
	return options
end function

firstRequirements = function(condition, facts, rules, depth, binds, open, newVars, reportOpen)
	"The ways a body's condition can be met: what it settles, and what it adds to the report."
	grounded = substitute(condition, binds)
	// A fact still to be added would bind these variables, so this condition cannot
	// be judged against what is known. When the facts found so far bind all of them,
	// it is a condition to check rather than a fact to add.
	if newVars.len > 0 and hasUnknowns(grounded) then
		return [{"binds": binds, "needs": [missingFact(grounded, coveredBy(grounded, newVars))]}]
	end if
	proofs = proveGoals(condition, facts, rules, depth, binds, open)
	if proofs.len == 0 then
		return mapWith(needsFor(condition, facts, rules, depth, binds, open), @requirement, binds)
	end if
	settled = agreeingBinds(proofs)
	// Proofs can disagree about a condition's variables, and then it settles nothing for
	// the conditions after it. Asked to report the conditions left open, it is a fact to
	// add instead: no fact of another shape can join this body's conditions into a proof.
	if reportOpen and hasUnknowns(substitute(condition, settled)) then
		return [{"binds": binds, "needs": [missingFact(grounded, false)]}]
	end if
	return [{"binds": settled, "needs": []}]
end function

agreeingBinds = function(proofs)
	"The bindings every proof agrees on, so a report names a value only when the search forces it."
	agreed = proofs[0].binds
	for proof in proofs[1:]
		shared = {}
		for name in agreed.indexes
			if proof.binds.hasIndex(name) and proof.binds[name] == agreed[name] then
				shared[name] = agreed[name]
			end if
		end for
		agreed = shared
	end for
	return agreed
end function

requirement = function(option, binds)
	"One of needsFor's options as a step of a body: its facts, and the bindings that stay as they are."
	return {"binds": binds, "needs": option.needs}
end function

missingFact = function(triple, settled)
	"One fact the report mentions, and whether a fact already listed would settle it."
	return {"triple": triple, "settled": settled}
end function

constraintTerms = function(constraint)
	"The fields a constraint must have settled before it can be judged: years-since binds its second field, so only its date has to be read."
	if constraint isa YearsSince then return [constraint.date]
	return [constraint.left, constraint.right]
end function

settles = function(constraint)
	"The fields a constraint binds once it can be judged: years-since's years, and nothing for the others."
	if constraint isa YearsSince then return [constraint.years]
	return []
end function

promisedBy = function(terms, binds, newVars)
	"Says whether a fact already listed would settle every field still free, so the check can only be judged once that fact exists."
	waiting = false
	for term in terms
		if term isa Var then
			value = substitute(term, binds)
			if value isa Var then
				waiting = true
				// A rule's variables are renamed and the head is unified with the goal's, so one free
				// variable can stand under two names here: the one the constraint writes and the one
				// it derefs to. Either of them promised is the same promise.
				if newVars.hasIndex(term.name) == 0 and newVars.hasIndex(value.name) == 0 then
					return false
				end if
			end if
		end if
	end for
	return waiting
end function

coveredBy = function(triple, newVars)
	"Says whether the facts already found would bind every variable left in this one."
	for part in unboundVars(triple)
		if newVars.hasIndex(part.name) == 0 then return false
	end for
	return true
end function

extendVars = function(newVars, needs)
	"The variables these missing facts would bind, added to the ones already promised: a moment asked as a variable is one of them, so the constraint reading it waits on this fact."
	terms = []
	for need in needs
		terms = terms + need.triple.parts + varsIn(need.triple.at)
	end for
	return promiseVars(newVars, terms)
end function

promiseVars = function(newVars, terms)
	"The variables these terms would bind, added to the ones already promised."
	extended = newVars + {}
	for term in terms
		if term isa Var then extended[term.name] = 1
	end for
	return extended
end function

unboundVars = function(triple)
	"The fields of a triple that are still variables, in order, and the moment asked for after them - which may be a call holding variables of its own."
	vars = []
	for part in triple.parts
		if part isa Var then vars.push(part)
	end for
	vars = vars + varsIn(triple.at)
	return vars
end function

varsIn = function(term)
	"The variables a term holds, a call's arguments included: ?now inside add-hours(has-time(session, ?now), 9) is one the question still has to settle."
	if term isa Var then return [term]
	if term isa Call then
		found = []
		for arg in term.args
			found = found + varsIn(arg)
		end for
		return found
	end if
	return []
end function

hasUnknowns = function(triple)
	"Says whether any field of a triple is still a variable."
	return unboundVars(triple).len > 0
end function

// The report is built from pieces, so it can be painted without the engine knowing
// what a color is: a style is a map of role -> the text placed before that role's
// pieces, plus the "normal" text that ends it. A role the caller leaves out gets
// nothing, so the plain style, which is all empty strings, prints exactly as the
// checks expect it. paint is the one place that reads the map, so the report, the
// program that runs one query, and the session at the prompt all paint alike.

plainStyle = {"normal": "", "header": "", "fact": "", "rule": "", "var": "", "note": ""}

filledStyle = function(style)
	"A complete style map: the plain style, with the caller's own text for the roles it names."
	if style == null then return plainStyle + {}
	return plainStyle + style
end function

paint = function(style, role, text)
	"One piece in its role's color, or as it is when the style has nothing for that role."
	if style == null or style.hasIndex(role) == 0 then return text
	return style[role] + text + style.normal
end function

// A variable that came through standardizeApart carries a number in its name, so
// when two of them would read alike the rule's one is given a prime instead of a
// digit: ?p is the name that was asked about, ?p' is the same name inside a rule.

reportVarNames = function(options)
	"Every variable name the alternatives mention, once each, in the order it appears."
	names = []
	seen = {}
	for option in options
		for need in option.needs
			terms = need.triple.parts + varsIn(need.triple.at)
			for part in terms
				if part isa Var and seen.hasIndex(part.name) == 0 then
					seen[part.name] = 1
					names.push(part.name)
				end if
			end for
		end for
	end for
	return names
end function

isRuleName = function(name)
	"Says whether the name carries the suffix standardizeApart added, so it came from a rule."
	return plainName(name) != name
end function

reportLabels = function(options)
	"One label per variable name the report shows: its own name, or a primed one for a rule's that would read the same."
	names = reportVarNames(options)
	labels = {}
	// The goal's names are claimed first, so a rule's ?p can never take the name of
	// the variable the query actually asked about.
	for name in names
		if not isRuleName(name) then labels[name] = name
	end for
	for name in names
		if isRuleName(name) then labels[name] = freeLabel(labels, plainName(name))
	end for
	return labels
end function

freeLabel = function(labels, base)
	"The name itself when nothing else shows it, else primed once per variable that got there first."
	label = base
	while labels.indexOf(label) != null
		label = label + "'"
	end while
	return label
end function

primedVariable = function(labels)
	"Says whether the report shows a primed name, which its last line explains."
	for label in labels.values
		if label.indexOf("'") != null then return true
	end for
	return false
end function

reportLines = function(options, style=null)
	"The lines that describe these alternatives, painted with style; a body that needs nothing at all has no alternative to describe, so it has no report either."
	if options.len == 0 then return []
	style = filledStyle(style)
	labels = reportLabels(options)
	lines = [paint(style, "header", "  A solution would need one of these:")]
	seen = {}
	for option in options
		block = optionLines(option, labels, style)
		key = block.join("|")
		if seen.hasIndex(key) == 0 then
			seen[key] = 1
			lines = lines + block
		end if
	end for
	if primedVariable(labels) then
		lines.push(paint(style, "note",
			"    (a name ending in ' is the rule's own variable, not one you asked about)"))
	end if
	return lines
end function

neededFactLines = function(goal, facts, rules, depth, style=null)
	"The lines to print when goal has no answer: the facts that would allow one, painted with style."
	return reportLines(needsFor(goal, facts, rules, depth), style)
end function

optionLines = function(option, labels, style)
	"The lines for one alternative: a fact, or a rule and the facts its body would still need."
	if option.rule == null then
		if option.needs.len == 1 then
			return ["    a fact like " + neededFactText(option.needs[0], labels, style)]
		end if
		// A body asked as a one-off rule has no head one fact could answer, so every fact its
		// conditions would need is listed: they are needed together, not one of them.
		block = [paint(style, "note", "    facts like these:")]
		for needed in option.needs
			block.push("      " + neededFactText(needed, labels, style))
		end for
		return block
	end if
	block = [paint(style, "rule", "    through rule " + option.rule.text)]
	for needed in option.needs
		block.push("      " + neededFactText(needed, labels, style))
	end for
	return block
end function

neededFactText = function(need, labels, style)
	"One missing fact as it reads, tagged when a fact listed above it would settle the condition."
	triple = need.triple
	fact = paint(style, "fact", shownTerm(triple.predicate, labels, style) + "(" +
		shownTerm(triple.subject, labels, style) + ", " +
		shownTerm(triple.object, labels, style) + ")")
	if not need.settled then return fact
	return fact + paint(style, "note", "  (checked once the facts above exist)")
end function

shownTerm = function(term, labels, style)
	"One field of a needed fact: a value as it reads, a variable as the label the report gave it."
	if not (term isa Var) then return termText(term)
	plain = "?" + labels[term.name]
	shown = paint(style, "var", plain)
	// Dimming a variable ends the paint it sits in, so a painted fact reopens it.
	if shown == plain then return plain
	return shown + style.fact
end function

// ── What a value asked for means ────────────────────────────────────────────
// A question's box names the value by the label of its variable, and a label like ?p' says
// nothing on its own. The fact being filled says the rest: in is-parent-of(?p', ?p) the first
// field is the parent of the second, so a value there is "the parent of ?p". The word comes
// from the predicate's own name, which is a domain's own vocabulary for the field - nothing
// has to be declared twice - and a name of another shape falls back to the fact as a sentence,
// where the value's place in it is the explanation.

relationWord = function(name)
	"The word an is-...-of name gives its first field, as 'parent' from is-parent-of; null when the name says no such thing."
	if not (name isa string) then return null
	parts = name.split("-")
	if parts.len < 3 then return null
	if parts[0] != "is" then return null
	if parts[parts.len - 1] != "of" then return null
	// A name's sections are the sentence's words, so is-grand-parent-of gives "grand parent".
	middle = []
	for at in range(1, parts.len - 2)
		middle.push(parts[at])
	end for
	if middle.len == 0 then return null
	return middle.join(" ")
end function

valueMeaning = function(triple, variable)
	"What a value asked for stands for: 'the parent of ?p', 'the one ?p is the parent of', or the fact as a sentence when its name gives no such word."
	word = relationWord(triple.predicate)
	if word != null then
		if triple.subject isa Var and triple.subject.name == variable.name then
			return "the " + word + " of " + termText(triple.object)
		end if
		if triple.object isa Var and triple.object.name == variable.name then
			return "the one " + termText(triple.subject) + " is the " + word + " of"
		end if
	end if
	return speak(triple, 1)
end function

plainName = function(name)
	"The variable's name without the numeric suffix standardizeApart added, so ?x_3 reads ?x."
	pieces = name.split("_")
	if pieces.len < 2 then return name
	last = pieces[-1]
	if last == "" then return name
	for c in last
		if c.code < 48 or c.code > 57 then return name
	end for
	return pieces[:-1].join("_")
end function

// ── Parsing ───────────────────────────────────────────────────────────────────

parseLine = function(line)
	"Reads 'predicate(subject, object)' or 'subject | predicate | object', or an error."
	text = trimSpace(line)
	// An open quote is refused here rather than read as part of a value: it would
	// swallow everything after it and leave a misreading of the line.
	if not balancedQuotes(text) then return err(unclosedQuote(line))

	// Text wrapped in one pair of parentheses is a call, and a call that does not
	// fit fails loudly: falling back to the pipe form would put 'oav(bill' in the
	// subject and quietly invent a triple. A '(' inside a quoted value is not the
	// call's, so the opening one is looked for outside quotes.
	if indexOfOutside(text, "(", false) != null and text[-1] == ")" then
		called = parseCall(text)
		if called == null then return err(badLine(line))
		return called
	end if

	return parsePipe(text, line)
end function

parsePipe = function(text, line)
	"Reads 'subject | predicate | object' into [subject, predicate, object], else an error."
	fields = splitOutside(text, "|", false)
	if fields.len != 3 then return err(badLine(line))
	terms = mapWith(fields, @fieldTerm, line)
	for term in terms
		if term isa error then return term
	end for
	return terms
end function

fieldTerm = function(field, line)
	"One pipe-form field as a term: trimmed, non-empty, and a Var when it reads ?x."
	term = trimSpace(field)
	if term == "" then return err("malformed spo: empty field: " + line)
	return termOf(term)
end function

parseCall = function(text)
	"Reads 'predicate(subject, object)' into [subject, predicate, object], else null."
	text = trimSpace(text)
	openAt = indexOfOutside(text, "(", false)
	if openAt == null then return null
	if text[-1] != ")" then return null
	inner = text[openAt + 1:-1]
	args = splitOutside(inner, ",", true)
	if args.len != 2 then return null
	predicate = trimSpace(text[:openAt])
	if predicate == "" then return null
	return [termOf(trimSpace(args[0])), termOf(predicate), termOf(trimSpace(args[1]))]
end function

termOf = function(text)
	"Turns a field into a term: a quoted field is the text it holds, '?x' becomes a Var, a plain number a number, and any other field its text."
	if isQuoted(text) then return bareText(text)
	if text[:1] == "?" then return Var.make(text)
	if isNumber(text) then return val(text)
	// A call stands where a value stands, and only a call's own name is read that way: any
	// other parentheses in a field stay the text they were written as.
	for name in callNames.indexes
		if text[:name.len + 1] == name + "(" and text[-1:] == ")" then
			args = []
			for arg in splitOutside(text[name.len + 1:-1], ",", true)
				args.push(termOf(trimSpace(arg)))
			end for
			return Call.make(name, args)
		end if
	end for
	return text
end function

isNumber = function(text)
	"Says whether the text is a plain number, which val alone cannot tell: val of a name is 0."
	// A number is a mantissa and an exponent: '1e3' is a thousand, and val alone cannot
	// tell, because it stops reading at the 'e' and keeps the one before it.
	digits = 0          // digits in the mantissa
	dots = 0            // dots in the mantissa: one at most
	exponentAt = null   // where the 'e' sits, once the mantissa has ended
	exponentDigits = 0  // digits after the 'e', which are required and whole
	for at in range(0, text.len - 1)
		c = text[at]
		if exponentAt == null then
			if c == "e" or c == "E" then
				exponentAt = at
			else if c >= "0" and c <= "9" then
				digits = digits + 1
			else if c == "." then
				dots = dots + 1
				if dots > 1 then return false
			else if c != "-" or at != 0 then
				return false
			end if
		else if c >= "0" and c <= "9" then
			exponentDigits = exponentDigits + 1
		else if (c != "+" and c != "-") or at != exponentAt + 1 then
			// A sign may open the exponent, and nothing else may follow it.
			return false
		end if
	end for
	// '' and '-' have no digits at all, 'e3' has none before the 'e', and '1e' has none
	// after it: each stays text rather than becoming the number val would make of it.
	if digits == 0 then return false
	if exponentAt != null and exponentDigits == 0 then return false
	return true
end function

badLine = function(line)
	"One message for every malformed line."
	return "malformed spo: expected 'predicate(subject, object)' or 'subject | predicate | object': " + line
end function

unclosedQuote = function(line)
	"One message for a line whose quoted value has no closing quote."
	return "malformed spo: a quoted value has no closing quote: " + line
end function

// ── Rules as text ─────────────────────────────────────────────────────────────
// Rule.text prints a rule as 'head => condition, condition', and the functions here
// read that line back. They return the pieces Rule.make takes rather than a rule, so
// this module never has to hold the Rule class: a caller wraps them in whichever copy
// of it built the rest of its knowledge base.

parseRule = function(line)
	"Reads 'head => condition, condition' into {head, body}, or an error."
	// The arrow is looked for outside quotes, so a value holding one is not the rule's.
	arrowAt = indexOfOutside(line, "=>", false)
	if arrowAt == null then return err(badRule(line))
	// A head that does not parse keeps its own error: it names the piece that is wrong,
	// where the rule's one message would only repeat the line, and a predicate name it
	// refuses is the one message a typo can act on.
	head = SpoTriple.parseBare(line[:arrowAt])
	if head isa error then return head
	body = trimSpace(line[arrowAt + 2:])
	if body == "" then return err(badRule(line))
	conditions = []
	for text in splitConditions(body)
		more = parseBodyPart(text, line)
		// Likewise for a condition: a body is where most rule typos are, so the piece's own
		// message says more than the line's.
		if more isa error then return more
		conditions = conditions + more
	end for
	return {"head": head, "body": conditions}
end function

splitConditions = function(text)
	"Splits a rule body at the commas between conditions, not the ones inside a call or a quoted value."
	return splitOutside(text, ",", true)
end function

parseCondition = function(text, line, atAllowed=0)
	"Reads one condition of a rule body: a triple, or a constraint such as not-equal(?x, ?y), equal(?n, 18), years-since(2019-04-01, ?n) or less-than-or-equal(?n, 18)."
	text = trimSpace(text)
	if text == "" then return err(badRule(line))
	constraint = constraintOf(text)
	if constraint != null then return constraint
	// A rule's head and conditions are written bare, since the moment belongs to the fact it
	// matches. A question written as a body - and(...) typed at the prompt - is asking, so it
	// may name the moment; '~' and '#' stay a stored fact's own.
	if atAllowed then
		triple = SpoTriple.parse(text)
		if triple isa error then return triple
		if triple.confidence != 100 or triple.source != null then
			return err("a question takes only an '@': " + text)
		end if
		return triple
	end if
	return SpoTriple.parseBare(text)
end function

constraintOf = function(text)
	"Reads a constraint call into an Equal, a NotEqual or a Comparison: null for another predicate, an error when the call is wrong."
	openAt = indexOfOutside(text, "(", false)
	if openAt == null then return null
	name = trimSpace(text[:openAt])
	if not isConstraint(name) then return null
	expected = "expected '" + name + "(field, field)': " + text
	if not balancedQuotes(text) then return err(expected)
	inner = trimSpace(text[openAt + 1:])
	if inner.len == 0 then return err(expected)
	if inner[-1] != ")" then return err(expected)
	fields = splitOutside(inner[:-1], ",", true)
	if fields.len != 2 then return err(expected)
	left = trimSpace(fields[0])
	right = trimSpace(fields[1])
	if left == "" or right == "" then return err(expected)
	leftTerm = termOf(left)
	rightTerm = termOf(right)
	for term in [leftTerm, rightTerm]
		problem = callProblem(term)
		if problem != null then return err(problem + ": " + text)
	end for
	if name == equalName then return Equal.make(leftTerm, rightTerm)
	if name == notEqualName then return NotEqual.make(leftTerm, rightTerm)
	if name == sinceName then return YearsSince.make(leftTerm, rightTerm)
	return Comparison.make(comparisonNames[name], leftTerm, rightTerm)
end function

parseBodyPart = function(text, line, atAllowed=0)
	"Reads one piece of a rule body into the conditions it stands for: a fact, a constraint, and(...) flattened, or or(...) and not(...) as one condition."
	text = trimSpace(text)
	if text == "" then return err(badRule(line))
	called = groupingOf(text)
	if called == null then
		condition = parseCondition(text, line, atAllowed)
		if condition isa error then return condition
		return [condition]
	end if
	inner = trimSpace(called.inner)
	if inner == "" then return err(badRule(line))
	parts = splitConditions(inner)
	if called.name == "not" then
		if parts.len != 1 then return err(badRule(line))
		body = parseBodyPart(parts[0], line, atAllowed)
		if body isa error then return body
		return [Not.make(body)]
	end if
	if called.name == "and" then
		conditions = []
		for part in parts
			more = parseBodyPart(part, line, atAllowed)
			if more isa error then return more
			conditions = conditions + more
		end for
		return conditions
	end if
	alternatives = []
	for part in parts
		alternative = parseBodyPart(part, line, atAllowed)
		if alternative isa error then return alternative
		alternatives.push(alternative)
	end for
	return [Or.make(alternatives)]
end function

groupingOf = function(text)
	"The {name, inner} of an and(...), or(...) or not(...) standing alone, or null when the text is not one."
	openAt = indexOfOutside(text, "(", false)
	if openAt == null then return null
	name = trimSpace(text[:openAt])
	if ["and", "or", "not"].indexOf(name) == null then return null
	if trimSpace(text[-1:]) != ")" then return null
	return {"name": name, "inner": text[openAt + 1:-1]}
end function

badRule = function(line)
	"One message for every malformed rule line."
	return "malformed rule: expected 'head => condition, condition': " + line
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
