// Cases for splitting a command line into the options the cli library reads and the bare
// words a program reads itself.
//
// The command here is a small one of each type rather than either service's table, so a case
// failing says what the split did, not which endpoint happened to declare a parameter that
// way.

run = function(cli, client, h)
	cmd = function
		"A command carrying one of each type, as a program declares its own."
		made = cli.newCommand("demo", "1.0.0", "a command line")
		cli.add(made, {"name": "json", "aliases": ["--json"], "type": "flag",
			"description": "A switch."})
		cli.add(made, {"name": "q", "aliases": ["--q"], "type": "string",
			"description": "A query."})
		cli.add(made, {"name": "limit", "aliases": ["--limit"], "type": "number",
			"description": "A count."})
		cli.add(made, {"name": "addressdetails", "aliases": ["--addressdetails"], "type": "string",
			"description": "A boolean."})
		cli.add(made, {"name": "osm-ids", "aliases": ["--osm-ids"], "type": "list",
			"description": "A list."})
		return made
	end function

	spec = {"params": [
		{"name": "addressdetails", "type": "bool"},
		{"name": "osm_ids", "type": "csv"},
	]}

	split = function(arguments)
		"Splits a command line that starts with the script path, as a run's does."
		return client.splitArguments(cli, ["demo.ms"] + arguments, cmd(), spec)
	end function

	// ── Words and options ────────────────────────────────────────────────────

	bare = split(["reverse", "48.8", "2.3"])
	h.check("bare words are left as words", bare.words.join(" ") == "reverse 48.8 2.3")
	h.check("and none of them becomes an option", bare.options.len == 0)

	taken = split(["--limit", "3", "Paris"])
	h.check("an option takes the next argument as its value", taken.options.join(" ") == "--limit 3")
	h.check("the word after that keeps its place", taken.words.join(" ") == "Paris")

	inline = split(["--limit=3", "Paris"])
	h.check("an inline value stays one token", inline.options.join(" ") == "--limit=3")
	h.check("so it does not swallow the word after it", inline.words.join(" ") == "Paris")

	switched = split(["--json", "Paris"])
	h.check("a flag takes no value", switched.options.join(" ") == "--json")
	h.check("so the word after it stays a word", switched.words.join(" ") == "Paris")

	helped = split(["--help", "Paris"])
	h.check("--help takes no value either", helped.options.join(" ") == "--help")
	h.check("so the word after it is still a word", helped.words.join(" ") == "Paris")

	negative = split(["reverse", "-33.8688", "151.2093"])
	h.check("a negative number is a word, not an option",
		negative.words.join(" ") == "reverse -33.8688 151.2093" and negative.options.len == 0)

	unknown = split(["--bogus", "Paris"])
	h.check("an undeclared option is passed on rather than dropped",
		unknown.options[0] == "--bogus")

	// ── Spellings ────────────────────────────────────────────────────────────

	under = split(["--osm_ids", "R253832"])
	h.check("an underscored name becomes the declared spelling", under.options[0] == "--osm-ids")
	h.check("and a list option still takes its value", under.options[1] == "R253832")

	off = split(["--no-addressdetails"])
	h.check("--no-name becomes the parameter", off.options[0] == "--addressdetails")
	h.check("set to false", off.options[1] == "false")

	on = split(["--addressdetails"])
	h.check("a boolean with no value means true", on.options.join(" ") == "--addressdetails true")

	notABoolean = split(["--no-limit"])
	h.check("--no-name on anything else is left for the library",
		notABoolean.options[0] == "--no-limit")

	// ── The shell's quotes ───────────────────────────────────────────────────

	quote = char(34)
	quoted = split(["--q", quote + "Eiffel", "Tower" + quote])
	h.check("a quoted value the shell split is put back together",
		quoted.options[1] == quote + "Eiffel Tower" + quote)
	h.check("and no fragment of it is left as a word", quoted.words.len == 0)

	// ── What the library then reads ──────────────────────────────────────────

	parsed = cli.parse(cmd(), ["demo.ms"] + quoted.options)
	h.check("the library reads the split's options", parsed.ok)
	h.check("and the quoted value arrives whole", parsed.values.q == "Eiffel Tower")

	repeat = split(["--osm-ids", "R1", "--osm-ids", "W2"])
	listed = cli.parse(cmd(), ["demo.ms"] + repeat.options)
	h.check("a repeated list option collects both values", listed.values["osm-ids"].len == 2)
	h.check("in the order they were given", listed.values["osm-ids"].join(",") == "R1,W2")
end function
