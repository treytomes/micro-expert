// cli.ms — a small declarative command-line parser, modelled on System.CommandLine.
//
// Options are declared as maps, parsed against the shell arguments, and used to
// generate --help and --version output automatically:
//
//   cmd = cli.newCommand("micro-expert", "0.1.0", "A little expert system.")
//   cli.add(cmd, {"name": "facts", "aliases": ["--facts", "-f"],
//                 "type": "string", "description": "A facts file to load."})
//   options = cli.parse(cmd, shellArgs)
//   if not options.ok then print options.error
//
// Option map keys:
//   name         key in parse's values map              (required)
//   aliases      spellings, e.g. ["--facts", "-f"]      (default ["--<name>"])
//   type         "flag" | "string" | "number" | "list"  (default "flag")
//   description  help text, shown by --help             (required)
//   default      value used when the option is absent
//
// parse returns {"ok", "error", "values", "help", "version"}; values holds one
// entry per declared option. --help/-h and --version/-v work for every command.

helpOption = {"name": "help", "aliases": ["--help", "-h"], "type": "flag",
	"description": "Show this help text and exit."}

versionOption = {"name": "version", "aliases": ["--version", "-v"], "type": "flag",
	"description": "Show version information and exit."}

newCommand = function(name, version, description=null)
	"Builds a command: a name, a version string, and room for options."
	return {"name": name, "version": version, "description": description, "options": []}
end function

add = function(cmd, option)
	"Declares one option on the command, filling in type and alias defaults."
	// MiniScript 2 raises Key Not Found on a missing map key, so the keys an
	// option map may omit are filled in here rather than read defensively later.
	if not option.hasIndex("type") then option.type = "flag"
	if not option.hasIndex("aliases") then option.aliases = ["--" + option.name]
	cmd.options.push(option)
	return cmd
end function

parse = function(cmd, rawArgs)
	"Parses raw shell arguments, returning ok/error/values/help/version."
	result = {"ok": 1, "error": null, "values": {}, "help": 0, "version": 0}
	for option in cmd.options
		result.values[option.name] = defaultValue(option)
	end for

	byAlias = {}
	for option in allOptions(cmd)
		for alias in option.aliases
			byAlias[alias] = option
		end for
	end for

	args = normalizeArgs(rawArgs)
	i = 0
	while i < args.len
		token = args[i]
		if token.len == 0 then
			return fail(result, "empty argument")
		end if
		if token[0] != "-" then
			return fail(result, "unexpected argument: " + token)
		end if

		// --option=value arrives as one token; split it so the rest of the
		// parser only ever sees "--option value".
		inlineValue = null
		equalsAt = token.indexOf("=")
		if equalsAt != null then
			if equalsAt > 0 then
				inlineValue = token[equalsAt + 1:]
				token = token[:equalsAt]
			end if
		end if

		if not byAlias.hasIndex(token) then
			return fail(result, "unknown option: " + token)
		end if
		option = byAlias[token]

		step = 1
		if option.name == "help" then
			result.help = 1
		else if option.name == "version" then
			result.version = 1
		else if option.type == "flag" then
			if inlineValue != null then
				return fail(result, token + " does not take a value")
			end if
			result.values[option.name] = 1
		else
			text = inlineValue
			if text == null then
				if i + 1 >= args.len then
					return fail(result, "option requires a value: " + token)
				end if
				text = args[i + 1]
				step = 2
			end if
			value = coerce(option, text)
			if value isa error then
				return fail(result, token + ": " + value.message)
			end if
			if option.type == "list" then
				result.values[option.name].push(value)
			else
				result.values[option.name] = value
			end if
		end if
		i = i + step
	end while

	return result
end function

// ── Argument preprocessing ────────────────────────────────────────────────────

// The MiniScript CLI splits its raw command line on whitespace and keeps quote
// characters, so `--query "household_avoids(trey, ?a)"` arrives as the two
// shellArgs entries  --query="household_avoids(trey,  and  ?a)" . Rejoin tokens
// that end mid-quote so callers see whole strings, whatever the shell did.
normalizeArgs = function(rawArgs)
	tokens = []
	i = 1									// shellArgs[0] is the script path
	while i < rawArgs.len
		text = rawArgs[i]
		while hasOpenQuote(text) and i + 1 < rawArgs.len
			i = i + 1
			text = text + " " + rawArgs[i]
		end while
		tokens.push(text)
		i = i + 1
	end while
	return tokens
end function

hasOpenQuote = function(text)
	"True when text contains an odd number of double quotes, i.e. ends quoted."
	count = 0
	for c in text
		if c == """" then count = count + 1
	end for
	return count % 2
end function

trimQuotes = function(text)
	if text.len >= 2 then
		if text[0] == """" then
			if text[-1] == """" then
				return text[1:-1]
			end if
		end if
	end if
	return text
end function

// ── Value handling ────────────────────────────────────────────────────────────

defaultValue = function(option)
	if option.hasIndex("default") then return option.default
	if option.type == "flag" then return 0
	if option.type == "list" then return []
	return null
end function

coerce = function(option, text)
	text = trimQuotes(text)
	if option.type == "number" then
		if not isNumber(text) then return err("not a number: " + text)
		return text.val
	end if
	return text
end function

// .val is lenient ("12abc".val is 12), so check the shape before converting.
isNumber = function(text)
	if text.len == 0 then return 0
	digits = 0
	dots = 0
	for idx in text.indexes
		c = text[idx]
		if c == "-" then
			if idx != 0 then return 0
		else if c == "." then
			dots = dots + 1
			if dots > 1 then return 0
		else if "0123456789".indexOf(c) == null then
			return 0
		else
			digits = digits + 1
		end if
	end for
	return digits > 0
end function

// ── Generated output ──────────────────────────────────────────────────────────

helpText = function(cmd)
	options = allOptions(cmd)
	width = 0
	for option in options
		label = optionLabel(option)
		if label.len > width then width = label.len
	end for

	lines = []
	lines.push(cmd.name + " " + cmd.version)
	if cmd.description != null then
		lines.push(cmd.description)
	end if
	lines.push("")
	lines.push("Usage:")
	lines.push("  " + cmd.name + " [options]")
	lines.push("")
	lines.push("Options:")
	for option in options
		label = optionLabel(option)
		lines.push("  " + label + " " * (width - label.len + 2) + optionHelp(option))
	end for
	return lines.join(char(10))
end function

versionLine = function(cmd)
	return cmd.name + " " + cmd.version
end function

allOptions = function(cmd)
	options = cmd.options[:]
	options.push(helpOption)
	options.push(versionOption)
	return options
end function

optionLabel = function(option)
	label = option.aliases.join(", ")
	placeholder = placeholderFor(option.type)
	if placeholder != "" then
		label = label + " <" + placeholder + ">"
		if option.type == "list" then
			label = label + "..."
		end if
	end if
	return label
end function

optionHelp = function(option)
	text = option.description
	if option.hasIndex("default") then
		text = text + " (default: " + str(option.default) + ")"
	end if
	return text
end function

placeholderFor = function(typeName)
	if typeName == "string" then return "TEXT"
	if typeName == "number" then return "NUM"
	if typeName == "list" then return "TEXT"
	return ""
end function

fail = function(result, message)
	result.ok = 0
	result.error = message
	return result
end function
