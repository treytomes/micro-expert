// domain.ms — the three data files a domain is made of, and where a run finds them.
//
// A domain is the combination of its schema, rules and facts: the vocabulary a fact may
// be written in, the rules that draw conclusions from it, and the facts themselves. A run
// reads one of each, and by default they are data/schema.kb, data/rules.kb and
// data/facts.kb:
//
//   micro-expert --domain domains/invoices
//   micro-expert --domain domains/invoices --facts ~/draft-facts.kb
//
// --domain names a folder that holds the three files by those names. --facts, --rules and
// --schema each name one file in place of the folder's piece, so a domain can be tried
// with a draft of one component while the other two are left as the folder has them.
//
// The paths are kept as typed here; knowledge.ms resolves them when it reads or writes,
// and the session holds them so /save-* can put each component back where it came from.

defaultFolder = "data"

pathsFor = function(options)
	"The three paths a run reads: the folder's file for each component, unless one is named."
	folder = provided(options, "domain")
	if folder == null then folder = defaultFolder
	return {
		"facts": pieceOf(options, "facts", file.child(folder, "facts.kb")),
		"rules": pieceOf(options, "rules", file.child(folder, "rules.kb")),
		"schema": pieceOf(options, "schema", file.child(folder, "schema.kb")),
	}
end function

pieceOf = function(options, name, fallback)
	"One component's path: the file named for it, or the folder's file of that name."
	path = provided(options, name)
	if path == null then return fallback
	return path
end function

provided = function(options, name)
	"An option's value when one was actually given, or null when it was absent or blank."
	if not options.hasIndex(name) then return null
	value = options[name]
	if value == null then return null
	if value == "" then return null
	return value
end function
