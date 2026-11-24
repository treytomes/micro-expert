# The ipwho.is API surface

ipwho.is reads an IP address to where it is: the country, region and city that address is
registered to, the coordinates of that city, and the network, clock and flag that go with it.
`src/api/ipwhois.ms` holds the one endpoint the layer models - the lookup of the session's own
address - with the two parameters it takes. There is no program of its own for this service;
`src/spike/session.ms` is the caller, asking it where the session is.

This document is the remote surface written out: what a request looks like, what comes back, the
classes that reply is read into, the facts written from them, and the endpoint with its parameters.
What is missing between those facts and a usable domain is collected with the other services' in
[gaps to close before these APIs are knowledge](gaps.md).

## The request

```
GET https://ipwho.is/?lang=en&fields=city,region,country
```

- The path is the host's root: there is one lookup, and no endpoint name to choose. It answers
  for the address the request came from, so nothing in the URL says which address is asked about.
- There is no key. The free service counts requests by address rather than by key, which is why
  the layer has no credential to read, no `.env` to load and no key to keep out of a printed URL.
- The keyed parts of the service are left out rather than half-answered: `/bulk` and the
  `security` fields belong to a paid account, so the table holds neither.
- `lang` and `fields` are the only two query parameters, and both are optional. The layer
  URL-encodes values, drops empty ones, and joins a repeated `--name` with commas, so
  `--fields city --fields country` becomes `fields=city%2Ccountry`.
- A value the table cannot use never leaves the program: an empty `fields` is refused as
  `fields must not contain an empty value`, and a name the table does not hold is refused by that
  name, both before a request is made.

## The reply

The answer is one JSON object, and it is the same object whatever the address: no list, no
envelope with a status in it. Trimmed to the fields this layer reads, it looks like this:

```json
{
  "ip": "2607:fb91:4080:a72e:6fb9:c94a:f32a:7f70",
  "success": true,
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
  "flag": {"img": "https://cdn.ipwhois.io/flags/us.svg", "emoji": "🇺🇸", "emoji_unicode": "U+1F1FA U+1F1F8"},
  "connection": {"asn": 21928, "org": "T-Mobile USA, Inc.", "isp": "T-Mobile USA, Inc.", "domain": "t-mobile.com"},
  "timezone": {"id": "America/Chicago", "abbr": "CST", "is_dst": 0, "offset": -21600, "utc": "-06:00"}
}
```

| Field | Meaning |
| --- | --- |
| `ip` | The address the answer is about: the one the request came from. |
| `success` | Whether the lookup was answered: `true`, or `1`, when it was. A refusal is still a 200. |
| `type` | `IPv4` or `IPv6`, the address family. |
| `continent`, `continent_code` | The continent, by name and by code. |
| `country`, `country_code` | The country, by name and by ISO 3166-1 alpha-2 code. |
| `region`, `region_code` | The first-level administrative division and its code, such as `Texas` and `TX`. |
| `city` | The city the address is registered to. |
| `latitude`, `longitude` | The city's coordinates, as numbers rather than strings. |
| `is_eu` | `1` when the country is in the European Union, `0` when it is not. |
| `postal` | The postal code of the city. |
| `calling_code` | The country's international dialling code, as text. |
| `capital` | The country's capital. |
| `borders` | The countries it borders, comma-separated in one text field (`CA,MX`). |
| `flag` | An object: `img` the picture the service hosts, `emoji` the flag as one, `emoji_unicode` its code points. |
| `connection` | An object: `asn` the autonomous system number, `org` the owning organization, `isp` the provider as the service names it, `domain` its domain. |
| `timezone` | An object: `id` the IANA zone, `abbr` its abbreviation, `is_dst` daylight saving, `offset` seconds from UTC, `utc` that offset as text. |

Anything else the service sends stays in the reply as it came and is printed by `describe`;
nothing is dropped on the way in, so a field added between releases is readable by name without a
change to the layer.

`fields` is how a reply is made narrower: `fields=city,country` sends only those two, and every
class then answers for what was sent and for nothing else - a coordinate that was not asked for is
`null`, not zero, and a part that was not sent is absent rather than empty.

## The reply as classes

`fetch` hands the parsed JSON through untouched and puts a second field beside it: `reply`, the
same answer read as classes. `src/api/ipwhois.ms` defines only what holds them together; the
objects themselves are the API layer's, from `src/api/client.ms`.

**`Place`: the shared class.** The answer as a whole is a place, so it is the layer's shared
`Place`, built with `["city"]` as the name and `["region", "country"]` after it. That is what
gives a lookup its label - `Fort Worth, Texas, United States` - and a place with no region is
named without one (`Berlin, Germany`), while a place with nothing to say has no label at all, which
is the empty text the program turns into `(no name)`. Coordinates come from the reply's
`latitude` and `longitude` numbers; `latitude` and `longitude` return those numbers, ready to send
as parameters. Every other field is read by the name the service gave it - `place.text("type")` for
`IPv6`, `place.text("borders")` for `CA,MX`, `place.number("is_eu")` for `0` - so no field needs an
accessor of its own. `place.describe` prints every field one to a line, with a nested object's
fields indented under its name, and `place.raw` is the map exactly as it arrived.

**`Fields`: the three objects inside.** The flag, the network and the clock are objects of the
service's own fields and nothing more, so each is a plain `Fields` rather than a class per shape:
`fields.text("isp")`, `fields.number("asn")`, `fields.text("utc")`, `fields.number("offset")`,
`fields.text("img")`, `fields.text("emoji")`. A part the reply does not carry is `null`.

**`LocationReply`: the answer.** It holds the place and the three parts - `place`, `connection`,
`timezone`, `flag` - and answers the questions a caller asks of the whole thing:

| Member | Meaning |
| --- | --- |
| `ok`, `error` | Whether the lookup was answered, and why not when it was refused. |
| `place`, `connection`, `timezone`, `flag` | The shared `Place` and the three `Fields`, or `null` where the reply had none. |
| `ip` | The address the answer is about; empty when the reply named none. |
| `label` | What the address is known by, as its place names it. |
| `coordinates` | The latitude and longitude, one line; empty when the reply gave none. |
| `isEmpty` | True when there is no address to describe - a refusal, or an empty reply. |
| `describe` | The whole answer as lines: label, coordinates, a blank line, then every field. |

### Refusals

ipwho.is reports a refusal as a **200 with `success: false`** rather than as an HTTP error, so the
request succeeds and the reply does not:

```json
{"success": false, "message": "404 not found"}
```

The layer reads that into `ok: 0` and an `error` of `The API refused the lookup: 404 not found`,
with the service's message trimmed of surrounding spaces. A refusal with no message says
`no message given.`; a body that is not an object at all is `The API returned an unexpected
reply.`; and no JSON to read is no reply at all, `reply` being `null`. All of them are values a
program reports rather than renders - `describe` on a refusal is empty, because there is no
address to lay out.

A request that never went out is a different thing: a host that will not resolve, or curl timing
out, fails the transport instead, and then `ok` is `0` on the result, `error` carries the
transport's own words, and `reply` is `null`.

## The reply as facts

`src/spike/session.ms` writes the answer as facts about the session: the session holds the place it
is in, and the place holds what the answer says about it.

```prolog
has-location(session, fort-worth)
has-continent(fort-worth, North America)
has-country(fort-worth, United States)
has-region(fort-worth, Texas)
has-city(fort-worth, Fort Worth)
has-latitude(fort-worth, 32.725413)
has-longitude(fort-worth, -97.320849)
```

`session` is the run's own subject, the way `env` is the interpreter's: it is one term from one run
to the next, so a file of these facts can be added to rather than replaced, and a question about the
session reads without naming a machine that will be somewhere else tomorrow. The place is a subject
of its own because it is not the session: `fort-worth` is the city the address resolves to, and a
geocoder result or a second session that reaches the same city can name the same term, which is
what lets their facts meet.

The term is the service's `city` in lower case with its spaces joined by dashes. It is chosen
rather than derived - a lookup carries no id - which is why the answer's own city is repeated as
`has-city`. A field the reply did not carry writes no fact, so a `fields=city,country` lookup is
three lines rather than seven, and a refused lookup writes none at all: the program prints the
refusal instead.

Four of the spellings are the other two pages' own - `has-city`, `has-country`, `has-latitude`,
`has-longitude` - written here exactly as they are there, with the same field types, so one schema
line and one rule cover a place whichever service supplied it. `has-continent`, `has-region` and
`has-location` are this page's. The coordinates are numbers here, where the geocoder's reply writes
its two as text: `has-latitude(fort-worth, 32.725413)` compares, `has-latitude(way/5013364,
"48.8582599")` does not.

Nothing yet writes these lines to a file: they are printed, and pasting them into a domain is a
person's step rather than a program's.

## Endpoints

### `lookup`

```
GET https://ipwho.is/
```

The caller's own address: where this session reaches the network from. The coordinates it answers
with are the city's, so they say which city the session appears in rather than which room it sits
in.

| Parameter | Type | Notes |
| --- | --- | --- |
| `lang` | text | Language the words come back in, such as `en` or `de`. |
| `fields` | csv | Only these fields, comma-separated. An empty value is refused before the request. |

The reply is the one object described above - not a list, and not wrapped in anything. The layer
knows the two parameter names and their types, not the service's field names, so `fields` is
passed through as given: a name the service does not know is its own to answer, and the classes
read whatever came back.

## How a program calls it

There is no command-line program for this service: `src/where.ms` runs the location spike,
`src/spike/session.ms`, which asks for the session's location and prints it as the facts above. The
module imports nothing and reads no globals - an imported module's imports belong to the entry
script, and so does its globals - so the host in `src/` loads the maps and hands them in:

```
api = globals["api/client"]
ipwhois = globals["api/ipwhois"]
where = session.getCurrentLocation(api, ipwhois)
where.city                        Fort Worth
where.latitude                    32.725413
session.generateLocationFacts(globals["triples"], where)    the facts above
```

A program doing the lookup itself reads the same layer by hand - `ipwhois.fetch(api, "lookup",
{"fields": "city,country"})` - and finds the shared `Place` at `result.reply.place`, the request
at `result.url` and the service's own answer at `result.json`.

`result` is the transport's map - `ok`, `status`, `body`, `json`, `url`, `error` - with `reply`
beside them, so a program that wants the service's own JSON still has it. `fetch` takes the
endpoint name first and refuses one the table does not name by that name
(`Unknown endpoint "bulk".`), so a misspelling is reported rather than requested.

A program with a command line of its own declares this endpoint's parameters from the same table
the request is checked against - `api.addParameters(cli, cmd, ipwhois.specFor("lookup"))` - so
`--help` lists `lang` and `fields` with what each takes, and a parameter the table does not hold is
refused before anything is sent.
