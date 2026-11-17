// logging.ms — console and rolling-file logging, modelled on Serilog.
//
// Mirrors the setup used by NLP.REPL (Program.cs): a console sink writing to
// stdout and a file sink writing to logs/app-YYYYMMDD.log that rolls daily,
// keeps the last seven files, and is shared by concurrent processes.
//
//   import "logging"
//   log = logging.newLogger({"name": "micro-expert"})
//   log.info("{App} starting", {"App": "micro-expert"})
//   log.warning("Low confidence: {Confidence}", {"Confidence": 0.3})
//
// Levels are Serilog's: Debug, Information, Warning, Error, Fatal. Events
// below the logger's minimum level are dropped. Message templates take
// {Name} holes filled from a properties map; a hole with no matching property
// is left in the output as written.
//
// Console lines color the level tag (via the bundled vt module): grey for
// Debug, plain for Information, yellow for Warning, red for Error, bold red
// for Fatal. Set colors to 0 (or the NO_COLOR environment variable) when
// stdout is redirected, so escape codes stay out of the data.
//
// newLogger options (all optional):
//   name               logger name shown in each line      ("app")
//   minimumLevel       level name or rank to start at      ("information")
//   console            1 to write to stdout                (1)
//   colors             1 for ANSI-colored level tags       (1)
//   file               1 to write to the rolling file      (1)
//   path               folder for the log files            ("logs")
//   fileName           base file name                      ("app-.log")
//   rollingInterval    infinite|year|month|day|hour|minute ("day")
//   retainedFileCount  files kept when rolling; 0 keeps all (7)

import "dateTime"
import "vt"

// ── Levels ───────────────────────────────────────────────────────────────────

levels = ["Debug", "Information", "Warning", "Error", "Fatal"]
abbreviations = ["DBG", "INF", "WRN", "ERR", "FTL"]
ranks = {"debug": 0, "information": 1, "warning": 2, "error": 3, "fatal": 4}

// Console color for each level's tag; null leaves the terminal default.
levelColors = [vt.color.gray, null, vt.color.yellow, vt.color.red, vt.color.red]

// RollingInterval -> the dateTime format appended to the file name.
intervalFormats = {
	"infinite": "",
	"none": "",
	"year": "yyyy",
	"month": "yyyyMM",
	"day": "yyyyMMdd",
	"hour": "yyyyMMddHH",
	"minute": "yyyyMMddHHmm",
}

levelRank = function(name)
	"Returns a level's numeric rank, or null when the name is unknown."
	if name == null then return null
	if name isa number then return name
	key = str(name).lower
	if ranks.hasIndex(key) then return ranks[key]
	return null
end function

// ── Construction ─────────────────────────────────────────────────────────────

newLogger = function(options=null)
	"Builds a logger with a console sink and a rolling file sink."
	settings = {
		"name": "app",
		"minimumLevel": "information",
		"console": 1,
		"colors": 1,
		"file": 1,
		"path": "logs",
		"fileName": "app-.log",
		"rollingInterval": "day",
		"retainedFileCount": 7,
	}
	if options != null then settings = settings + options

	logger = new Logger
	logger.name = str(settings.name)
	logger.minimumLevel = levelRank(settings.minimumLevel)
	if logger.minimumLevel == null then logger.minimumLevel = ranks["information"]
	logger.console = settings.console
	logger.colors = settings.colors
	// The NO_COLOR convention (https://no-color.org) wins over the option.
	if env.hasIndex("NO_COLOR") then logger.colors = 0
	logger.file = settings.file
	logger.directory = str(settings.path)
	logger.retainedFileCount = settings.retainedFileCount

	// "app-.log" rolls to "app-20261116.log", as Serilog does.
	prefix = str(settings.fileName)
	if prefix.len >= 4 then
		if prefix[-4:].lower == ".log" then prefix = prefix[:-4]
	end if
	logger.filePrefix = prefix

	interval = str(settings.rollingInterval).lower
	if intervalFormats.hasIndex(interval) then
		logger.intervalFormat = intervalFormats[interval]
	else
		logger.intervalFormat = intervalFormats["day"]
	end if

	logger.prune
	return logger
end function

// ── Logger ───────────────────────────────────────────────────────────────────

Logger = {}

Logger.debug = function(template, properties=null)
	return self.write("Debug", template, properties)
end function

Logger.info = function(template, properties=null)
	return self.write("Information", template, properties)
end function

Logger.warning = function(template, properties=null)
	return self.write("Warning", template, properties)
end function

Logger.error = function(template, properties=null)
	return self.write("Error", template, properties)
end function

Logger.fatal = function(template, properties=null)
	return self.write("Fatal", template, properties)
end function

Logger.setMinimumLevel = function(name)
	"Changes the minimum level, by name (""debug"" … ""fatal"") or rank."
	rank = levelRank(name)
	if rank == null then return err("unknown log level: " + name)
	self.minimumLevel = rank
	return null
end function

Logger.isEnabled = function(name)
	"True when an event at this level would be written."
	rank = levelRank(name)
	if rank == null then rank = ranks["information"]
	return rank >= self.minimumLevel
end function

Logger.levelTag = function(rank)
	"Level abbreviation, colored for the console when colors are on."
	label = abbreviations[rank]
	if not self.colors then return label
	index = levelColors[rank]
	if index == null then return label
	if rank == ranks["fatal"] then return vt.bold + vt.textColor(index) + label + vt.normal
	return vt.textColor(index) + label + vt.normal
end function

Logger.write = function(level, template, properties=null)
	"Writes one event to every sink that is enabled."
	rank = levelRank(level)
	if rank == null then rank = ranks["information"]
	if rank < self.minimumLevel then return null

	message = render(str(template), properties)
	subject = self.name + ": " + message
	if self.console then
		// Serilog's console template is [{Timestamp:HH:mm:ss} {Level:u3}].
		stamp = dateTime.str(dateTime.nowVal, "HH:mm:ss")
		if self.colors then stamp = vt.textColor(vt.color.gray) + stamp + vt.normal
		print "[" + stamp + " " + self.levelTag(rank) + "] " + subject
	end if
	if self.file then self.append(dateTime.now + " [" + abbreviations[rank] + "] " + subject)
	return null
end function

Logger.append = function(line)
	"Appends one line to the current rolling file, creating the folder first."
	problem = ensureDirectory(self.directory)
	if problem isa error then return self.reportFileFailure(problem)
	handle = file.open(self.rollingPath, "a")
	if handle isa error then return self.reportFileFailure(handle)
	handle.writeLine(line)
	handle.close
	return null
end function

Logger.reportFileFailure = function(problem)
	"Falls back to the console when the log file cannot be written."
	if self.console then print self.failureLine(problem)
	return null
end function

Logger.failureLine = function(problem)
	"The console line explaining why the sink could not write."
	return "[" + self.levelTag(ranks["error"]) + "] logging: could not write to " + self.directory + ": " + problem.message
end function

Logger.rollingName = function
	"Name of the file the current event belongs in."
	suffix = ""
	if self.intervalFormat != "" then suffix = dateTime.str(dateTime.nowVal, self.intervalFormat)
	return self.filePrefix + suffix + ".log"
end function

Logger.rollingPath = function
	"Path of the file the current event belongs in."
	return file.child(self.directory, self.rollingName)
end function

Logger.prune = function
	"Drops the oldest rolling files beyond retainedFileCount."
	if self.intervalFormat == "" then return null
	if self.retainedFileCount <= 0 then return null
	names = file.children(self.directory)
	if names isa error then return null
	current = self.rollingName
	rolling = self.rollingFiles(names, current)
	rolling.sort
	self.dropOldest(rolling, current)
	return null
end function

Logger.rollingFiles = function(names, current)
	"This logger's files among names, counting the current one even before it exists."
	if names.len == 0 then return [current]
	rest = self.rollingFiles(names[1:], current)
	if self.isRollingFile(names[0]) and names[0] != current then return [names[0]] + rest
	return rest
end function

Logger.dropOldest = function(names, current)
	"Deletes the oldest files beyond the retained count, sparing the current one."
	if names.len <= self.retainedFileCount then return null
	if names[0] != current then removeFile(file.child(self.directory, names[0]))
	return self.dropOldest(names[1:], current)
end function

Logger.isRollingFile = function(name)
	"True for file names this logger rolls: prefix + date stamp + .log."
	if name.len != self.filePrefix.len + self.intervalFormat.len + 4 then return 0
	if name[:self.filePrefix.len] != self.filePrefix then return 0
	if name[-4:].lower != ".log" then return 0
	stamp = name[self.filePrefix.len:-4]
	for c in stamp
		if "0123456789".indexOf(c) == null then return 0
	end for
	return 1
end function

// ── Helpers ──────────────────────────────────────────────────────────────────

render = function(template, properties)
	"Substitutes {Name} holes in a message template from a properties map."
	if properties == null then return template
	if template.indexOf("{") == null then return template

	parts = []
	pos = 0
	while pos < template.len
		// indexOf's optional start is exclusive, so search a slice and offset.
		at = template[pos:].indexOf("{")
		if at == null then break
		at = at + pos
		stop = template[at + 1:].indexOf("}")
		if stop == null then break
		stop = stop + at + 1
		token = holeName(template[at + 1:stop])
		if token.len > 0 and properties.hasIndex(token) then
			parts.push template[pos:at]
			parts.push formatValue(properties[token])
			pos = stop + 1
		else
			parts.push template[pos:at + 1]
			pos = at + 1
		end if
	end while
	parts.push template[pos:]
	return parts.join("")
end function

holeName = function(text)
	"Strips Serilog's format clause and @/$ sigils from a hole: {@X:l} -> X."
	colon = text.indexOf(":")
	if colon != null then text = text[:colon]
	if text.len > 0 then
		if text[0] == "@" then text = text[1:]
	end if
	if text.len > 0 then
		if text[0] == "$" then text = text[1:]
	end if
	return text
end function

formatValue = function(value)
	"Renders a property the way a log line expects it."
	if value isa string then return value
	if value == null then return "null"
	return str(value)
end function

ensureDirectory = function(path)
	"Makes path and any missing parents, like Directory.CreateDirectory."
	// file.parent hands back parents ending in a separator, and a folder written that way
	// reads as its own parent, which would stop the recursion below one level short.
	if path.len > 1 then
		last = path[-1]
		if last == char(92) or last == "/" then return ensureDirectory(path[:-1])
	end if
	if file.exists(path) then return null
	parent = file.parent(path)
	if parent != null then
		if parent != "" and parent != path then
			problem = ensureDirectory(parent)
			if problem isa error then return problem
		end if
	end if
	problem = file.makedir(path)
	if problem isa error then return problem
	return null
end function

removeFile = function(path)
	"Deletes a file, ignoring the error value when it cannot be removed."
	result = file.delete(path)
	return null
end function
