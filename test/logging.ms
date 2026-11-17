// Cases for logging.ms, aimed at the rolling-file prune.
//
// The prune deletes real files, so each case works in its own folder under the system
// temp directory and clears it away afterwards. The stamps are far in the past, so those
// files always sort ahead of the one today's run would write.

import "dateTime"

scratchDir = function()
	"Where the case folder goes: the system temp directory when there is one."
	if env.hasIndex("TEMP") then return file.child(env["TEMP"], "micro-expert-prune-test")
	if env.hasIndex("TMP") then return file.child(env["TMP"], "micro-expert-prune-test")
	return "micro-expert-prune-test"
end function

clearDir = function(dir)
	"Removes the files in dir, then dir itself; a folder that is not there is left alone."
	names = file.children(dir)
	if names isa error then return null
	for name in names
		file.delete(file.child(dir, name))
	end for
	file.delete(dir)
	return null
end function

startDir = function(dir)
	"An empty folder for one case."
	clearDir(dir)
	file.makedir(dir)
	return null
end function

makeFile = function(dir, name)
	"Creates one small file in dir."
	handle = file.open(file.child(dir, name), "a")
	handle.writeLine("x")
	handle.close
	return null
end function

makeOldFiles = function(dir)
	"Five dated files, old enough that every one of them is a candidate to prune."
	for stamp in ["20000101", "20000102", "20000103", "20000104", "20000105"]
		makeFile(dir, "t-" + stamp + ".log")
	end for
	return null
end function

namesIn = function(dir)
	"Sorted names of the files in dir."
	names = file.children(dir)
	if names isa error then return []
	return names.sort
end function

loggerOn = function(log, dir, retained, extra=null)
	"A logger that prunes dir, with no console output and no writes of its own."
	settings = {"name": "test", "path": dir, "fileName": "t-.log",
		"retainedFileCount": retained, "console": 0, "file": 0}
	if extra != null then settings = settings + extra
	return log.newLogger(settings)
end function

run = function(log, h)
	"Checks which files the prune keeps, and which files it counts at all."
	dir = scratchDir()

	// ── How many are kept ────────────────────────────────────────────────────

	startDir(dir)
	makeOldFiles(dir)
	loggerOn(log, dir, 2)
	h.check("prune keeps the newest file and today's slot", namesIn(dir) == ["t-20000105.log"])

	startDir(dir)
	makeFile(dir, "t-20000101.log")
	loggerOn(log, dir, 3)
	h.check("prune leaves a folder under the limit alone", namesIn(dir) == ["t-20000101.log"])

	startDir(dir)
	makeOldFiles(dir)
	loggerOn(log, dir, 0)
	h.check("retainedFileCount 0 keeps every file", namesIn(dir).len == 5)

	startDir(dir)
	makeOldFiles(dir)
	loggerOn(log, dir, 1, {"rollingInterval": "infinite"})
	h.check("an infinite interval never prunes", namesIn(dir).len == 5)

	// ── What counts as a rolled file ─────────────────────────────────────────

	startDir(dir)
	makeOldFiles(dir)
	makeFile(dir, "notes.txt")
	makeFile(dir, "t-old.log")
	makeFile(dir, "other-20000101.log")
	loggerOn(log, dir, 2)
	h.check("prune ignores files it did not roll",
		namesIn(dir).join(",") == "notes.txt,other-20000101.log,t-20000105.log,t-old.log")

	// ── Today's file ─────────────────────────────────────────────────────────

	startDir(dir)
	makeOldFiles(dir)
	current = "t-" + dateTime.str(dateTime.nowVal, "yyyyMMdd") + ".log"
	makeFile(dir, current)
	loggerOn(log, dir, 2)
	h.check("prune spares the file it is about to write",
		namesIn(dir).join(",") == "t-20000105.log," + current)

	clearDir(dir)
end function
