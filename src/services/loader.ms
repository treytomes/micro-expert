// loader.ms — every service in a folder, found and read: one entry point for the declarations.
//
// A service is a document - services/ipwhois.grfon, services/geocode.grfon, services/openmeteo.grfon
// - and this module is what turns a folder of them into the maps a session can ask. It lists the
// folder, takes every name ending in `.grfon`, and reads each through src/services/document.ms. A
// file that is not a declaration costs that one service, not the run: its entry is the reason it
// could not be read, so a host drops that one and says which file it was.
//
//   import "services/loader"
//   loaded = globals["services/loader"].load(globals["services/document"], globals["knowledge"])
//   for kv in loaded
//       if kv.value isa error then print kv.key + " is off: " + kv.value.message
//   end for
//
// The default folder is services/ at the repository's root, found from the entry script rather than
// from the working directory: a run started from another folder reads the same documents. A host
// that embeds this module and has no command line is answered from where the module itself stands.
// The map is keyed by file name and sorted by it, so every host reads the same folder into the same
// order - which is the order a session tries the services in when more than one declares the same
// fact. A host whose documents stand somewhere else passes that folder as the third argument. The
// reader and the path rule arrive as arguments because an import inside a module here binds no name.

extension = ".grfon"
defaultFolder = "services"


load = function(document, knowledge, folder=null)
	"Every .grfon in folder as a declaration, keyed by file name: an error where a file is refused."
	if folder == null then folder = folderFor(knowledge)
	names = file.children(folder)
	if names isa error then return err("could not list " + folder + ": " + names.message)
	// The names that are documents, sorted so every host reads the folder in one order.
	found = []
	for name in names
		if name.len > extension.len and name[-extension.len:] == extension then found.push name
	end for
	found.sort
	// A folder holding no document is a folder found in the wrong place, not a run with no services.
	if found.len == 0 then return err("no " + extension + " service document is in " + folder)
	loaded = {}
	for name in found
		loaded[name] = readOne(document, file.child(folder, name))
	end for
	return loaded
end function


folderFor = function(knowledge)
	"The repository's services folder: from the entry script's root, else this module's own place."
	// The entry script names the repository its own file stands in, whatever the working directory
	// is. The module's own place answers a host that embeds this one and has no command line: its
	// path goes through knowledge.resolvePath, the program's one path rule, which reads the source
	// location as it is given.
	roots = []
	if shellArgs.len > 0 then roots.push(file.parent(file.parent(shellArgs[0])))
	roots.push(file.parent(file.parent(knowledge.resolvePath("loader.ms", info(@folderFor).sourceLoc))))
	for root in roots
		folder = file.child(root, defaultFolder)
		if file.exists(folder) then return folder
	end for
	// Neither has one, so the error that follows names the folder the run was meant to read.
	return file.child(roots[0], defaultFolder)
end function


readOne = function(document, path)
	"One document read: the declaration it is, or the reason this file is not one."
	text = file.loadRaw(path)
	if text isa error then return err(file.name(path) + ": " + text.message)
	decl = document.read(text)
	if decl isa error then return err(file.name(path) + ": " + decl.message)
	resolved = document.resolve(decl)
	if resolved isa error then return err(file.name(path) + ": " + resolved.message)
	return resolved
end function
