// Cases for the .env loader: the file's shapes, a shell's export spelling, and a setting
// landing in env with the environment's own value left alone.

run = function(dotenv, h)
	// The fixture sits beside the runner, wherever the suite is run from.
	path = file.child(file.parent(shellArgs[0]), "settings.env")
	values = dotenv.read(path)

	h.check("a plain setting is read", values.PLAIN == "value")
	h.check("double quotes are removed", values.QUOTED == "two words")
	h.check("single quotes too", values.SINGLE == "one word")
	h.check("spaces around a value are dropped", values.SPACED == "padded")
	h.check("only the first = separates the two", values.WITH_EQUALS == "a=b")
	h.check("an empty value is still a setting", values.hasIndex("EMPTY") and values.EMPTY == "")
	h.check("a comment line is not a setting", values.len == 8)
	h.check("a line with no = is skipped", not values.hasIndex("NOT_A_SETTING"))
	h.check("an export line is a setting", values.EXPORTED == "from a shell")
	h.check("a key that only starts with export is left alone", values.EXPORTS == "nothing")
	h.check("a file that is not there is an empty map", dotenv.read(path + ".missing").len == 0)

	// Loading the fixture puts its settings in the interpreter's own env map, where the
	// environment's value wins and an empty one counts as absent.
	names = ["PLAIN", "QUOTED", "SINGLE", "SPACED", "WITH_EQUALS", "EXPORTED", "EXPORTS"]
	saved = {}
	for name in names
		if env.hasIndex(name) then saved[name] = env[name]
		env.remove(name)
	end for
	env["QUOTED"] = "  from environment  "
	env["PLAIN"] = ""

	dotenv.load(path)
	h.check("a setting in the file lands in env", env["SINGLE"] == "one word")
	h.check("the environment's own value is left alone", env["QUOTED"] == "  from environment  ")
	h.check("an empty environment value takes the file's value", env["PLAIN"] == "value")
	h.check("an empty setting is not put in env", not env.hasIndex("EMPTY"))

	before = env.len
	dotenv.load(path + ".missing")
	h.check("a file that is not there leaves env alone", env.len == before)

	// env is one map for the whole run, so put it back the way the checks found it.
	for name in names
		env.remove(name)
	end for
	for kv in saved
		env[kv.key] = kv.value
	end for
end function
