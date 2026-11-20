// The library's cases moved with it into the micro-repl submodule, where they sit beside the
// module they test and run on their own (src/repl/test/run.ms). This suite does not import
// them, just as it does not import the parser's or the logger's: each submodule carries its
// own suite and is run from its own folder.
//
// What stays here is the single check that is about this repository rather than the library:
// examples/notes.ms is a whole program written on the library and nothing else, so it is what
// proves the library stands alone outside its own repository. A second import in it would be
// that claim failing quietly.

run = function(h)
	"Checks this repository's notes example against the library it is built on."
	example = file.readLines(file.child("examples", "notes.ms"))
	imports = []
	for line in example
		if line.indexOf("import ") == 0 then imports.push(line)
	end for
	h.check("the notes example imports the repl library and nothing else",
		example.len > 0 and imports.len == 1 and
			imports[0].indexOf("src/repl/repl") != null)
end function
