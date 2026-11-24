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
//   "each"        the path to the list of objects, when a reply carries several
//   "refuse"      when one field says the service said no, and which field carries why
//   "require"     the fields without which there is no subject to hang facts on
//   "subject"     the kind and fields that identify it, or the parts to join
//   "request"     the request's own fields, bound for a fact that records what was asked
//   "facts"       [predicate, subject, object] per line
//
// Each side of a fact is one of
//
//   ?name              a name the reading bound: the subject, or a field of the request
//   $.a.b[0]           a path into the reply, an index allowed at any step
//   $.a as number      the field read as that type, for a service that spells a number as text
//   anything           a literal term
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


at = function(raw, path)
	"One value from the reply by a dotted path, an index such as [0] at any step; null when it runs out."
	if not (raw isa map or raw isa list) then return null
	value = raw
	for step in str(path).split(".")
		index = null
		open = step.indexOf("[")
		if open != null then
			index = val(step[open + 1:-1])
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


fieldOf = function(raw, path)
	"The field the reply carried, or null when it carried none."
	return present(at(raw, path))
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
		value = fieldOf(raw, path[2:])
		if value == null then return null
		if kind == "number" then
			text = str(value).trim
			if not numberText(text) then return null
			return val(text)
		end if
		if kind == "text" then return str(value)
		return value
	end if
	return term
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


readOne = function(triples, uid, reply, item, asked, facts, skipped, strict)
	"One object as its facts: ok 0 only when strict and it has no subject."
	for name in reply.require
		if fieldOf(item, name) == null then
			if strict then
				return {"ok": 0, "error": "the reply named no " + name, "subject": ""}
			end if
			skipped.push "an entry with no " + name
			return {"ok": 1, "subject": ""}
		end if
	end for

	parts = []
	for name in reply.subject.from
		parts.push fieldOf(item, name)
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

	bindings = {}
	bindings[reply.subject.name] = subject
	if reply.hasIndex("request") then
		for name in reply.request
			if asked.hasIndex(name) then bindings[name] = asked[name]
		end for
	end if

	for spec in reply.facts
		predicate = spec[0]
		subjectTerm = termValue(item, spec[1], bindings)
		objectTerm = termValue(item, spec[2], bindings)
		if subjectTerm == null then
			skipped.push predicate + ": " + spec[1] + " was absent or did not fit"
			continue
		end if
		if objectTerm == null then
			skipped.push predicate + ": " + spec[2] + " was absent or did not fit"
			continue
		end if
		facts.push triples.SpoTriple.make(subjectTerm, predicate, objectTerm)
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

	items = [json]
	if each then
		items = json
		if reply.each != "$" then items = at(json, reply.each)
		if not (items isa list) then
			return {"ok": 0, "error": "the service did not answer with a list", "subject": "",
				"subjects": [], "facts": [], "skipped": []}
		end if
	end if

	facts = []
	skipped = []
	subjects = []
	for item in items
		if not (item isa map) then
			skipped.push "an entry that is not an object"
			continue
		end if
		one = readOne(triples, uid, reply, item, asked, facts, skipped, not each)
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