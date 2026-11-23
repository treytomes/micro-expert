// Cases for the .env reader: the file's shapes, a shell's export spelling, the environment
// winning over them, and an empty value counting as absent.

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

	env["CODEBUFF_DOTENV_CHECK"] = "  from environment  "
	h.check("the environment wins", dotenv.find("CODEBUFF_DOTENV_CHECK", shellArgs[0]) == "from environment")
	env["CODEBUFF_DOTENV_CHECK"] = ""
	h.check("an empty environment value is absent", dotenv.find("CODEBUFF_DOTENV_CHECK", shellArgs[0]) == null)
	h.check("a setting nobody has is null", dotenv.find("CODEBUFF_DOTENV_ABSENT", shellArgs[0]) == null)

	// A load puts a file's settings into the interpreter's own env map, once, and leaves any
	// setting the environment already holds as it is.
	names = ["PLAIN", "QUOTED", "SINGLE", "SPACED", "WITH_EQUALS", "EXPORTED", "EXPORTS"]
	saved = {}
	for name in names
		if env.hasIndex(name) then saved[name] = env[name]
		env.remove(name)
	end for
	env["QUOTED"] = "  from environment  "

	h.check("a load answers how many settings it added", dotenv.load(path) == 6)
	h.check("a setting in the file lands in env", env["PLAIN"] == "value")
	h.check("a loaded value has its quotes removed", env["SINGLE"] == "one word")
	h.check("the environment's own value is left alone", env["QUOTED"] == "  from environment  ")
	h.check("an empty setting is not put in env", not env.hasIndex("EMPTY"))
	h.check("a file is loaded only once", dotenv.load(path) == 0)
	h.check("a file that is not there adds nothing", dotenv.load(path + ".missing") == 0)
	h.check("a loaded setting is found", dotenv.find("PLAIN", shellArgs[0]) == "value")
	h.check("a setting is read from the environment after a load", dotenv.find("QUOTED", shellArgs[0]) == "from environment")

	// env is one map for the whole run, so put it back the way the checks found it.
	for name in names
		env.remove(name)
	end for
	for kv in saved
		env[kv.key] = kv.value
	end for
end function
