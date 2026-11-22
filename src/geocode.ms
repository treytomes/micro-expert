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
//   ./3rd-party/miniscript-linux/miniscript src/geocode.ms --help
//
// A bare query searches, so the first form and "search "Eiffel Tower"" mean the same thing;
// the other two subcommands name the other two endpoints. The words after the subcommand are
// joined with spaces for a search, and are a latitude and longitude or a list of OSM IDs
// otherwise. Every parameter the endpoints document is an option, with underscores or dashes
// in its name: --limit, --countrycodes, --zoom, --polygon-geojson, and so on. --help lists
// them all - generated from the same table the request is checked against - so a parameter
// that was misspelt is named rather than sent, and a value outside the range the table gives
// never leaves the program.
//
// --json prints the API's own JSON instead of the summary. Errors go to stdout with a
// non-zero exit status: a missing key, nothing to search with, an option the parser cannot
// read, a failed request, or a reply that is not what the endpoint documents. The key is
// never printed - the URL is built and handed to curl, not shown.


import "cli/cli"
import "api/client"
import "api/geocode"
import "api/dotenv"
import "json"

cli = globals["cli/cli"]
client = globals["api/client"]
geo = globals["api/geocode"]
dotenv = globals["api/dotenv"]

scriptName = "geocode.ms"
if shellArgs.len > 0 then scriptName = file.name(shellArgs[0])

version = "1.0.0"


description = function
	"The lines under the command name in --help: which words name which endpoint."
	lines = []
	lines.push "Asks geocode.maps.co about a place, a coordinate or an OSM id."
	lines.push ""
	lines.push "  " + scriptName + " <place or address>                   search"
	lines.push "  " + scriptName + " reverse <latitude> <longitude>       reverse"
	lines.push "  " + scriptName + " lookup <R253832,W175905>             lookup"
	lines.push ""
	lines.push "The words after the endpoint are joined with spaces for a search. Every"
	lines.push "parameter the endpoints document is an option; a boolean is --name,"
	lines.push "--name false or --no-name, and --json prints the API's own JSON."
	return lines.join(char(10))
end function


cmd = cli.newCommand(scriptName, version, description())


refuse = function(message)
	"Reports a mistake and stops, pointing at the generated help."
	print "error: " + message
	print "Run " + cmd.name + " --help for usage."
	exit 1
end function


cli.add(cmd, {
	"name": "json",
	"aliases": ["--json"],
	"type": "flag",
	"description": "Print the API's own JSON instead of the summary.",
})

// The three endpoints' parameters, once each: a name one endpoint takes and another does
// not is still declared, because the words decide where the request goes. Required fields
// are left to the request, since reverse alone needs --lat and --lon.
surface = geo.surface(client)
client.addParameters(cli, cmd, surface, 0)


// ── One result ───────────────────────────────────────────────────────────────

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

if shellArgs.len <= 1 then
	print cli.helpText(cmd)
	exit 1
end if

// cli reads the options; what it leaves over is the endpoint and the words after it.
split = client.splitArguments(cli, shellArgs, cmd, surface)
parsed = cli.parse(cmd, [shellArgs[0]] + split.options)

if parsed.help then
	print cli.helpText(cmd)
	exit 0
end if
if parsed.version then
	print cli.versionLine(cmd)
	exit 0
end if
if not parsed.ok then refuse(parsed.error)

showJson = parsed.values.json
options = client.apiOptions(parsed.values, ["json"])

mode = "search"
rest = split.words
if split.words.len > 0 then
	if ["search", "reverse", "lookup"].indexOf(split.words[0]) != null then
		mode = split.words[0]
		rest = split.words[1:]
	end if
end if

if mode == "search" then
	query = rest.join(" ")
	searchable = query != "" or options.hasIndex("q")
	for field in ["amenity", "street", "city", "county", "state", "country", "postalcode"]
		if options.hasIndex(field) then searchable = 1
	end for
	if not searchable then refuse("a search needs a place or address.")
	if query != "" and not options.hasIndex("q") then options.q = query
else if mode == "reverse" then
	if rest.len >= 2 then
		options.lat = rest[0]
		options.lon = rest[1]
	end if
	if not options.hasIndex("lat") or not options.hasIndex("lon") then refuse("reverse needs a latitude and a longitude.")
else if mode == "lookup" then
	if rest.len > 0 then options.osm_ids = rest.join(",")
	if not options.hasIndex("osm_ids") then refuse("lookup needs at least one OSM ID, such as R253832.")
end if

apiKey = dotenv.find(geo.keyName, shellArgs[0])
if apiKey == null then
	print "error: no " + geo.keyName + " found."
	print "Put it in the .env beside the runner, or export it, then try again."
	exit 1
end if
options.apiKey = apiKey


// ── The reply ────────────────────────────────────────────────────────────────

result = geo.fetch(client, mode, options)
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
	ids = options.osm_ids
	if ids isa list then ids = ids.join(",")
	header = header + " for " + ids
end if
print header + ":"

for i in reply.indexes
	item = reply[i]
	if item isa map then showMatch(item, i + 1)
end for
