// Cases for src/services/loader.ms: the folder it is given, and what one refused document costs.
//
// No request leaves the program: a document is read and resolved, never sent. The folder these cases
// build stands beside the suite and is removed again, so a run leaves the repository as it found it.
// Every file call is assigned rather than left standing, so a folder an earlier stopped run left
// behind is written into again instead of halting this one.

run = function(loader, document, knowledge, h)
	folder = file.child(file.parent(shellArgs[0]), "loader-cases")
	made = file.makedir(folder)
	writeDocument = function(name, lines)
		"Writes one document into the folder these cases built."
		handle = file.open(file.child(folder, name), "w")
		if handle isa error then return
		for line in lines
			handle.writeLine(line)
		end for
		handle.close
	end function

	// One document that reads and one that does not: the bad one is refused rather than a stop.
	writeDocument("probe-one.grfon", ["service: probe.one", "base: http://127.0.0.1",
		"endpoints: {reading: {path: /a; reply: {}}}"])
	writeDocument("probe-two.grfon", ["service: probe.two", "bogus: 1",
		"endpoints: {reading: {path: /a; reply: {}}}"])

	loaded = loader.load(document, knowledge, folder)
	count = -1
	if loaded isa map then count = loaded.len
	h.check("a folder passed in is the folder scanned, not the default one", count == 2)

	good = null
	if loaded isa map and loaded.hasIndex("probe-one.grfon") then good = loaded["probe-one.grfon"]
	declared = ""
	if good isa map then declared = good.service
	h.check("the document that reads is the declaration it holds", declared == "probe.one")

	refused = null
	if loaded isa map and loaded.hasIndex("probe-two.grfon") then refused = loaded["probe-two.grfon"]
	besideItsName = 0
	if refused isa error then
		if refused.message.indexOf("probe-two.grfon: ") == 0 then besideItsName = 1
	end if
	// Both entries are still there: the refused file is off, and the document beside it is not.
	h.check("a refused document is an error beside its file name, and costs only that service",
		besideItsName and good isa map and count == 2)

	// A folder that is not there, and a folder with nothing in it: both are refused by name rather
	// than answering a registry with no services in it.
	absent = loader.load(document, knowledge, file.child(folder, "absent"))
	said = 0
	if absent isa error then
		if absent.message.indexOf("could not list") != null then said = 1
	end if
	h.check("a folder that is not there is refused, naming it", said)

	bareFolder = file.child(folder, "bare")
	made = file.makedir(bareFolder)
	bare = loader.load(document, knowledge, bareFolder)
	namedBare = 0
	if bare isa error then
		if bare.message.indexOf(".grfon") != null then namedBare = 1
	end if
	h.check("a folder with no document in it is refused, naming the suffix", namedBare)

	// The default folder is the repository's, found from the entry script rather than the working
	// directory: a host started from elsewhere still reads the three shipped services. The entry is
	// made absolute first, since a relative one is only meaningful from the folder it was typed in,
	// and the working directory is moved to a folder with no services in it.
	entry = shellArgs[0]
	if entry.indexOf(":") != 1 and entry[:1] != "/" then entry = file.child(file.curdir, entry)
	savedArgs = globals["shellArgs"]
	savedDir = file.curdir
	globals["shellArgs"] = [entry]
	moved = file.setdir(folder)
	shipped = loader.load(document, knowledge)
	back = file.setdir(savedDir)
	globals["shellArgs"] = savedArgs
	found = -1
	if shipped isa map then found = shipped.len
	h.check("the default folder comes from the entry script, not the working directory", found == 3)

	// Leave the repository as it was found.
	gone = file.delete(file.child(folder, "probe-one.grfon"))
	gone = file.delete(file.child(folder, "probe-two.grfon"))
	gone = file.delete(bareFolder)
	gone = file.delete(folder)
end function
