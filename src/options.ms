// options.ms — the command line micro-expert declares.
//
// The table lives here rather than in main.ms so the suite can read the same declarations
// the program builds its parser from: a default is a decision, and the one that went wrong
// - verbose on by default - was invisible until a run printed a proof tree nobody asked for.
// test/options.ms parses arguments against this table and pins what it says.
//
// The cli library is handed in rather than imported, the way triples.ms is handed to the
// loaders: the cmd filled here was made by the caller's copy, and one copy's parse is the
// one that reads it.

declare = function(cli, cmd)
	"Adds every option a run takes to cmd, with the defaults the README states."
	cli.add(cmd, {
		"name": "depth",
		"aliases": ["--depth"],
		"type": "number",
		"default": 8,
		"description": "Maximum backward-chaining depth.",
	})
	cli.add(cmd, {
		"name": "verbose",
		"aliases": ["--verbose"],
		"type": "flag",
		"default": 0,
		"description": "Print the proof tree before each answer.",
	})
	cli.add(cmd, {
		"name": "nlp",
		"aliases": ["--nlp"],
		"type": "flag",
		"default": 0,
		"description": "Say answers, and the proof trees above them, as sentences.",
	})
	cli.add(cmd, {
		"name": "domain",
		"aliases": ["--domain"],
		"type": "string",
		"description": "Folder holding facts.kb, rules.kb and schema.kb (default: data).",
	})
	cli.add(cmd, {
		"name": "facts",
		"aliases": ["--facts"],
		"type": "string",
		"description": "Facts file, in place of the domain's facts.kb.",
	})
	cli.add(cmd, {
		"name": "rules",
		"aliases": ["--rules"],
		"type": "string",
		"description": "Rules file, in place of the domain's rules.kb.",
	})
	cli.add(cmd, {
		"name": "schema",
		"aliases": ["--schema"],
		"type": "string",
		"description": "Schema file, in place of the domain's schema.kb.",
	})
	cli.add(cmd, {
		"name": "log-level",
		"aliases": ["--log-level"],
		"type": "string",
		"default": "information",
		"description": "Lowest level to log: debug, information, warning, error, fatal.",
	})
end function
