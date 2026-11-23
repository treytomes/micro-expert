// dotenv.ms — KEY=value settings from the environment and from the .env beside a runner.
//
// A program imports this file and passes what it finds into a request, because this
// interpreter discards the imports of an imported module, and api/client.ms is itself
// imported by the programs. Nothing here touches the network, and nothing here knows what
// any setting means.
//
//   dotenv = globals["dotenv"]
//   dotenv.load()                                // one .env file, once, into `env`
//   key = dotenv.find("GEOCODE_MAPS_API_KEY", shellArgs[0])
//
// A load copies whole settings into the interpreter's own `env` map. That map is changed,
// never replaced, so the entries it starts with and its link to a child process's
// environment survive. The environment wins over a file, so one run can be pointed
// elsewhere without editing the .env, and an empty value counts as absent either way.
// find loads the .env files a runner can see before it looks, so a caller that asks for one
// setting still gets each file read once.


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


// The files loaded so far, so each is read once: a later load of one changes nothing.
loaded = {}


load = function(path=".env")
	"Puts one .env's settings into env, once, keeping any the environment has; how many added."
	if loaded.hasIndex(path) then return 0
	loaded[path] = 1
	added = 0
	for kv in read(path)
		// An empty value is absent, the way find reads one, and a setting the environment
		// already holds is the run's own. Neither is copied into env.
		if kv.value == "" then continue
		if env.hasIndex(kv.key) then
			if trimSpace(env[kv.key]) != "" then continue
		end if
		env[kv.key] = kv.value
		added = added + 1
	end for
	return added
end function


pathsFor = function(scriptPath="")
	"The .env files a run can see, in the order a setting is looked for in them."
	// The runner lives beside its .env, so a script named by a path finds it one level up.
	// The working folder is tried as well, for a script named from where it stands.
	paths = [".env"]
	hasFolder = scriptPath.indexOf("/") != null
	if not hasFolder then hasFolder = scriptPath.indexOf(char(92)) != null
	if hasFolder then paths.push(file.child(file.parent(scriptPath), "..") + "/.env")
	paths.push("../.env")
	return paths
end function


find = function(settingName, scriptPath="")
	"A setting from the environment first, then from the nearest .env; null when absent."
	for path in pathsFor(scriptPath)
		load(path)
	end for
	if env.hasIndex(settingName) then
		value = trimSpace(env[settingName])
		if value != "" then return value
	end if
	return null
end function
