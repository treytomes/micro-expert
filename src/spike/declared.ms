// declared.ms — one writer for every service that can be said as a map.
//
// A service is data: its base, its endpoints, the parameters each takes, and what each reply
// becomes. This module is the reading, and it knows no service by name.
//
//   import "spike/declared"
//   declared = globals["spike/declared"]
//
//   decl    = {"service": "ipwho.is", "base": "https://ipwho.is", "endpoints": {...}}
//   result  = declared.fetch(api, decl, "lookup", {"fields": "city"}, 10)
//   reading = declared.read(triples, uid, decl, "lookup", result.json)
//
// The reply half of an endpoint says these things, and they run in this order:
//
//   "each"        the list to read: "$" or a path for a list of objects, or
//                 {"path": ..., "as": ...} for a series whose variables are parallel lists
//   "refuse"      when one field says the service said no, and which field carries why
//   "require"     the fields without which there is no subject to hang facts on
//   "subject"     the kind and fields that identify it, or the parts to join
//   "request"     the request's own fields, bound for a fact that records what was asked
//   "facts"       [predicate, subject, object, annotations] per line
//
// Each side of a fact is one of
//
//   ?name              a name the reading bound: the subject, or a field of the request
//   $.a.b[0]           a path into the reply, an index allowed at any step
//   $.a.b[i]           the same, indexed by the reading's own position in a series
//   $.a.b[i+1]         the same, one step on; [i-1] one step back
//   $.a as number      the field read as that type, for a service that spells a number as text
//   $.a as moment      the field as the fact grammar spells a datetime: '2026-11-22 00:00'
//   anything           a literal term
//
// A fact may carry the two annotations a stored fact does: '@' says when it holds, '~' how
// confident it is. The fourth element says where they come from, and either may be left out:
//
//   {"at": "?time"}                                        a moment
//   {"at": {"span": ["?time", "$.a[i+1]"], "or": "?time"}}  a range, or a moment with no end
//   {"confidence": "$.a[i]"}                               a percentage, 0 to 100
//
// A confidence the reply does not carry leaves the fact fully confident, the way a fact that
// says nothing about its confidence does; one that is not a number from 0 to 100 leaves the
// fact out and names it in "skipped".
//
// Absent, null and blank text all write nothing, the way src/location.ms reads a field, and
// every fact left out is named in the reading's "skipped" list rather than disappearing
// quietly.
//
// The request half takes two per-service clauses as well: "key" names the parameter a key
// travels as, and "redact" the parameters whose values are hidden in the url a result carries;
// "boolAs" rewrites true and false the way a service spells them.


endpointOf = function(decl, name)
	"The endpoint the map names, or null when it names none."
	if not decl.endpoints.hasIndex(name) then return null
	return decl.endpoints[name]
end function


at = function(raw, path, bindings=null)
	"One value from the reply by a dotted path, an index such as [0] or [i] at any step; null when it runs out."
	if not (raw isa map or raw isa list) then return null
	value = raw
	for step in str(path).split(".")
		index = null
		open = step.indexOf("[")
		if open != null then
			text = step[open + 1:-1]
			if numberText(text) then
				index = val(text)
			else if bindings != null then
				index = boundIndex(text, bindings)
			end if
			if index == null then return null
			step = step[:open]
		end if
		if step != "" then
			if not (value isa map) then return null
			if not value.hasIndex(step) then return null
			value = value[step]
		end if
		if index != null then
			if not (value isa list) then return null
			if index < 0 or index >= value.len then return null
			value = value[index]
		end if
	end for
	return value
end function


present = function(value)
	"One value as a fact can hold it: absent, null and blank text all read the same."
	if value == null then return null
	if value isa string then
		if value.replace(" ", "") == "" then return null
	end if
	return value
end function


boundIndex = function(text, bindings)
	"An index a reading bound, or one and a step from it: 'i', 'i+1', 'i-1'."
	if bindings.hasIndex(text) then return bindings[text]
	for sign in ["+", "-"]
		cut = text.indexOf(sign)
		if cut != null and cut > 0 then
			name = text[:cut]
			step = text[cut + 1:]
			if bindings.hasIndex(name) and numberText(step) then
				if sign == "+" then return bindings[name] + val(step)
				return bindings[name] - val(step)
			end if
		end if
	end for
	return null
end function


fieldOf = function(raw, path, bindings=null)
	"The field the reply carried, or null when it carried none."
	return present(at(raw, path, bindings))
end function


numberText = function(text)
	"Says whether text spells a number in the plain shape a coordinate takes, so val() is only called on one."
	if text.len == 0 then return false
	start = 0
	if text[:1] == "-" then start = 1
	if text.len <= start then return false
	digits = 0
	dots = 0
	for i in range(start, text.len - 1)
		c = text[i]
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


termValue = function(raw, term, bindings)
	"One side of a declared fact: a bound name, a path into the reply, or a literal."
	if not (term isa string) then return term
	if term[:1] == "?" then
		name = term[1:]
		if bindings.hasIndex(name) then return bindings[name]
		return null
	end if
	if term[:2] == "$." then
		// 'as number' and 'as text' say what the field has to read as.
		path = term
		kind = null
		cut = term.indexOf(" as ")
		if cut != null then
			path = term[:cut]
			kind = term[cut + 4:]
		end if
		value = fieldOf(raw, path[2:], bindings)
		if value == null then return null
		if kind == "number" then
			text = str(value).trim
			if not numberText(text) then return null
			return val(text)
		end if
		if kind == "text" then return str(value)
		if kind == "moment" then
			// A service writes an instant its own way - ISO 8601's 'T' is not the grammar's
			// datetime, which is a date and a time with a space between them.
			return str(value).trim.replace("T", " ")
		end if
		return value
	end if
	return term
end function


momentOf = function(scope, spec, bindings)
	"One fact's '@': a moment term, or a range of two terms with the moment to fall back to."
	if not (spec isa map) then return termValue(scope, spec, bindings)
	start = termValue(scope, spec.span[0], bindings)
	finish = termValue(scope, spec.span[1], bindings)
	if start != null and finish != null then return "[" + start + ", " + finish + "]"
	if spec.hasIndex("or") then return termValue(scope, spec["or"], bindings)
	return null
end function


subjectPart = function(scope, term, bindings)
	"One part of a subject: a field of the reply, or a term the reading bound."
	if term isa string then
		if term[:2] == "$." or term[:1] == "?" then return termValue(scope, term, bindings)
	end if
	return fieldOf(scope, term, bindings)
end function


joined = function(parts, separator)
	"Parts as one term, the empty ones dropped; empty when no part says anything."
	words = []
	for part in parts
		if part == null then continue
		text = str(part).trim
		if text != "" then words.push text
	end for
	return words.join(separator)
end function


readOne = function(triples, uid, reply, scope, asked, extra, facts, skipped, strict)
	"One object, or one index of a series, as its facts: ok 0 only when strict and it has no subject."
	bindings = extra + {}
	if reply.hasIndex("request") then
		for name in reply.request
			if asked.hasIndex(name) then bindings[name] = asked[name]
		end for
	end if

	for term in reply.require
		if subjectPart(scope, term, bindings) == null then
			// A request field is missing for the whole reply, not for one reading of a series.
			if term[:1] == "?" then
				return {"ok": 0, "error": "the request named no " + term[1:], "subject": ""}
			end if
			why = "the reply named no " + term
			if strict then return {"ok": 0, "error": why, "subject": ""}
			skipped.push why
			return {"ok": 1, "subject": ""}
		end if
	end for

	parts = []
	for term in reply.subject.from
		parts.push subjectPart(scope, term, bindings)
	end for
	subject = ""
	if reply.subject.hasIndex("kind") then
		// A generated term: the same three fields make the same one on the next run.
		subject = uid.of(reply.subject.kind, parts)
	else
		// A joined term: the service's own identity, as way/5013364.
		separator = "/"
		if reply.subject.hasIndex("join") then separator = reply.subject.join
		subject = joined(parts, separator)
	end if
	if subject == "" then
		if strict then
			return {"ok": 0, "error": "the reply named nothing to identify it by", "subject": ""}
		end if
		skipped.push "an entry with nothing to identify it by"
		return {"ok": 1, "subject": ""}
	end if

	bindings[reply.subject.name] = subject

	for spec in reply.facts
		predicate = spec[0]
		subjectTerm = termValue(scope, spec[1], bindings)
		objectTerm = termValue(scope, spec[2], bindings)
		if subjectTerm == null then
			skipped.push predicate + ": " + spec[1] + " was absent or did not fit"
			continue
		end if
		if objectTerm == null then
			skipped.push predicate + ": " + spec[2] + " was absent or did not fit"
			continue
		end if
		at = null
		confidence = 100
		if spec.len > 3 then
			annotations = spec[3]
			if annotations.hasIndex("at") then at = momentOf(scope, annotations.at, bindings)
			if annotations.hasIndex("confidence") then
				value = termValue(scope, annotations.confidence, bindings)
				if value != null then
					if not (value isa number) or value < 0 or value > 100 then
						skipped.push predicate + ": " + str(value) + " is not a confidence from 0 to 100"
						continue
					end if
					confidence = value
				end if
			end if
		end if
		facts.push triples.SpoTriple.make(subjectTerm, predicate, objectTerm, at, confidence)
	end for
	return {"ok": 1, "subject": subject}
end function


read = function(triples, uid, decl, endpointName, json, asked={})
	"Every object the reply carries, as the facts its endpoint maps; ok 0 only when a single object has no subject."
	endpoint = endpointOf(decl, endpointName)
	if endpoint == null then
		return {"ok": 0, "error": "unknown endpoint " + endpointName, "subject": "",
			"subjects": [], "facts": [], "skipped": []}
	end if
	reply = endpoint.reply

	// A refusal is read before a fact is, because a service may refuse with a 200.
	if reply.hasIndex("refuse") and json isa map then
		refusal = reply.refuse
		saysNo = false
		if refusal.hasIndex("when") then
			if at(json, refusal.when) == refusal.is then saysNo = true
		else if refusal.hasIndex("present") then
			if at(json, refusal.present) != null then saysNo = true
		end if
		if saysNo then
			why = null
			if refusal.hasIndex("message") then why = at(json, refusal.message)
			if why == null and refusal.hasIndex("present") then why = at(json, refusal.present)
			if not (why isa string) then why = "no message given."
			return {"ok": 0, "error": "the service refused the request: " + why,
				"subject": "", "subjects": [], "facts": [], "skipped": []}
		end if
	end if

	each = reply.hasIndex("each")
	if not each and not (json isa map) then
		return {"ok": 0, "error": "the service did not answer with an object", "subject": "",
			"subjects": [], "facts": [], "skipped": []}
	end if

	// A reply is one object, a list of objects, or a series: parallel lists where one index is
	// one reading, and the paths into it are the root's.
	mode = "object"
	asName = null
	items = [json]
	if each then
		path = reply.each
		mode = "objects"
		if reply.each isa map then
			path = reply.each.path
			// A series may name no variable: its index is what the facts are read by.
			if reply.each.hasIndex("as") then asName = reply.each.as
			mode = "array"
		end if
		items = json
		if path != "$" then
			if path[:2] == "$." then path = path[2:]
			items = at(json, path)
		end if
		if not (items isa list) then
			return {"ok": 0, "error": "the service did not answer with a list", "subject": "",
				"subjects": [], "facts": [], "skipped": []}
		end if
	end if

	facts = []
	skipped = []
	subjects = []
	for i in items.indexes
		element = items[i]
		scope = element
		extra = {}
		if mode == "array" then
			scope = json
			extra["i"] = i
			if asName != null then extra[asName] = element
		else
			if not (element isa map) then
				skipped.push "an entry that is not an object"
				continue
			end if
		end if
		one = readOne(triples, uid, reply, scope, asked, extra, facts, skipped, not each)
		if not one.ok then
			return {"ok": 0, "error": one.error, "subject": "", "subjects": subjects,
				"facts": facts, "skipped": skipped}
		end if
		if one.subject != "" then subjects.push one.subject
	end for

	subject = ""
	if subjects.len > 0 then subject = subjects[0]
	return {"ok": 1, "error": null, "subject": subject, "subjects": subjects,
		"facts": facts, "skipped": skipped}
end function


fetch = function(api, decl, endpointName, options={}, timeout=null)
	"One request to the endpoint the map names, checked and spelled as its params say."
	endpoint = endpointOf(decl, endpointName)
	if endpoint == null then
		return api.failure("Unknown endpoint " + api.quote(endpointName) + ".")
	end if
	checked = api.validate(endpoint, options)
	if not checked.ok then
		return api.failure("Invalid " + endpointName + " request: " + checked.problems.join("; "))
	end if

	params = checked.params
	// A service that spells a boolean 1 or 0, and ignores the word false.
	if endpoint.hasIndex("boolAs") then
		for paramSpec in endpoint.params
			if paramSpec.type != "bool" then continue
			if not params.hasIndex(paramSpec.name) then continue
			value = str(params[paramSpec.name]).lower
			if value == "true" then params[paramSpec.name] = 1
			if value == "false" then params[paramSpec.name] = 0
		end for
	end if
	// A key travels as its own parameter rather than in the table the checks read.
	if endpoint.hasIndex("key") then
		key = api.keyIn(options)
		if key != null then params[endpoint.key] = key
	end if

	url = api.urlFor(decl.base + endpoint.path, params)
	result = api.get(url, timeout)
	if endpoint.hasIndex("redact") then result.url = api.redactUrl(url, endpoint.redact)
	return result
end function


label = function(decl, endpointName, json)
	"What the reply is known by: the first of its name fields with text, then the fields around it."
	endpoint = endpointOf(decl, endpointName)
	if endpoint == null then return ""
	spec = endpoint.reply.label
	words = []
	for name in spec.name
		text = fieldOf(json, name)
		if text != null then
			words.push str(text)
			break
		end if
	end for
	for name in spec.also
		text = fieldOf(json, name)
		if text != null then words.push str(text)
	end for
	return words.join(", ")
end function


coordinates = function(decl, endpointName, json)
	"The coordinates as one line, or empty when the reply carried none of them."
	endpoint = endpointOf(decl, endpointName)
	if endpoint == null then return ""
	parts = []
	for name in endpoint.reply.coordinates
		value = fieldOf(json, name)
		if value == null then return ""
		parts.push str(value)
	end for
	return parts.join(", ")
end function