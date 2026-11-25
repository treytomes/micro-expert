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
// The request half takes three per-service clauses as well: "key" names the parameter a key
// travels as, "keyEnv" the environment variable the key is read from, and "redact" the
// parameters whose values are hidden in the url a result carries; "boolAs" rewrites true and
// false the way a service spells them.
//
// A key is the caller's to pass - api.keyIn reads it from the options - and a map that names
// "keyEnv" is otherwise read from the environment, which is where src/dotenv.ms puts the .env
// beside the run. A declaration that names a variable and finds it empty refuses the request
// and says which variable to set, rather than sending a call the service answers 401 to. A
// map that names no variable has an optional key - Open-Meteo's apikey - and goes out without
// one.


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
	"One side of a declared fact: a bound name, a path into the reply, a list of paths to try in turn, or a literal."
	// A list is a fallback: the first alternative the reply carries a value for, so a service
	// that spells one field two ways needs no second fact line.
	if term isa list then
		for alternative in term
			value = termValue(raw, alternative, bindings)
			if value != null then return value
		end for
		return null
	end if
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
			text = trimText(value)
			if not numberText(text) then return null
			return val(text)
		end if
		if kind == "text" then return str(value)
		if kind == "moment" then
			// A service writes an instant its own way - ISO 8601's 'T' is not the grammar's
			// datetime, which is a date and a time with a space between them.
			return trimText(value).replace("T", " ")
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
		text = trimText(part)
		if text != "" then words.push text
	end for
	return words.join(separator)
end function


readOne = function(triples, uid, reply, scope, asked, extra, facts, skipped, strict, factsSpec=null)
	"One object, or one index of a series, as its facts: ok 0 only when strict and it has no subject."
	if factsSpec == null then factsSpec = reply.facts
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

	for spec in factsSpec
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


// ── Several series in one reply ─────────────────────────────────────────────
// A weather reply holds one table per period - hourly, daily, current, minutely_15, weekly,
// monthly - and each table is a list of instants beside one list per variable. A series spec
// names the table and the shape of its instants; the variables come from the table itself, or
// from the spec's own list when it has one, which is how a reply that left a documented
// variable out can still name it.

trimText = function(value)
	"The value as text without the space around it; the interpreter's strings carry no trim."
	text = str(value)
	while text.len > 0 and (text[0] == " " or text[0] == char(9) or text[0] == char(10) or text[0] == char(13))
		text = text[1:]
	end while
	while text.len > 0
		last = text[text.len - 1]
		if last != " " and last != char(9) and last != char(10) and last != char(13) then break
		text = text[:text.len - 1]
	end while
	return text
end function


momentText = function(value)
	"An instant as the fact grammar spells it: a date and a time with a space between them."
	return trimText(value).replace("T", " ")
end function


seriesMoment = function(times, index, kind)
	"The '@' of one row: the hour or quarter it covers, the date of a day, or the instant itself."
	if kind == "hour" or kind == "minutely" then
		if times isa list and index < times.len then
			start = momentText(times[index])
			if index + 1 < times.len then return "[" + start + ", " + momentText(times[index + 1]) + "]"
			return start
		end if
		return null
	end if
	if kind == "day" or kind == "week" or kind == "month" then
		if times isa list and index < times.len then return momentText(times[index])
		return null
	end if
	// A current reading carries its one instant as a field rather than a list.
	if times isa string then return momentText(times)
	return null
end function


probabilityOf = function(series, index)
	"The service's chance of precipitation at one row, as a confidence, or 100 when it sent none."
	if not series.hasIndex("precipitation_probability") then return 100
	values = series.precipitation_probability
	if not (values isa list) then return 100
	if index >= values.len then return 100
	value = present(values[index])
	if not (value isa number) then return 100
	if value < 0 or value > 100 then return 100
	return value
end function


appendSeries = function(triples, scope, spec, subject, facts, skipped, wanted={})
	"One table's facts, row by row: each row's variables in order, annotated by the row."
	series = at(scope, spec.path[2:])
	// A table the reply did not carry is simply no facts: a request that did not ask for it is
	// not a gap to report.
	if not (series isa map) then return null
	times = null
	if series.hasIndex("time") then times = series.time
	kind = "instant"
	if spec.hasIndex("kind") then kind = spec.kind
	// A table of rows without its instants cannot be read as rows; a current reading keeps its
	// one instant as a field and has no list to check.
	if kind != "instant" and not (times isa list) then return "the service did not answer with a list"
	names = []
	// What the caller asked this table for comes first: a request for two variables should not
	// be told about the three it did not ask for. Without that list, the documented ones name
	// what a reply left out.
	key = spec.path[2:]
	if wanted.hasIndex(key) then
		names = wanted[key]
	else if spec.hasIndex("variables") then
		names = spec.variables
	else
		for field in series.indexes
			if field == "time" or field == "interval" then continue
			if field == "precipitation_probability" then continue
			if series[field] isa map then continue
			names.push field
		end for
	end if
	// A current reading has no row list: its variables hold one value each.
	rows = [0]
	if times isa list then rows = times.indexes
	for i in rows
		for field in names
			values = null
			if series.hasIndex(field) then values = series[field]
			value = null
			if values isa list then
				if i < values.len then value = present(values[i])
			else
				value = present(values)
			end if
			if value == null then
				// A field the table never carried, or a null where a value belongs, is named once
				// per row: the reading says which of the variables it asked for it did not get.
				skipped.push "has-" + field.replace("_", "-") + ": " + spec.path + "." +
					field + " was absent"
				continue
			end if
			confidence = 100
			if field == "precipitation" then confidence = probabilityOf(series, i)
			facts.push triples.SpoTriple.make(subject, "has-" + field.replace("_", "-"), value,
				seriesMoment(times, i, kind), confidence)
		end for
	end for
	return null
end function


readSeries = function(triples, uid, reply, json, asked)
	"A reply of several tables, or of several places each holding them, as its facts."
	facts = []
	skipped = []
	subjects = []
	wanted = {}
	if asked.hasIndex("variables") then wanted = asked.variables
	items = [json]
	if reply.hasIndex("each") then
		if not (json isa list) then
			return {"ok": 0, "error": "the service did not answer with a list", "subject": "",
				"subjects": [], "facts": [], "skipped": []}
		end if
		items = json
	end if
	for item in items
		if not (item isa map) then
			skipped.push "an entry that is not an object"
			continue
		end if
		// The subject is the reply's, read once; the tables hang their facts off it.
		one = readOne(triples, uid, reply, item, asked, {}, facts, skipped,
			not reply.hasIndex("each"), [])
		if not one.ok then
			return {"ok": 0, "error": one.error, "subject": "", "subjects": subjects,
				"facts": facts, "skipped": skipped}
		end if
		if one.subject == "" then continue
		subjects.push one.subject
		for spec in reply.series
			problem = appendSeries(triples, item, spec, one.subject, facts, skipped, wanted)
			if problem != null then
				return {"ok": 0, "error": problem, "subject": "", "subjects": subjects,
					"facts": facts, "skipped": skipped}
			end if
		end for
	end for
	subject = ""
	if subjects.len > 0 then subject = subjects[0]
	return {"ok": 1, "error": null, "subject": subject, "subjects": subjects,
		"facts": facts, "skipped": skipped}
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

	// A reply of several tables is read a table at a time; a reply of one list of objects or one
	// object is read as before.
	if reply.hasIndex("series") then return readSeries(triples, uid, reply, json, asked)

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
	// An endpoint may say that its list is of values rather than of objects, as the elevation
	// reply's heights are.
	if reply.hasIndex("eachMode") then mode = reply.eachMode

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


keyVariable = function(decl, endpoint)
	"The environment variable a declaration says its key lives in: the endpoint's own, or the service's - null when it names none, which is how a service with an optional key says so."
	if endpoint.hasIndex("keyEnv") then return endpoint.keyEnv
	if decl.hasIndex("keyEnv") then return decl.keyEnv
	return null
end function


keyFromEnvironment = function(decl, endpoint)
	"The key the declaration's variable holds, or null when it names none or holds nothing: a blank setting is absent, the way dotenv reads one."
	name = keyVariable(decl, endpoint)
	if name == null then return null
	if not env.hasIndex(name) then return null
	value = env[name]
	if value == null then return null
	value = trimText(value)
	if value == "" then return null
	return value
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
	// A key travels as its own parameter rather than in the table the checks read. The caller
	// may hand one in; a declaration that names the variable its key lives in otherwise reads it
	// from the environment, and a key neither supplies is a refusal rather than a request the
	// service answers 401 to.
	if endpoint.hasIndex("key") then
		key = api.keyIn(options)
		if key == null then key = keyFromEnvironment(decl, endpoint)
		if key == null and keyVariable(decl, endpoint) != null then
			return api.failure(decl.service + " needs a key: set " + keyVariable(decl, endpoint) +
				" in the environment or in the .env beside the run")
		end if
		if key != null then params[endpoint.key] = key
	end if

	// A service can answer on more than one host, so an endpoint may name its own base.
	base = decl.base
	if endpoint.hasIndex("base") then base = endpoint.base
	url = api.urlFor(base + endpoint.path, params)
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