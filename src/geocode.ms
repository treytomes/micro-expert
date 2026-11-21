// geocode.ms — asks geocode.maps.co about a place, and prints what comes back.
//
// A standalone program, not part of the session: it reads GEOCODE_MAPS_API_KEY from the
// environment or from the .env beside the runner, asks one of the service's three endpoints,
// and prints the answer.
//
//   ./3rd-party/miniscript-linux/miniscript src/geocode.ms "Eiffel Tower"
//   ./3rd-party/miniscript-linux/miniscript src/geocode.ms Paris, Texas
//   ./3rd-party/miniscript-linux/miniscript src/geocode.ms reverse 48.8584 2.2945
//   ./3rd-party/miniscript-linux/miniscript src/geocode.ms lookup R253832,W175905
//   ./3rd-party/miniscript-linux/miniscript src/geocode.ms --json --limit 3 "Paris, Texas"
//
// A bare query searches, so the first form and "search "Eiffel Tower"" mean the same thing;
// the other two subcommands name the other two endpoints. The arguments after the subcommand
// are joined with spaces for a search, and are a latitude and longitude or a list of OSM IDs
// otherwise. Every other parameter the endpoint documents works as --name value, with
// underscores or dashes: --limit, --countrycodes, --zoom, --polygon-geojson, and so on.
//
// --json prints the API's own JSON instead of the summary. Errors go to stdout with a
// non-zero exit status: a missing key, nothing to search with, a failed request, or a reply
// that is not what the endpoint documents. The key is never printed - the URL is built and
// handed to curl, not shown.


import "api/client"
import "json"

client = globals["api/client"]

scriptName = "geocode.ms"
if shellArgs.len > 0 then scriptName = file.name(shellArgs[0])


usageLine = function
	"One line saying how to run this."
	return "Usage: miniscript " + scriptName + " <place or address>"
end function


usageText = function
	"The whole usage, for a bare run or --help."
	lines = []
	lines.push usageLine
	lines.push "       miniscript " + scriptName + " reverse <latitude> <longitude>"
	lines.push "       miniscript " + scriptName + " lookup <osm ids>"
	lines.push ""
	lines.push "Searches geocode.maps.co and prints each match. A bare query searches; reverse turns"
	lines.push "a coordinate into the nearest address, and lookup takes comma-separated OSM IDs such"
	lines.push "as R253832. Any parameter the endpoint documents works as --name value, spelled with"
	lines.push "dashes or underscores, and --json prints the API's own JSON instead of the summary."
	return lines.join(char(10))
end function


nameOf = function(item)
	"The name a result is known by, whichever field the endpoint used."
	if item.hasIndex("display_name") then
		if item.display_name isa string then return item.display_name
	end if
	if item.hasIndex("localname") then
		if item.localname isa string then return item.localname
	end if
	return "(no name)"
end function


whereOf = function(item)
	"The coordinates a result carries, as the API gave them."
	where = ""
	if item.hasIndex("lat") then
		if item.lat isa string then where = item.lat
	end if
	if item.hasIndex("lon") then
		if item.lon isa string then
			if where != "" then where = where + ", "
			where = where + item.lon
		end if
	end if
	if where == "" then
		// A lookup result carries a GeoJSON point instead, as [longitude, latitude].
		if item.hasIndex("centroid") then
			centroid = item.centroid
			if centroid isa map then
				if centroid.hasIndex("coordinates") then
					if centroid.coordinates isa list then
						if centroid.coordinates.len >= 2 then
							where = str(centroid.coordinates[1]) + ", " + str(centroid.coordinates[0])
						end if
					end if
				end if
			end if
		end if
	end if
	return where
end function


kindOf = function(item)
	"The result's type in parentheses, when it has one."
	if item.hasIndex("type") then
		if item["type"] isa string then return "  (" + item["type"] + ")"
	end if
	return ""
end function


showMatch = function(item, number=null)
	"Prints one result: its name, then its coordinates and type."
	prefix = "  "
	if number != null then prefix = "  " + number + ". "
	print prefix + nameOf(item)
	where = whereOf(item)
	if where != "" then print "     " + where + kindOf(item)
end function


// ── The question ─────────────────────────────────────────────────────────────

arguments = []
if shellArgs.len > 1 then
	for i in range(1, shellArgs.len - 1)
		arguments.push shellArgs[i]
	end for
end if

if arguments.len == 0 then
	print usageText
	exit 1
end if

parsed = client.parseArguments(arguments, ["json", "help"])
if parsed.problems.len > 0 then
	for problem in parsed.problems
		print "error: " + problem
	end for
	exit 1
end if
if parsed.flags.hasIndex("help") then
	print usageText
	exit 0
end if
showJson = parsed.flags.hasIndex("json")
words = parsed.words
options = parsed.options

mode = "search"
rest = words
if words.len > 0 then
	if words[0] == "search" or words[0] == "reverse" or words[0] == "lookup" then
		mode = words[0]
		rest = words[1:]
	end if
end if

if mode == "search" then
	query = rest.join(" ")
	searchable = query != "" or options.hasIndex("q")
	for field in ["amenity", "street", "city", "county", "state", "country", "postalcode"]
		if options.hasIndex(field) then searchable = 1
	end for
	if not searchable then
		print "The place or address cannot be blank."
		print usageLine
		exit 1
	end if
	if query != "" and not options.hasIndex("q") then options.q = query
else if mode == "reverse" then
	if rest.len >= 2 then
		options.lat = rest[0]
		options.lon = rest[1]
	end if
	if not options.hasIndex("lat") or not options.hasIndex("lon") then
		print "reverse needs a latitude and a longitude."
		print usageLine
		exit 1
	end if
else if mode == "lookup" then
	if rest.len > 0 then options.osm_ids = rest.join(",")
	if not options.hasIndex("osm_ids") then
		print "lookup needs at least one OSM ID, such as R253832."
		print usageLine
		exit 1
	end if
end if

apiKey = client.geocodeFindKey
if apiKey == null then
	print "No " + client.geocodeKeyName + " found."
	print "Put it in the .env beside the runner, or export it, then try again."
	exit 1
end if
options.apiKey = apiKey


// ── The reply ────────────────────────────────────────────────────────────────

result = client.geocodeFetch(mode, options)
if not result.ok then
	print result.error
	exit 1
end if

if showJson then
	if result.json != null then
		print json.toJSON(result.json)
	else
		print result.body
	end if
	exit 0
end if

if result.json == null then
	print "The reply was not JSON."
	exit 1
end if

reply = result.json

if reply isa map then
	if reply.hasIndex("error") then
		print "The API refused the request: " + reply.error
		exit 1
	end if
	// /reverse answers with one object rather than a list of matches.
	showMatch(reply)
	exit 0
end if

if not (reply isa list) then
	print "The API returned an unexpected reply."
	exit 1
end if

if reply.len == 0 then
	if mode == "search" and options.hasIndex("q") then
		print "No matches for " + char(34) + options.q + char(34) + "."
	else
		print "No matches."
	end if
	exit 0
end if

header = reply.len + " result" + "s" * (reply.len != 1)
if mode == "search" then
	if options.hasIndex("q") then header = header + " for " + char(34) + options.q + char(34)
else if mode == "lookup" then
	header = header + " for " + options.osm_ids
end if
print header + ":"

for i in reply.indexes
	item = reply[i]
	if item isa map then showMatch(item, i + 1)
end for
