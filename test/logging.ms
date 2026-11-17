// Cases for logging.ms: message templates, levels, tags, file names, directories, the
// rolling-file prune, and the file sink with its failures.
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
	"Removes everything in dir, then dir itself; a path that is not a folder is left alone."
	names = file.children(dir)
	if names isa error then return null
	for name in names
		path = file.child(dir, name)
		if file.children(path) isa error then
			file.delete(path)
		else
			clearDir(path)
		end if
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

fileLines = function(path)
	"Every line of a text file, without its line endings."
	handle = file.open(path, "r")
	if handle isa error then return []
	lines = []
	line = handle.readLine
	while line != null
		lines.push(line)
		line = handle.readLine
	end while
	handle.close
	return lines
end function

loggerOn = function(log, dir, retained, extra=null)
	"A logger that prunes dir, with no console output and no writes of its own."
	settings = {"name": "test", "path": dir, "fileName": "t-.log",
		"retainedFileCount": retained, "console": 0, "file": 0}
	if extra != null then settings = settings + extra
	return log.newLogger(settings)
end function

run = function(log, h)
	"Checks templates, levels, tags, file names, directories, the prune and the file sink."
	dir = scratchDir()

	// ── Message templates ────────────────────────────────────────────────────

	h.check("render fills a hole", log.render("Hello {Name}!", {"Name": "Trey"}) == "Hello Trey!")
	h.check("render keeps a hole with no property as written", log.render("Hello {Name}!", {}) == "Hello {Name}!")
	h.check("render drops a format clause", log.render("{@Count:000}", {"Count": 7}) == "7")
	h.check("render keeps an unterminated brace", log.render("open {Name", {"Name": "x"}) == "open {Name")
	h.check("render leaves a template with no holes alone", log.render("plain text", {"Name": "x"}) == "plain text")
	h.check("render without properties keeps the template", log.render("{Name}", null) == "{Name}")

	// ── Hole names ───────────────────────────────────────────────────────────

	h.check("holeName reads a bare name", log.holeName("Name") == "Name")
	h.check("holeName drops a format clause", log.holeName("Name:l") == "Name")
	h.check("holeName drops a destructuring sigil", log.holeName("@Name") == "Name")
	h.check("holeName drops a stringify sigil", log.holeName("$Name") == "Name")
	h.check("holeName drops both", log.holeName("@Name:l") == "Name")

	// ── Levels ───────────────────────────────────────────────────────────────

	h.check("levelRank reads a name", log.levelRank("debug") == 0)
	h.check("levelRank ignores case", log.levelRank("WARNING") == 2)
	h.check("levelRank passes a number through", log.levelRank(4) == 4)
	h.check("levelRank has no rank for an unknown name", log.levelRank("verbose") == null)
	h.check("levelRank has no rank for null", log.levelRank(null) == null)

	// ── Minimum level ────────────────────────────────────────────────────────

	gated = loggerOn(log, dir, 7)
	h.check("setMinimumLevel accepts a level name", gated.setMinimumLevel("warning") == null)
	h.check("setMinimumLevel rejects an unknown name", gated.setMinimumLevel("verbose") isa error)
	h.check("isEnabled drops a level below the minimum", gated.isEnabled("information") == 0)
	h.check("isEnabled admits the minimum level", gated.isEnabled("warning") == 1)
	h.check("isEnabled treats an unknown name as information", gated.isEnabled("loud") == 0)

	// ── Level tags ───────────────────────────────────────────────────────────

	plainTags = loggerOn(log, dir, 7, {"colors": 0})
	h.check("levelTag names the level plainly", plainTags.levelTag(1) == "INF")
	h.check("levelTag names fatal plainly", plainTags.levelTag(4) == "FTL")
	tinted = loggerOn(log, dir, 7, {"colors": 1})
	tag = tinted.levelTag(2)
	h.check("levelTag wraps the label when colours are on",
		tinted.colors == 0 or (tag.indexOf("WRN") != null and tag.len > 3))

	// ── Property values ──────────────────────────────────────────────────────

	h.check("formatValue leaves a string alone", log.formatValue("x") == "x")
	h.check("formatValue renders a number", log.formatValue(7) == "7")
	h.check("formatValue renders null", log.formatValue(null) == "null")

	// ── Which names count as rolled ──────────────────────────────────────────

	rolling = loggerOn(log, dir, 7)
	h.check("a dated name is a rolling file", rolling.isRollingFile("t-20261117.log"))
	h.check("letters in the date are not a rolling file", rolling.isRollingFile("t-2026ab17.log") == 0)
	h.check("a short name is not a rolling file", rolling.isRollingFile("t-2026.log") == 0)
	h.check("another prefix is not a rolling file", rolling.isRollingFile("x-20261117.log") == 0)

	// ── File names ───────────────────────────────────────────────────────────

	today = dateTime.str(dateTime.nowVal, "yyyyMMdd")
	h.check("rollingName adds the day stamp", rolling.rollingName == "t-" + today + ".log")
	h.check("rollingName has no stamp for an infinite interval",
		loggerOn(log, dir, 7, {"rollingInterval": "infinite"}).rollingName == "t-.log")
	h.check("rollingPath joins the folder and the name",
		rolling.rollingPath == file.child(dir, rolling.rollingName))

	// ── Directories ──────────────────────────────────────────────────────────

	nested = file.child(file.child(dir, "sub"), "deeper")
	h.check("ensureDirectory makes a nested path",
		log.ensureDirectory(nested) == null and file.exists(nested) == 1)
	h.check("ensureDirectory accepts a path that exists", log.ensureDirectory(nested) == null)

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

	// ── Writing to the file sink ────────────────────────────────────────────

	startDir(dir)
	sink = loggerOn(log, dir, 7, {"file": 1})
	h.check("an event call answers with nothing", sink.info("Hello {Name}", {"Name": "world"}) == null)
	h.check("write creates the rolling file", namesIn(dir) == [sink.rollingName])
	lines = fileLines(file.child(dir, sink.rollingName))
	h.check("the line carries the level and the message",
		lines.len == 1 and lines[0].indexOf("[INF] test: Hello world") != null)
	sink.warning("Second")
	h.check("a second event appends another line",
		fileLines(file.child(dir, sink.rollingName)).len == 2)

	startDir(dir)
	dropped = loggerOn(log, dir, 7, {"file": 1, "minimumLevel": "error"})
	dropped.info("dropped")
	h.check("a level below the minimum writes nothing", namesIn(dir).len == 0)

	// ── Debug and fatal ──────────────────────────────────────────────────────

	startDir(dir)
	verbose = loggerOn(log, dir, 7, {"file": 1, "minimumLevel": "debug"})
	verbose.debug("Debug at {N}", {"N": 1})
	verbose.fatal("Fatal at {N}", {"N": 2})
	written = fileLines(file.child(dir, verbose.rollingName))
	h.check("debug writes a DBG line",
		written.len == 2 and written[0].indexOf("[DBG] test: Debug at 1") != null)
	h.check("fatal writes an FTL line",
		written.len == 2 and written[1].indexOf("[FTL] test: Fatal at 2") != null)

	startDir(dir)
	quiet = loggerOn(log, dir, 7, {"file": 1})
	quiet.debug("dropped")
	h.check("debug sits below the default minimum", namesIn(dir).len == 0)

	// ── Several writers on one file ──────────────────────────────────────────

	startDir(dir)
	first = loggerOn(log, dir, 7, {"file": 1})
	first.info("from A")
	loggerOn(log, dir, 7, {"file": 1}).info("from B")
	loggerOn(log, dir, 7, {"file": 1}).info("from C")
	h.check("three writers to one file keep every line",
		fileLines(file.child(dir, first.rollingName)).len == 3)

	// ── When the sink cannot write ───────────────────────────────────────────

	startDir(dir)
	makeFile(dir, "blocker")
	blocked = file.child(dir, "blocker")
	broken = loggerOn(log, blocked, 7, {"file": 1, "colors": 0})
	h.check("append swallows a failed open",
		broken.append("x") == null and file.exists(broken.rollingPath) == 0)
	h.check("the failure line names the folder and the problem",
		broken.failureLine(err("boom")) == "[ERR] logging: could not write to " + blocked + ": boom")
	h.check("reportFileFailure stays quiet without a console",
		broken.reportFileFailure(err("boom")) == null)

	// ── Removing a file ──────────────────────────────────────────────────────

	startDir(dir)
	makeFile(dir, "stale.log")
	stale = file.child(dir, "stale.log")
	h.check("removeFile deletes the file", log.removeFile(stale) == null and file.exists(stale) == 0)
	h.check("removeFile ignores a file that is gone", log.removeFile(stale) == null)
	clearDir(dir)
end function
