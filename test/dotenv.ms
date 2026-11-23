// Cases for the .env reader: the file's shapes, the environment winning over them, and an
// empty value counting as absent.

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
	h.check("a comment line is not a setting", values.len == 6)
	h.check("a line with no = is skipped", not values.hasIndex("NOT_A_SETTING"))
	h.check("a file that is not there is an empty map", dotenv.read(path + ".missing").len == 0)

	env["CODEBUFF_DOTENV_CHECK"] = "  from environment  "
	h.check("the environment wins", dotenv.find("CODEBUFF_DOTENV_CHECK", shellArgs[0]) == "from environment")
	env["CODEBUFF_DOTENV_CHECK"] = ""
	h.check("an empty environment value is absent", dotenv.find("CODEBUFF_DOTENV_CHECK", shellArgs[0]) == null)
	h.check("a setting nobody has is null", dotenv.find("CODEBUFF_DOTENV_ABSENT", shellArgs[0]) == null)
end function
