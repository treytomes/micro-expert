// client.ms — what the API programs share: one HTTP request path, one set of parameter checks,
// the classes their replies come back as, and the cli library's declarations.
//
//   1. Transport        query strings, curl, the HTTP status, JSON
//   2. Parameters       names, types, ranges, required fields, one validator
//   3. Replied objects  one object of a reply as the service sent it, and a place among them
//   4. Arguments        the cli library's declarations, and the split into options and words
//
// The two services live beside this file, one each: geocode.ms holds geocode.maps.co's three
// endpoints and openmeteo.ms holds Open-Meteo's twenty-three. Neither can import this file -
// this interpreter discards the imports of an imported module - so a program imports both and
// hands them this module's map, which they call through: api.validate, api.get. The endpoint
// tables are still the whole surface of each service; validate passes a name a table does not
// list through untouched, for the parts the services extend without notice.
//
// Both services answer with JSON by default, and every request returns the same map:
//
//   {"ok": 1, "status": 200, "body": "...", "json": {...}, "url": "...", "error": null}
//
// A refused request is ok: 0 with the HTTP status and, when the service sent one, its own
// "reason".


import "json"
import "stringUtil"


// ══ 1. Transport ════════════════════════════════════════════════════════════

defaultTimeout = 60
statusMarker = "__http_status__"
quoteMark = char(34)
newline = char(10)
quote = function(text)
	"Puts a pair of double quotes around text, so a shell reads it as one word."
	return quoteMark + text + quoteMark
end function


queryString = function(params)
	"Encodes an ordered parameter map as a query string. A list joins with commas."
	parts = []
	for kv in params
		value = kv.value
		if value == null then continue
		if value isa list then
			if value.len == 0 then continue
			value = value.join(",")
		end if
		value = str(value)
		if value == "" then continue
		parts.push kv.key.urlEncode + "=" + value.urlEncode
	end for
	return parts.join("&")
end function


urlFor = function(base, params)
	"base with the parameters appended, using whichever of ? or & it already needs."
	text = queryString(params)
	if text == "" then return base
	if base.indexOf("?") == null then return base + "?" + text
	return base + "&" + text
end function


redactUrl = function(url, names=[])
	"url with the values of the named parameters replaced, so a key can be shown."
	if names.len == 0 then return url
	cut = url.indexOf("?")
	if cut == null then return url
	pairs = url[cut + 1:].split("&")
	for i in pairs.indexes
		equals = pairs[i].indexOf("=")
		if equals == null then continue
		if names.indexOf(pairs[i][:equals]) != null then
			pairs[i] = pairs[i][:equals] + "=REDACTED"
		end if
	end for
	return url[:cut + 1] + pairs.join("&")
end function


get = function(url, timeout=null)
	"Runs one curl GET and answers ok, status, body, json, url and error."
	if timeout == null then timeout = defaultTimeout
	command = "curl -sS --max-time " + timeout
	// curl writes the status after the body, marked so a body full of newlines is safe.
	command = command + " -w " + quote(newline + statusMarker + "%{http_code}") + " " + quote(url)
	reply = exec(command, timeout + 10)

	result = {"ok": 0, "status": null, "body": "", "json": null, "url": url, "error": null}
	if reply isa error then
		result.error = "Could not run curl: " + reply.message
		return result
	end if
	if reply.status != 0 then
		message = reply.errors.trim
		if message == "" then message = "no message from curl"
		result.error = "The request failed (curl exit " + reply.status + "): " + message
		return result
	end if

	output = reply.output
	body = output
	if output.indexOf(statusMarker) != null then
		parts = output.split(statusMarker)
		body = parts[:parts.len - 1].join(statusMarker)
		result.status = val(parts[parts.len - 1].trim)
	end if
	if body.len > 0 then
		if body[-1] == newline then body = body[:body.len - 1]
	end if
	result.body = body

	parsed = json.parse(body)
	if not (parsed isa error) then result.json = parsed

	if result.status == null then
		result.error = "The reply did not include an HTTP status."
		return result
	end if
	if result.status < 200 or result.status >= 300 then
		// Both services send {"error": true, "reason": "..."} for a refused request; the
		// rest of the body is a fallback for anything that is not their JSON.
		detail = ""
		if parsed isa map then
			if parsed.hasIndex("reason") then
				if parsed.reason isa string then detail = parsed.reason
			end if
			if detail == "" then
				if parsed.hasIndex("error") then
					if parsed.error isa string then detail = parsed.error
				end if
			end if
		end if
		if detail == "" then
			text = body.replace(char(13), "").trim
			if text != "" then detail = text[:200]
		end if
		message = "HTTP " + result.status
		if detail != "" then message = message + ": " + detail
		result.error = message
		return result
	end if

	result.ok = 1
	return result
end function


keyIn = function(options)
	"The caller's key, whichever spelling it was given under; null when none was."
	for candidate in ["apiKey", "api_key", "apikey"]
		if options.hasIndex(candidate) then
			value = options[candidate]
			if value != null then return value
		end if
	end for
	return null
end function


failure = function(message)
	"The map a request answers with when it never went out: nothing but the message."
	return {"ok": 0, "status": null, "body": "", "json": null, "url": "", "error": message}
end function


// ══ 2. Parameters ═══════════════════════════════════════════════════════════
// An endpoint is a map with "params", a list of parameter specs. A spec is a map with
// "name" and "type", and optionally "min", "max", "values", "required", "default",
// "allowNan" and "doc". The types are:
//
//   text         any string
//   int          a whole number, within min and max when given
//   number       any number, within min and max when given
//   enum         one of values
//   bool         true/false, 1/0, yes/no, on/off
//   coordinates  a number or a comma-separated list of numbers, each within min and max
//   csv          a comma-separated list, given as a string or as a list
//   date         yyyy-mm-dd
//   datetime     yyyy-mm-ddThh:mm
//
// validate() turns a caller's options map into the parameters to send, in the order the
// caller gave them, and says what is wrong with the ones it cannot use. A name the table
// does not list is passed through untouched, because both services promise to add optional
// parameters and a layer that dropped one would quietly hide it.

// Options that belong to this layer or the programs, not to the remote API.
reservedKeys = ["apikey", "customer"]


normalKey = function(key)
	"Parameter names compare without dashes, underscores or case."
	return str(key).replace("_", "").replace("-", "").lower
end function


matchParam = function(spec, key)
	"The parameter spec a caller's name refers to, or null when the table has no such name."
	normal = normalKey(key)
	for paramSpec in spec.params
		if normalKey(paramSpec.name) == normal then return paramSpec
	end for
	return null
end function


rangeProblem = function(paramSpec, number)
	"null when the number is inside the spec's range, otherwise what is wrong."
	if paramSpec.hasIndex("min") then
		if number < paramSpec.min then return "must be at least " + paramSpec.min
	end if
	if paramSpec.hasIndex("max") then
		if number > paramSpec.max then return "must be at most " + paramSpec.max
	end if
	return null
end function


isDate = function(text)
	"True for yyyy-mm-dd."
	if text.len != 10 then return false
	if text[4] != "-" or text[7] != "-" then return false
	for i in [0, 1, 2, 3, 5, 6, 8, 9]
		if "0123456789".indexOf(text[i]) == null then return false
	end for
	return true
end function


isHour = function(text)
	"True for yyyy-mm-ddThh:mm."
	if text.len != 16 then return false
	if text[4] != "-" or text[7] != "-" then return false
	if text[10] != "T" and text[10] != " " then return false
	if text[13] != ":" then return false
	for i in [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15]
		if "0123456789".indexOf(text[i]) == null then return false
	end for
	return true
end function


coerce = function(paramSpec, value)
	"One value checked against one spec: {ok, value} or {ok: 0, problem}."
	kind = paramSpec.type

	if kind == "bool" then
		if value isa number then
			if value == 0 then return {"ok": 1, "value": "false"}
			return {"ok": 1, "value": "true"}
		end if
		text = str(value).lower
		if ["1", "true", "yes", "on"].indexOf(text) != null then return {"ok": 1, "value": "true"}
		if ["0", "false", "no", "off"].indexOf(text) != null then return {"ok": 1, "value": "false"}
		return {"ok": 0, "problem": "must be true or false"}
	end if

	if kind == "int" or kind == "number" then
		text = str(value).trim
		// A number the table lets nan stand in for, such as a panel tilt, keeps the word.
		if text.lower == "nan" and paramSpec.hasIndex("allowNan") then return {"ok": 1, "value": "nan"}
		if not text.isNumeric then
			if kind == "int" then return {"ok": 0, "problem": "must be a whole number"}
			return {"ok": 0, "problem": "must be a number"}
		end if
		number = val(text)
		if kind == "int" then
			if floor(number) != number then return {"ok": 0, "problem": "must be a whole number"}
		end if
		problem = rangeProblem(paramSpec, number)
		if problem != null then return {"ok": 0, "problem": problem}
		return {"ok": 1, "value": str(number)}
	end if

	if kind == "enum" then
		text = str(value)
		if paramSpec.values.indexOf(text) == null then
			return {"ok": 0, "problem": "must be one of " + paramSpec.values.join(", ")}
		end if
		return {"ok": 1, "value": text}
	end if

	if kind == "coordinates" or kind == "csv" then
		items = value
		if not (value isa list) then items = str(value).split(",")
		if items.len == 0 then return {"ok": 0, "problem": "must not be empty"}
		clean = []
		for item in items
			text = str(item).trim
			if kind == "csv" then
				if text == "" then return {"ok": 0, "problem": "must not contain an empty value"}
				clean.push text
			else
				// A list option gives one value per occurrence, and each may still be a
				// comma-separated run, so both spellings of several coordinates arrive here.
				for part in text.split(",")
					part = part.trim
					if part == "" then
						return {"ok": 0, "problem": "must not contain an empty value"}
					end if
					if part.lower == "nan" and paramSpec.hasIndex("allowNan") then
						clean.push "nan"
						continue
					end if
					if not part.isNumeric then
						return {"ok": 0, "problem": "must be a number or a comma-separated list of numbers"}
					end if
					number = val(part)
					problem = rangeProblem(paramSpec, number)
					if problem != null then return {"ok": 0, "problem": problem}
					clean.push str(number)
				end for
			end if
		end for
		return {"ok": 1, "value": clean.join(",")}
	end if

	if kind == "date" then
		text = str(value).trim
		if not isDate(text) then return {"ok": 0, "problem": "must be a date like 2026-11-21"}
		return {"ok": 1, "value": text}
	end if

	if kind == "datetime" then
		text = str(value).trim
		if not isHour(text) then return {"ok": 0, "problem": "must be a date and hour like 2026-11-21T12:00"}
		return {"ok": 1, "value": text}
	end if

	// text, and any type a table names that this file does not know: sent as it came.
	text = str(value)
	if text == "" then return {"ok": 0, "problem": "must not be empty"}
	return {"ok": 1, "value": text}
end function


validate = function(spec, options={})
	"{ok, params, problems}: options checked against the endpoint's parameter specs."
	sent = {}
	problems = []
	found = {}

	for kv in options
		normal = normalKey(kv.key)
		if reservedKeys.indexOf(normal) != null then continue
		paramSpec = matchParam(spec, kv.key)
		if paramSpec == null then
			if kv.value != null then sent[kv.key] = kv.value
			continue
		end if
		if kv.value == null then continue
		// Provided, even if it turns out to be wrong: one complaint is enough.
		found[paramSpec.name] = 1
		checked = coerce(paramSpec, kv.value)
		if not checked.ok then
			problems.push paramSpec.name + " " + checked.problem
			continue
		end if
		if sent.hasIndex(paramSpec.name) then
			// The same parameter twice is how several values are given on a command line.
			sent[paramSpec.name] = str(sent[paramSpec.name]) + "," + str(checked.value)
		else
			sent[paramSpec.name] = checked.value
		end if
	end for

	for paramSpec in spec.params
		if paramSpec.hasIndex("required") then
			if paramSpec.required then
				if not found.hasIndex(paramSpec.name) then
					problems.push paramSpec.name + " is required"
				end if
			end if
		end if
	end for

	return {"ok": problems.len == 0, "params": sent, "problems": problems}
end function


// ══ 3. Replied objects ══════════════════════════════════════════════════════════
// Every service answers with objects - a result, a place, a flag, a clock - and each of them
// is read the same way: a map exactly as the service sent it, with named fields asked of it.
// That is Fields, and Place is a Fields that knows what it is called and where it is. The one
// thing that differs between services is the field names, so building one takes them:
// geocode.maps.co names a result display_name, Open-Meteo names it name and puts country after
// it, ipwho.is has no name at all but a city, a region and a country.
//
// They live here, beside the transport, because one service module cannot import another: this
// interpreter resolves an import against the entry script's folder, and an imported module's
// `globals` is the entry's. A service is handed this map instead, and builds its results from
// the classes on it, so all three services' places are one class.

Fields = {}


Fields.build = function(raw)
	"One object of a reply, its fields kept exactly as the service sent them."
	instance = new self
	instance.raw = raw
	return instance
end function


Fields.value = function(field)
	"The field the reply carried, or null when it carried none."
	if self.raw == null then return null
	if not self.raw.hasIndex(field) then return null
	return self.raw[field]
end function


Fields.text = function(field)
	"The field when it is text with something in it, otherwise null."
	value = self.value(field)
	if not (value isa string) then return null
	if value == "" then return null
	return value
end function


Fields.number = function(field)
	"The field when it is a number, otherwise null."
	value = self.value(field)
	if not (value isa number) then return null
	return value
end function


Fields.names = function
	"Every field it carries, in the order the service wrote them."
	if self.raw == null then return []
	return self.raw.indexes
end function


Fields.describe = function
	"Every field it carries as one line each, a nested object's fields indented under it."
	lines = []
	for field in self.names
		value = self.raw[field]
		if value isa map then
			lines.push field + ":"
			for inner in value.indexes
				lines.push "  " + inner + ": " + str(value[inner])
			end for
		else if value isa list then
			lines.push field + ": " + value.join(", ")
		else
			lines.push field + ": " + str(value)
		end if
	end for
	return lines
end function


Place = new Fields


Place.build = function(raw, nameFields=["name"], alsoFields=[])
	"A result of a reply, with the field names this service calls it by."
	place = new Place
	place.raw = raw
	place.nameFields = nameFields
	place.alsoFields = alsoFields
	return place
end function


Place.label = function
	"What it is known by: the first of its name fields with text, then the fields around it."
	words = []
	for field in self.nameFields
		text = self.text(field)
		if text != null then
			words.push text
			break
		end if
	end for
	for field in self.alsoFields
		text = self.text(field)
		if text != null then words.push text
	end for
	return words.join(", ")
end function


// Three shapes say where an object is: lat and lon as the reply spelled them, latitude and
// longitude as numbers, or a GeoJSON point as [longitude, latitude], which a lookup result may
// carry instead of either.
Place.coordinates = function
	"Where it is, in whichever of those shapes the reply gave; empty when it gave none."
	lat = self.value("lat")
	lon = self.value("lon")
	if lat != null and lon != null then return str(lat) + ", " + str(lon)
	lat = self.number("latitude")
	lon = self.number("longitude")
	if lat != null and lon != null then return str(lat) + ", " + str(lon)
	// A lookup result may carry no coordinates of its own, and a point as [longitude, latitude].
	centroid = self.value("centroid")
	if centroid isa map then
		if centroid.hasIndex("coordinates") then
			if centroid.coordinates isa list then
				if centroid.coordinates.len >= 2 then
					return str(centroid.coordinates[1]) + ", " + str(centroid.coordinates[0])
				end if
			end if
		end if
	end if
	return ""
end function


Place.latitude = function
	"The latitude itself, to send as a parameter; null when the reply gave none."
	number = self.number("latitude")
	if number != null then return number
	return self.text("lat")
end function


Place.longitude = function
	"The longitude itself, to send as a parameter, as latitude reads its own."
	number = self.number("longitude")
	if number != null then return number
	return self.text("lon")
end function


// ══ 4. Arguments ════════════════════════════════════════════════════════════════
// The command lines are the cli library's: a program declares its own switches, the
// service's parameters are declared from its own table, and the library reads both,
// generates --help and --version, and names the mistake. What is left here is the seam -
// a table as cli declarations, and the split between the options the library parses and the
// bare words a program reads itself, such as the endpoint to ask or the place to look for.
//
// A parameter is declared as the cli type that reads it best: a number as number, a list of
// values as list so that a repeated --hourly collects them, and everything else - text,
// dates, enumerations, booleans - as string, because the service's table knows what each one
// takes and says so before the request is made. A boolean keeps its written forms: --name
// alone means true, --name false says so, and --no-name means false.
//
// A parameter the table does not declare is refused by name rather than sent, which is what
// a parser is for; one a service adds later becomes available by adding it to the table. Each
// service's fetch still passes an unknown name through untouched, for callers that do not go
// through a program's command line.


// ── A table as declarations ──────────────────────────────────────────────────

optionType = function(paramSpec)
	"The cli type that reads this parameter: number, list, or string."
	// nan is a value these take, and the number type would refuse it before the table does.
	if paramSpec.hasIndex("allowNan") then return "string"
	if paramSpec.type == "int" or paramSpec.type == "number" then return "number"
	if paramSpec.type == "csv" or paramSpec.type == "coordinates" then return "list"
	return "string"
end function


optionDescription = function(paramSpec, markRequired=1)
	"The help text for a parameter: what it takes, then what the API says it is for."
	note = ""
	if paramSpec.type == "bool" then
		note = "true or false"
	else if paramSpec.type == "enum" then
		note = paramSpec.values.join(", ")
	end if
	text = paramSpec.doc
	if note != "" then text = text + " (" + note + ")"
	if markRequired then
		if paramSpec.hasIndex("required") then
			if paramSpec.required then text = text + " Required."
		end if
	end if
	return text
end function


addParameter = function(cli, cmd, paramSpec, markRequired=1)
	"Declares one API parameter on a command the cli library made."
	return cli.add(cmd, {
		"name": paramSpec.name,
		"aliases": ["--" + paramSpec.name.replace("_", "-")],
		"type": optionType(paramSpec),
		"description": optionDescription(paramSpec, markRequired),
	})
end function


addParameters = function(cli, cmd, spec, markRequired=1)
	"Declares every parameter an endpoint's table names, in the table's order."
	for paramSpec in spec.params
		addParameter(cli, cmd, paramSpec, markRequired)
	end for
	return cmd
end function


unionSpec = function(specs)
	"One parameter list holding every name the given tables name, once, in order."
	merged = {"params": []}
	for spec in specs
		for paramSpec in spec.params
			if matchParam(merged, paramSpec.name) == null then merged.params.push paramSpec
		end for
	end for
	return merged
end function


// ── Options and words ──────────────────────────────────────────────────────
// The library reads options and refuses anything else, while these programs also take
// words: the endpoint to ask, the place to search for. The split happens before the library
// sees the arguments, so only the sorting is here; the library still rejoins the arguments
// the shell splits at a quote (normalizeArgs), answers which spelling means which option
// (aliasTable), and is told apart from a word by the one test below.

startsOption = function(token)
	"True for a token that can only be an option here, so a value is never swallowed."
	// A negative number such as reverse's -33.9 stays a word; the library would call it an
	// unknown option, and it is not this split's place to complain.
	if token[:2] == "--" then return true
	return token == "-h" or token == "-v"
end function


canonicalOption = function(token)
	"An option with its underscores spelled as dashes; a value after = is left alone."
	equals = token.indexOf("=")
	if equals == null then return token.replace("_", "-")
	return token[:equals].replace("_", "-") + token[equals:]
end function


booleanNames = function(spec)
	"The parameter names whose table entry takes true or false."
	names = []
	if spec == null then return names
	for paramSpec in spec.params
		if paramSpec.type == "bool" then names.push normalKey(paramSpec.name)
	end for
	return names
end function


splitArguments = function(cli, shellArgs, cmd, spec=null)
	"Options for cli.parse, and the bare words a program reads itself."
	tokens = cli.normalizeArgs(shellArgs)
	byAlias = cli.aliasTable(cmd)
	booleans = booleanNames(spec)
	options = []
	words = []
	index = 0
	while index < tokens.len
		index = takeArgument(tokens, index, byAlias, booleans, options, words)
	end while
	return {"options": options, "words": words}
end function


takeArgument = function(tokens, index, byAlias, booleans, options, words)
	"Sorts one argument, with the value it needs, into options or words: the next index."
	token = tokens[index]
	if not startsOption(token) then
		words.push token
		return index + 1
	end if
	// --no-name is how a false boolean is spelled; the library only knows --name.
	if token[:5] == "--no-" then
		name = canonicalOption("--" + token[5:])
		if booleans.indexOf(normalKey(name)) != null then
			options.push name
			options.push "false"
			return index + 1
		end if
	end if
	name = canonicalOption(token)
	options.push name
	if token.indexOf("=") != null then return index + 1
	if not byAlias.hasIndex(name) then return index + 1
	if byAlias[name].type == "flag" then return index + 1
	if index + 1 < tokens.len then
		if not startsOption(tokens[index + 1]) then
			options.push tokens[index + 1]
			return index + 2
		end if
	end if
	// A boolean with nothing after it means true; anything else is the library's to refuse.
	if booleans.indexOf(normalKey(name)) != null then options.push "true"
	return index + 1
end function


apiOptions = function(values, switches=[])
	"Only the values that were given: the library fills in a default for every option."
	options = {}
	for kv in values
		if switches.indexOf(kv.key) != null then continue
		if kv.value == null then continue
		if kv.value isa list then
			if kv.value.len == 0 then continue
		end if
		options[kv.key] = kv.value
	end for
	return options
end function
