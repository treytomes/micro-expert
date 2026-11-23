// dotenv.ms — the .env beside a runner, put into the interpreter's own env map.
//
// Importing this file is the whole of it. From then on a setting is an environment
// variable, and a program reads it from `env` like one the run was started with:
//
//   import "dotenv"
//   key = env["GEOCODE_MAPS_API_KEY"]
//
// `env` is changed, never replaced, so the entries it starts with and its link to a child
// process's environment survive. The environment wins over the file, so one run can be
// pointed elsewhere without editing the .env, and an empty value counts as absent.


blank = char(32) + char(9) + char(13) + char(10)


trimSpace = function(text)
	"text without the whitespace at either end, which is what a .env line can carry."
	start = 0
	stop = text.len
	while start < stop
		if blank.indexOf(text[start]) == null then break
		start = start + 1
	end while
	while stop > start
		if blank.indexOf(text[stop - 1]) == null then break
		stop = stop - 1
	end while
	return text[start:stop]
end function


stripQuotes = function(value)
	"Removes one pair of matching quotes from a value."
	if value.len >= 2 then
		mark = value[0]
		if mark == char(34) then
			if value[-1] == char(34) then return value[1:value.len - 1]
		else if mark == char(39) then
			if value[-1] == char(39) then return value[1:value.len - 1]
		end if
	end if
	return value
end function


read = function(path)
	"Reads a .env's KEY=value lines; a missing or unreadable file is an empty map."
	lines = file.readLines(path)
	if lines isa error then return {}
	values = {}
	for line in lines
		line = trimSpace(line)
		if line.len == 0 then continue
		if line[0] == "#" then continue
		// A hand-written env file may spell a line the way a shell does: `export KEY=value`.
		if line[:6] == "export" and blank.indexOf(line[6:7]) != null then line = trimSpace(line[6:])
		parts = line.split("=", 2)
		if parts.len < 2 then continue
		settingName = trimSpace(parts[0])
		if settingName.len > 0 then values[settingName] = stripQuotes(trimSpace(parts[1]))
	end for
	return values
end function


load = function(path=".env")
	"Puts one .env's settings into env, keeping any the environment already holds."
	for kv in read(path)
		// An empty value is absent, and a setting the environment already holds is the
		// run's own. Neither is copied into env.
		if kv.value == "" then continue
		if env.hasIndex(kv.key) then
			if trimSpace(env[kv.key]) != "" then continue
		end if
		env[kv.key] = kv.value
	end for
end function


// The .env beside the runner: a script named by a path runs one folder inside the
// repository, so its .env is one level up, and a script named from where it stands keeps
// the working folder's.
dotenvPath = ".env"
if shellArgs.len > 0 then
	runnerPath = shellArgs[0]
	if runnerPath.indexOf("/") != null or runnerPath.indexOf(char(92)) != null then
		dotenvPath = file.child(file.parent(runnerPath), "..") + "/.env"
	end if
end if
load(dotenvPath)
