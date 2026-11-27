// document.ms — a provider declaration as a file: GRFON text in, the map declared.ms reads out.
//
// A declaration is data, and src/services/declared.ms is what it means. This module is only how
// that data gets to and from a file, with the four things a document adds over a plain map:
//
//   groups: {name: {params|facts|once|series|provides|reply|endpoint|takes}}  a fragment, named
//   @name                    wherever a fragment belongs                     used as it is
//   {use: @name; ...}        in a reply or an endpoint                       used with changes
//   takes: {a; b}            with @name(x, y) at the reference               a group with arguments
//
// and the one thing a document has that a map does not: GRFON cannot say that a lone value is a
// list of one. `lists` below is the whole answer to that, and the only place the program keeps it.
//
//   import "services/document"
//   document = globals["services/document"]
//
//   decl  = document.resolve(document.read(file.loadRaw("geocode.grfon")))
//   again = document.resolve(document.read(document.text(decl)))
//
// read gives the document's data, resolve the declaration or the reason it is not one, and text
// the document again with every value escaped so that it reads back as itself: a colon stays a
// colon, a term that starts with @ stays a term, and a semicolon stays inside its value.

import "grfon"

backslash = char(92)
newline = char(10)

// ── The schema: what a document may hold, and which parts are lists ─────────

// The parts that are lists, by the thing holding them. A part that arrives as a lone value is
// wrapped, so `{city}` and `{city;}` resolve to the same list - and `{city;}` is how a document
// says a list of one on purpose. Nothing else in the program names these keys. A group's `takes`
// and a capability's `fact` are lists too; each is read only where it is read, and wrapped there.
lists = {
	"endpoint": ["params", "provides", "redact"],
	"reply": ["require", "coordinates", "request", "facts", "once", "series"],
	"subject": ["from"],
	"label": ["name", "also"],
}

// What each level may hold. A key outside its level is a typo, and refusing it here is what keeps
// a misspelt clause from becoming a field nobody reads.
keys = {
	"declaration": ["service", "base", "keyEnv", "groups", "endpoints"],
	"group": ["params", "facts", "once", "series", "provides", "reply", "endpoint", "takes"],
	"endpoint": ["method", "base", "path", "key", "redact", "boolAs", "params", "provides",
		"reply", "use"],
}

// ── Reading one value as what the document says it is ───────────────────────

asList = function(value)
	"A value where a list belongs: itself, an empty map as the empty list, anything else as one."
	if value isa list then return value
	if value isa map and value.len == 0 then return []
	return [value]
end function

trimmed = function(text)
	"Text without the spaces either end. GRFON keeps them, an argument list has none to spare."
	while text.len > 0 and text[:1] == " "
		text = text[1:]
	end while
	while text.len > 0 and text[-1:] == " "
		text = text[:-1]
	end while
	return text
end function

numberText = function(text)
	"Whether an argument's own spelling makes it a number: 16 does, temperature_2m does not."
	if text.len == 0 then return false
	digits = 0
	point = false
	for i in range(0, text.len - 1)
		ch = text[i]
		if ch >= "0" and ch <= "9" then
			digits = digits + 1
			continue
		end if
		if i == 0 and ch == "-" then continue
		if ch == "." and not point then
			point = true
			continue
		end if
		return false
	end for
	return digits > 0
end function

callOf = function(value)
	"The group a value names and its arguments, or null when it names no group."
	if not (value isa string) then return null
	if value.len == 0 or value[:1] != "@" then return null
	inner = value[1:]
	open = inner.indexOf("(")
	if open == null then return {"name": inner, "args": []}
	close = inner.indexOf(")")
	if close == null then return {"name": inner, "args": []}
	args = []
	for piece in inner[open + 1:close].split(",")
		piece = trimmed(piece)
		if piece == "" then continue
		if numberText(piece) then
			args.push val(piece)
		else
			args.push piece
		end if
	end for
	return {"name": inner[:open], "args": args}
end function

substitute = function(value, parameters, args)
	"Every <name> replaced: a whole value takes the argument's type, a text spells it out."
	if value isa string then
		for i in parameters.indexes
			token = "<" + parameters[i] + ">"
			if value == token then return args[i]
			value = value.replace(token, "" + args[i])
		end for
		return value
	end if
	if value isa list then
		out = []
		for item in value
			out.push substitute(item, parameters, args)
		end for
		return out
	end if
	if value isa map then
		out = {}
		for key in value.indexes
			out[key] = substitute(value[key], parameters, args)
		end for
		return out
	end if
	return value
end function

unfilled = function(value)
	"The <name> a text still carries, or null when every placeholder is filled."
	if value isa string then
		start = value.indexOf("<")
		if start == null then return null
		tail = value[start:]
		stop = tail.indexOf(">")
		if stop == null then return null
		return tail[1:stop]
	end if
	if value isa list then
		for item in value
			found = unfilled(item)
			if found != null then return found
		end for
	end if
	if value isa map then
		for key in value.indexes
			found = unfilled(value[key])
			if found != null then return found
		end for
	end if
	return null
end function

usesReference = function(value)
	"Whether a fragment names another group anywhere in it."
	if value isa string then return callOf(value) != null
	if value isa list then
		for item in value
			if usesReference(item) then return true
		end for
	end if
	if value isa map then
		for key in value.indexes
			if usesReference(value[key]) then return true
		end for
	end if
	return false
end function

// ── Groups ──────────────────────────────────────────────────────────────────

// The groups of the document being resolved. A map rather than a name assigned in resolve(),
// because a function here cannot assign a module-level name: it would make a local of it.
state = {"groups": {}}

fragmentFor = function(call, kind)
	"The reference's fragment of this kind, its arguments bound, or the reason there is none."
	if call == null then return err("a reference is @name")
	if not state.groups.hasIndex(call.name) then
		return err("the document uses a group it does not define: " + call.name)
	end if
	group = state.groups[call.name]
	if not (group isa map) then return err("the group " + call.name + " is not a map of fragments")
	parameters = []
	if group.hasIndex("takes") then parameters = asList(group.takes)
	body = {}
	if parameters.len > 0 then
		if call.args.len != parameters.len then
			plural = " arguments"
			if parameters.len == 1 then plural = " argument"
			return err(call.name + " takes " + parameters.len + plural + ", and was given " +
				call.args.len)
		end if
		for key in group.indexes
			if key == "takes" then continue
			body[key] = substitute(group[key], parameters, call.args)
		end for
		left = unfilled(body)
		if left != null then
			return err("the group " + call.name + " names <" + left + "> and no argument fills it")
		end if
		if usesReference(body) then
			return err("a group with arguments cannot use another group: " + call.name)
		end if
	else
		if call.args.len > 0 then return err("the group " + call.name + " takes no arguments")
		for key in group.indexes
			body[key] = group[key]
		end for
	end if
	if not body.hasIndex(kind) then
		return err(call.name + " holds " + body.indexes.join(" and ") + ", and a " + kind +
			" was expected")
	end if
	return body[kind]
end function

referenced = function(value, found)
	"Every group a fragment names, in the order they appear."
	if value isa string then
		call = callOf(value)
		if call != null then found.push call.name
	else if value isa list then
		for item in value
			referenced(item, found)
		end for
	else if value isa map then
		for key in value.indexes
			referenced(value[key], found)
		end for
	end if
	return found
end function

cycles = function()
	"Whether any group reaches itself, and which one does."
	reaches = {}
	for name in state.groups.indexes
		reaches[name] = referenced(state.groups[name], [])
	end for
	for name in state.groups.indexes
		seen = []
		queue = [name]
		while queue.len > 0
			at = queue.pop
			if at == name and seen.len > 0 then return err("the group " + name + " uses itself")
			if seen.indexOf(at) != null then continue
			seen.push at
			if reaches.hasIndex(at) then
				for next in reaches[at]
					queue.push next
				end for
			end if
		end while
	end for
	return null
end function

// ── A declaration, resolved ─────────────────────────────────────────────────

unknownKeys = function(value, allowed, what)
	"The first key outside the allowed ones, as a refusal."
	if not (value isa map) then return err(what + " is a map")
	for key in value.indexes
		if allowed.indexOf(key) == null then return err(what + " has no " + key)
	end for
	return null
end function

merge = function(base, local)
	"One map with another's keys on top: local wins, wholesale."
	if not (base isa map) then return base
	merged = {}
	for key in base.indexes
		merged[key] = base[key]
	end for
	for key in local.indexes
		if key == "use" then continue
		merged[key] = local[key]
	end for
	return merged
end function

expand = function(value, kind)
	"A reply or an endpoint: a reference, a plain map, or a group used with changes."
	call = callOf(value)
	if call != null then return fragmentFor(call, kind)
	if not (value isa map) then return value
	base = {}
	if value.hasIndex("use") then
		base = fragmentFor(callOf(value.use), kind)
		if base isa error then return base
	end if
	return merge(base, value)
end function

flatten = function(entries, kind)
	"One list with every reference replaced by the group it names."
	out = []
	for entry in asList(entries)
		call = callOf(entry)
		if call == null then
			out.push entry
			continue
		end if
		fragment = fragmentFor(call, kind)
		if fragment isa error then return fragment
		sub = flatten(fragment, kind)
		if sub isa error then return sub
		for item in sub
			out.push item
		end for
	end for
	return out
end function

mergeParams = function(entries)
	"Parameters keyed by name: a later one merges over an earlier one, in the earlier's place."
	out = []
	where = {}
	for entry in entries
		if not (entry isa map) or not entry.hasIndex("name") then
			out.push entry
			continue
		end if
		key = entry.name
		if not where.hasIndex(key) then
			where[key] = out.len
			out.push entry
			continue
		end if
		at = where[key]
		merged = {}
		for field in out[at].indexes
			merged[field] = out[at][field]
		end for
		for field in entry.indexes
			merged[field] = entry[field]
		end for
		out[at] = merged
	end for
	return out
end function

factLines = function(value, kind)
	"A reply's facts or once: lines of parts, whether the document wrote one line or many."
	lines = flatten(value, kind)
	if lines isa error then return lines
	lines = asList(lines)
	if lines.len > 0 and not (lines[0] isa list) then lines = [lines]
	for line in lines
		if not (line isa list) then
			return err("a fact line is a list of parts, and this one is not: " + line)
		end if
	end for
	return lines
end function

replyOf = function(spec)
	"The reply declared.ms reads, or the reason there is none."
	spec = expand(spec, "reply")
	if spec isa error then return spec
	out = {}
	for key in spec.indexes
		if key == "use" then continue
		out[key] = spec[key]
	end for
	for key in lists.reply
		if not out.hasIndex(key) then continue
		if key == "facts" or key == "once" then
			// The kind it is replacing, so `once: @zoneOnce` finds the group's `once` fragment and
			// not a `facts` one it does not have.
			out[key] = factLines(out[key], key)
		else
			// A list part expands a reference too, the way params and provides do: series is how
			// one endpoint says {@hourSeries; @daySeries} without repeating either.
			out[key] = flatten(out[key], key)
		end if
		if out[key] isa error then return out[key]
	end for
	if out.hasIndex("subject") and out.subject isa map then
		for key in lists.subject
			if out.subject.hasIndex(key) then out.subject[key] = asList(out.subject[key])
		end for
	end if
	if out.hasIndex("label") and out.label isa map then
		for key in lists.label
			if out.label.hasIndex(key) then out.label[key] = asList(out.label[key])
		end for
	end if
	return out
end function

endpointOf = function(spec)
	"One endpoint declared.ms reads, or the reason there is none."
	spec = expand(spec, "endpoint")
	if spec isa error then return spec
	stray = unknownKeys(spec, keys.endpoint, "an endpoint")
	if stray != null then return stray
	out = {}
	for key in spec.indexes
		if key == "use" then continue
		out[key] = spec[key]
	end for
	if out.hasIndex("params") then
		params = flatten(out.params, "params")
		if params isa error then return params
		out.params = mergeParams(params)
	end if
	if out.hasIndex("provides") then
		provides = flatten(out.provides, "provides")
		if provides isa error then return provides
		out.provides = asList(provides)
		for entry in out.provides
			if entry isa map and entry.hasIndex("fact") then entry.fact = asList(entry.fact)
		end for
	end if
	if out.hasIndex("redact") then out.redact = asList(out.redact)
	if out.hasIndex("reply") then
		out.reply = replyOf(out.reply)
		if out.reply isa error then return out.reply
	end if
	return out
end function

resolve = function(decl)
	"The declaration declared.ms reads, or the reason the document is not one."
	if not (decl isa map) then return err("a declaration is a map")
	stray = unknownKeys(decl, keys.declaration, "a declaration")
	if stray != null then return stray
	state.groups = {}
	if decl.hasIndex("groups") then
		if not (decl.groups isa map) then return err("groups is a map of names to fragments")
		state.groups = decl.groups
	end if
	// Each group's keys once, rather than on every reference to it.
	for name in state.groups.indexes
		stray = unknownKeys(state.groups[name], keys.group, "the group " + name)
		if stray != null then return stray
	end for
	same = cycles()
	if same != null then return same
	if not decl.hasIndex("endpoints") then return err("a declaration has endpoints")
	if not (decl.endpoints isa map) then return err("endpoints is a map of names")
	out = {}
	for key in ["service", "base", "keyEnv"]
		if decl.hasIndex(key) then out[key] = decl[key]
	end for
	out.endpoints = {}
	for name in decl.endpoints.indexes
		one = endpointOf(decl.endpoints[name])
		if one isa error then return err(name + ": " + one.message)
		out.endpoints[name] = one
	end for
	return out
end function

// ── Reading a document, and writing one ─────────────────────────────────────

strayKey = function(value, path)
	"The path of a _ key, which a document never means: GRFON's own mark for the parts before a pair."
	if value isa list then
		for i in value.indexes
			found = strayKey(value[i], path + "[" + i + "]")
			if found != null then return found
		end for
	else if value isa map then
		for key in value.indexes
			if key == "_" then return path
			found = strayKey(value[key], path + "." + key)
			if found != null then return found
		end for
	end if
	return null
end function

read = function(text)
	"A document's data, or the reason it is not a document: unescaped text reads as structure."
	if text isa RawData then text = text.utf8
	if not (text isa string) then return err("a document is text")
	value = grfon.parse(text)
	stray = strayKey(value, "the document")
	if stray != null then
		return err("a _ key at " + stray + ": a colon or a semicolon in a value went unescaped")
	end if
	return value
end function

// grfon's own escaping covers every character that would read as structure, the :// of a url
// included. What it does not cover is the first character: @ names a group, a digit or a dot
// starts a number (1/0 is 1, 15-minutely variables. is 15, 50% is 50), and a leading space is
// trimmed away - so a value that begins with one says so with a leading escape.
escaped = function(text)
	"A value's text as a document spells it, so that it reads back as itself."
	if text.len == 0 then return ""
	out = grfon.escape(text)
	if "@ .-0123456789".indexOf(out[:1]) != null then out = backslash + out
	return out
end function

write = function(value)
	"A value as a document spells it: a value that is a list stays a list, even a list of one."
	if value isa map then
		parts = []
		for key in value.indexes
			parts.push write(key) + ": " + write(value[key])
		end for
		return "{" + parts.join("; ") + "}"
	end if
	if value isa list then
		if value.len == 0 then return "{}"
		if value.len == 1 then return "{" + write(value[0]) + "; }"
		parts = []
		for item in value
			parts.push write(item)
		end for
		return "{" + parts.join("; ") + "}"
	end if
	if value isa string then return escaped(value)
	return "" + value
end function

text = function(decl)
	"A declaration as a document: what read() takes, with every value spelled so it stays itself."
	return write(decl) + newline
end function
