// dotenv.ms — KEY=value settings from the environment and from the .env beside a runner.
//
// A program imports this file and passes what it finds into a request, because this
// interpreter discards the imports of an imported module, and api/client.ms is itself
// imported by the programs. Nothing here touches the network, and nothing here knows what
// any setting means.
//
//   dotenv = globals["dotenv"]
//   key = dotenv.find("GEOCODE_MAPS_API_KEY", shellArgs[0])
//
// The environment wins over a file, so one run can be pointed elsewhere without editing the
// .env, and an empty value counts as absent either way.


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
		if line.len > 0 then
			if line[-1] == char(13) then line = line[0:line.len - 1]
		end if
		line = line.trim
		if line.len == 0 then continue
		if line[0] == "#" then continue
		parts = line.split("=", 2)
		if parts.len < 2 then continue
		settingName = parts[0].trim
		if settingName.len > 0 then values[settingName] = stripQuotes(parts[1].trim)
	end for
	return values
end function


find = function(settingName, scriptPath="")
	"A setting from the environment first, then from the nearest .env; null when absent."
	if env.hasIndex(settingName) then
		value = env[settingName].trim
		if value != "" then return value
	end if
	// The runner lives beside its .env, so a script named by a path finds it one level up.
	// The working folder is tried as well, for a script named from where it stands.
	paths = [".env"]
	hasFolder = scriptPath.indexOf("/") != null
	if not hasFolder then hasFolder = scriptPath.indexOf(char(92)) != null
	if hasFolder then paths.push(file.child(file.parent(scriptPath), "..") + "/.env")
	paths.push("../.env")
	for path in paths
		values = read(path)
		if values.hasIndex(settingName) then
			value = values[settingName].trim
			if value != "" then return value
		end if
	end for
	return null
end function
