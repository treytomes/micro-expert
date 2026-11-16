// cli.ms: declarations, parsing, defaults, mistakes, and generated output.

run = function(cli, h)
	cmd = cli.newCommand("demo", "1.2.3", "A demo command.")
	cli.add(cmd, {"name": "depth", "aliases": ["--depth"], "type": "number", "default": 8,
		"description": "How deep to go."})
	cli.add(cmd, {"name": "verbose", "aliases": ["--verbose"], "type": "flag",
		"description": "Say more."})
	cli.add(cmd, {"name": "log-level", "aliases": ["--log-level"], "type": "string",
		"default": "information", "description": "Lowest level to log."})
	cli.add(cmd, {"name": "tag", "aliases": ["--tag"], "type": "list",
		"description": "A repeatable label."})

	parse = function(args)
		return cli.parse(cmd, args)
	end function

	// ── Defaults ─────────────────────────────────────────────────────────────

	plain = parse(["demo.ms"])
	h.check("a bare command line parses", plain.ok)
	h.check("a number keeps its default", plain.values.depth == 8)
	h.check("a string keeps its default", plain.values["log-level"] == "information")
	h.check("a flag starts off", plain.values.verbose == 0)
	h.check("a list starts empty", plain.values.tag.len == 0)
	h.check("nothing asks for help or version", plain.help == 0 and plain.version == 0)

	// ── Values, in either spelling ───────────────────────────────────────────

	h.check("a number takes the next argument", parse(["demo.ms", "--depth", "3"]).values.depth == 3)
	h.check("a number takes an inline value", parse(["demo.ms", "--depth=3"]).values.depth == 3)
	h.check("a negative number is a number", parse(["demo.ms", "--depth", "-2"]).values.depth == -2)
	h.check("a string takes an inline value", parse(["demo.ms", "--log-level=debug"]).values["log-level"] == "debug")
	h.check("a flag turns on", parse(["demo.ms", "--verbose"]).values.verbose == 1)

	// ── Lists ────────────────────────────────────────────────────────────────

	listed = parse(["demo.ms", "--tag", "a", "--tag", "b"])
	h.check("a list collects every value", listed.values.tag.len == 2)
	h.check("a list keeps them in order", listed.values.tag.join(",") == "a,b")
	h.check("a list takes an inline value", parse(["demo.ms", "--tag=x"]).values.tag.join(",") == "x")

	// ── Help and version ─────────────────────────────────────────────────────

	h.check("--help asks for help", parse(["demo.ms", "--help"]).help == 1)
	h.check("-h asks for help", parse(["demo.ms", "-h"]).help == 1)
	h.check("--version asks for the version", parse(["demo.ms", "--version"]).version == 1)
	h.check("-v asks for the version", parse(["demo.ms", "-v"]).version == 1)
	h.check("the version line names the command", cli.versionLine(cmd) == "demo 1.2.3")

	// ── Mistakes ─────────────────────────────────────────────────────────────

	badNumber = parse(["demo.ms", "--depth", "abc"])
	h.check("a value that is not a number is rejected", not badNumber.ok)
	h.check("and the error says so", badNumber.error.indexOf("not a number") != null)
	missing = parse(["demo.ms", "--depth"])
	h.check("a missing value is rejected", not missing.ok)
	h.check("and the error names the option", missing.error.indexOf("requires a value") != null)
	unknown = parse(["demo.ms", "--bogus"])
	h.check("an unknown option is rejected", not unknown.ok)
	h.check("and the error names it", unknown.error.indexOf("unknown option") != null)
	h.check("a stray argument is rejected", not parse(["demo.ms", "extra"]).ok)
	h.check("a flag refuses an inline value", not parse(["demo.ms", "--verbose=1"]).ok)

	// ── Quoted arguments ─────────────────────────────────────────────────────
	// The CLI splits the command line on whitespace and keeps quote characters, so
	// a quoted value arrives in pieces; the parser rejoins them and trims the quotes.

	quote = char(34)
	quoted = parse(["demo.ms", "--tag", quote + "two", "words" + quote])
	h.check("a quoted value is rejoined", quoted.values.tag.join(",") == "two words")

	// ── Generated help ───────────────────────────────────────────────────────

	text = cli.helpText(cmd)
	h.check("help names the command and version", text.indexOf("demo 1.2.3") != null)
	h.check("help lists an option with its placeholder", text.indexOf("--depth <NUM>") != null)
	h.check("help shows a default", text.indexOf("(default: 8)") != null)
	h.check("help includes the built-in options", text.indexOf("--help") != null and text.indexOf("--version") != null)
end function
