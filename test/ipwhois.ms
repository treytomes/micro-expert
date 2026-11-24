// Cases for the ipwho.is reply classes and the request that reads them: one LocationReply
// holding the address, the flag, the network and the clock the service sent.
//
// The JSON here is hand-written from what the service answers rather than fetched, and the
// fetch cases answer through a client stand-in whose get returns canned JSON, so the suite
// needs no network and no key.

run = function(ipwhois, apiClient, h)
	// One answer, trimmed to the fields these cases read.
	fortWorth = {
		"ip": "2607:fb91:4080:a72e:6fb9:c94a:f32a:7f70",
		"success": 1,
		"type": "IPv6",
		"continent": "North America",
		"continent_code": "NA",
		"country": "United States",
		"country_code": "US",
		"region": "Texas",
		"region_code": "TX",
		"city": "Fort Worth",
		"latitude": 32.7254134,
		"longitude": -97.3208492,
		"is_eu": 0,
		"postal": "76127",
		"calling_code": "1",
		"capital": "Washington D.C.",
		"borders": "CA,MX",
		"flag": {"img": "https://cdn.ipwhois.io/flags/us.svg", "emoji": "🇺🇸",
			"emoji_unicode": "U+1F1FA U+1F1F8"},
		"connection": {"asn": 21928, "org": "T-Mobile USA, Inc.", "isp": "T-Mobile USA, Inc.",
			"domain": "t-mobile.com"},
		"timezone": {"id": "America/Chicago", "abbr": "CST", "is_dst": 0, "offset": -21600,
			"utc": "-06:00"},
	}

	quote = char(34)

	// A client stand-in: the real client's checks, with get answering canned JSON. The
	// functions are copied by name, since reading one out of an iteration pair calls it.
	stubFor = function(json, errorMessage=null)
		fake = {}
		for name in apiClient.indexes
			fake[name] = apiClient[name]
		end for
		fake.canned = json
		fake.cannedError = errorMessage
		// What the client was asked to wait, so a case can see the timeout reach it.
		fake.seenTimeout = null
		fake.get = function(url, timeout=null)
			self.seenTimeout = timeout
			if self.cannedError != null then
				return {"ok": 0, "status": null, "body": "", "json": null, "url": url,
					"error": self.cannedError}
			end if
			return {"ok": 1, "status": 200, "body": "", "json": self.canned, "url": url, "error": null}
		end function
		return fake
	end function

	// ── The place ───────────────────────────────────────────────────────────

	answer = ipwhois.reply(apiClient, fortWorth)
	h.check("an answer is a LocationReply", answer isa ipwhois.LocationReply)
	h.check("and it is ok", answer.ok)
	h.check("it holds the place as the layer's Place", answer.place isa apiClient.Place)
	h.check("whose fields stay as the service sent them", answer.place.raw.latitude == 32.7254134)
	h.check("the address it is about comes with it", answer.ip == fortWorth.ip)
	h.check("the place is known by its city, region and country",
		answer.label == "Fort Worth, Texas, United States")
	h.check("a place with no region is named without one",
		ipwhois.reply(apiClient, {"city": "Berlin", "country": "Germany"}).label == "Berlin, Germany")
	h.check("and a place with nothing to say has no label",
		ipwhois.reply(apiClient, {}).label == "")
	h.check("its coordinates are the latitude then the longitude",
		answer.coordinates == str(32.7254134) + ", " + str(-97.3208492))
	h.check("the numbers themselves are there to send as parameters",
		answer.place.latitude == 32.7254134 and answer.place.longitude == -97.3208492)
	h.check("a field no accessor names is read by the name the service gave it",
		answer.place.text("type") == "IPv6" and answer.place.text("borders") == "CA,MX")

	// ── The network ─────────────────────────────────────────────────────────

	connection = answer.connection
	h.check("the network comes as the layer's Fields", connection isa apiClient.Fields)
	h.check("and its fields are read by the names the service gave them",
		connection.text("isp") == "T-Mobile USA, Inc." and connection.text("domain") == "t-mobile.com")
	h.check("its number is a number, not the text of one", connection.number("asn") == 21928)
	h.check("a reply with no network holds none", ipwhois.reply(apiClient, {"city": "Berlin"}).connection == null)

	// ── The clock ───────────────────────────────────────────────────────────

	clock = answer.timezone
	h.check("the time zone comes as a Fields too", clock isa apiClient.Fields)
	h.check("with its name and its distance from UTC as the reply spelled it",
		clock.text("id") == "America/Chicago" and clock.text("utc") == "-06:00")
	h.check("and that distance in seconds for arithmetic", clock.number("offset") == -21600)

	// ── The flag ────────────────────────────────────────────────────────────

	flag = answer.flag
	h.check("the flag is a Fields as well", flag isa apiClient.Fields)
	h.check("with the picture the service hosts and the emoji",
		flag.text("img") == "https://cdn.ipwhois.io/flags/us.svg" and flag.text("emoji") == "🇺🇸")

	// ── The whole answer, described ─────────────────────────────────────────

	lines = answer.describe
	h.check("describe leads with what the answer is and where",
		lines[0] == answer.label and lines[1] == answer.coordinates)
	h.check("then every field the service sent, one to a line",
		lines.indexOf("postal: 76127") != null and lines.indexOf("is_eu: 0") != null)
	h.check("a nested object's fields sit indented under its name",
		lines.indexOf("flag:") != null and
			lines.indexOf("  img: https://cdn.ipwhois.io/flags/us.svg") != null)
	h.check("a reply with no place has nothing to describe",
		ipwhois.reply(apiClient, {"success": 0, "message": "nope"}).describe.len == 0)

	// ── A reply narrowed by fields ──────────────────────────────────────────
	// fields=city,country sends only those two, so everything else is simply absent.

	narrowed = ipwhois.reply(apiClient, {"success": 1, "city": "Fort Worth", "country": "United States"})
	h.check("a narrowed reply is still a LocationReply", narrowed isa ipwhois.LocationReply)
	h.check("named by the fields it was sent", narrowed.label == "Fort Worth, United States")
	h.check("its coordinates are missing rather than zero",
		narrowed.coordinates == "" and narrowed.place.latitude == null)
	h.check("and the parts it was not sent are absent",
		narrowed.connection == null and narrowed.timezone == null and narrowed.flag == null)

	// ── A refused lookup ────────────────────────────────────────────────────
	// ipwho.is says so in a 200: success false, and the message with it.

	refused = ipwhois.reply(apiClient, {"success": 0, "message": "404 not found"})
	h.check("a refused lookup is not ok", not refused.ok)
	h.check("and carries the service's own message",
		refused.error == "The API refused the lookup: 404 not found")
	h.check("it holds no address to read",
		refused.isEmpty and refused.label == "" and refused.ip == "")
	h.check("a message padded with spaces is trimmed",
		ipwhois.reply(apiClient, {"success": 0, "message": "  Reserved  "}).error == "The API refused the lookup: Reserved")
	h.check("a refusal with no message still says something",
		ipwhois.reply(apiClient, {"success": 0}).error == "The API refused the lookup: no message given.")
	h.check("a reply that is neither an object nor a list is refused",
		ipwhois.reply(apiClient, "not json").error == "The API returned an unexpected reply.")
	h.check("nothing to read is no reply at all", ipwhois.reply(apiClient, null) == null)

	// ── The request ─────────────────────────────────────────────────────────

	lookupSpec = ipwhois.specFor("lookup")
	h.check("the lookup takes the service's two parameters, lang and fields",
		lookupSpec.params.len == 2 and lookupSpec.params[0].name == "lang" and
			lookupSpec.params[1].name == "fields")
	h.check("nothing else is modelled: the one lookup is the whole table", ipwhois.endpoints.len == 1)

	full = ipwhois.fetch(stubFor(fortWorth), "lookup")
	h.check("a lookup is ok and answers a LocationReply",
		full.ok and full.reply isa ipwhois.LocationReply)
	h.check("with nothing to send, its url is the host's root", full.url == "https://ipwho.is/")
	h.check("and its reply reads like the one read by hand", full.reply.label == answer.label)

	// A caller with its own deadline hands it down; one that names none leaves the client's.
	patient = stubFor(fortWorth)
	ipwhois.fetch(patient, "lookup", {}, 3)
	h.check("a lookup hands the client the timeout it was given", patient.seenTimeout == 3)
	relaxed = stubFor(fortWorth)
	ipwhois.fetch(relaxed, "lookup")
	h.check("and leaves the client's own in place when none is named", relaxed.seenTimeout == null)

	narrowRequest = ipwhois.fetch(stubFor({"success": 1, "city": "Fort Worth", "country": "United States"}),
		"lookup", {"fields": "city,country"})
	h.check("a narrowed request sends its fields as a parameter",
		narrowRequest.url.indexOf("https://ipwho.is/?") == 0 and narrowRequest.url.indexOf("fields=") != null)
	h.check("and answers the narrowed reply", narrowRequest.reply.label == "Fort Worth, United States")

	refusedRequest = ipwhois.fetch(stubFor({"success": 0, "message": "Invalid IP address"}), "lookup")
	h.check("a refused lookup is a request that went through", refusedRequest.ok)
	h.check("carrying a reply that did not",
		not refusedRequest.reply.ok and refusedRequest.reply.error == "The API refused the lookup: Invalid IP address")

	invalid = ipwhois.fetch(stubFor(fortWorth), "lookup", {"fields": ""})
	h.check("a value the table refuses never leaves the program",
		not invalid.ok and invalid.error == "Invalid lookup request: fields must not contain an empty value")
	h.check("so there is no url to show", invalid.url == "")
	h.check("an endpoint the table does not name is refused by name",
		ipwhois.fetch(stubFor(fortWorth), "bulk").error == "Unknown endpoint " + quote + "bulk" + quote + ".")
	down = ipwhois.fetch(stubFor(null, "The request failed (curl exit 6): Could not resolve host"), "lookup")
	h.check("a request that never went out has no reply to read", not down.ok and down.reply == null)
end function
