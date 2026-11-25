# The ipwho.is API surface

ipwho.is reads an IP address to where it is: the country, region and city that address is
registered to, the coordinates of that city, and the network, clock and flag that go with it.
`src/services/ipwhois_map.ms` holds the one endpoint the writer models - the lookup of the session's
own address - with the two parameters it takes and the facts a reply becomes. There is no program
of its own for this service; `src/location.ms` is the caller, asking it where the session is.

This document is the remote surface written out: what a request looks like, what comes back, the
facts the map writes from it, and the endpoint with its parameters.
What is missing between those facts and a usable domain is collected with the other services' in
[gaps to close before these APIs are knowledge](gaps.md).

## The request

```
GET https://ipwho.is/?lang=en&fields=city,region,country
```

- The path is the host's root: there is one lookup, and no endpoint name to choose. It answers
  for the address the request came from, so nothing in the URL says which address is asked about.
- There is no key. The free service counts requests by address rather than by key, which is why
  the layer has no credential to read, no `.env` to load and no key to keep out of a request's URL.
- The keyed parts of the service are left out rather than half-answered: `/bulk` and the
  `security` fields belong to a paid account, so the table holds neither.
- `lang` and `fields` are the only two query parameters, and both are optional. The layer
  URL-encodes values, drops empty ones, and joins a repeated `--name` with commas, so
  `--fields city --fields country` becomes `fields=city%2Ccountry`.
- A value the table cannot use never reaches a request: an empty `fields` is refused as
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

Anything else the service sends stays in the reply as it came; nothing is dropped on the way in,
so a field added between releases is readable by path without a change to the map.

`fields` is how a reply is made narrower: `fields=city,country` sends only those two, and the map
then writes facts for what was sent and nothing else - a coordinate that was not asked for is
absent rather than zero, and a part that was not sent is absent rather than empty.

## The reply as facts

`src/services/declared.ms` reads the parsed JSON through the map: the reply says when the service
refused (`success` false), which fields identify the place (`city`, `region`, `country` hashed to
`place-...`), and one fact per line. The label is `city, region, country`; the coordinates stay
the numbers the reply sent. Every other field is read by the name the service gave it, so no field
needs an accessor of its own.

**The three objects inside.** The flag, the network and the clock are objects of the service's
own fields and nothing more; the map reads a field by its path when it wants one, and the facts
above need none of them. A part the reply does not carry is absent.

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
caller reports rather than renders; a refusal has no address to lay out.

A request that never went out is a different thing: a host that will not resolve, or curl timing
out, fails the transport instead, and then `ok` is `0` on the result, `error` carries the
transport's own words, and `reply` is `null`.

## The reply as facts

`src/location.ms` writes the answer as facts about the session: the session holds the place it
is in, and the place holds what the answer says about it.

```prolog
has-location(session, place-f1d6b283a52a28dc)
has-continent(place-f1d6b283a52a28dc, North America)
has-country(place-f1d6b283a52a28dc, United States)
has-region(place-f1d6b283a52a28dc, Texas)
has-city(place-f1d6b283a52a28dc, Fort Worth)
has-latitude(place-f1d6b283a52a28dc, 32.725413)
has-longitude(place-f1d6b283a52a28dc, -97.320849)
has-utc-offset(session, -21600)
```

`session` is the run's own subject, the way `env` is the interpreter's: it is one term from one run
to the next, so a file of these facts can be added to rather than replaced, and a question about the
session reads without naming a machine that will be somewhere else tomorrow. The place is a subject
of its own because it is not the session, and its term is generated rather than chosen: a lookup
carries no id, so `src/uid.ms` hashes the three fields that say which place is meant - city, region
and country - into `place-f1d6b283a52a28dc`, the kind, a dash and sixty-four bits of hex. A
geocoder result or a second session that reaches the same city generates the same term, which is
what lets their facts meet.

Hashing rather than minting is the property that matters: the term is the same one on the next run
and on another machine with no store to look it up in, so today's facts and next month's land on one
subject. A minted id - a UUID drawn from randomness - would be unique and useless here, because
nothing would recognize the same city tomorrow and every run would write a second copy of every
fact. `has-city` keeps the words the id was made from, and what the place is comes from a rule
rather than a fact: `data/rules.kb` concludes `is-a(?x, location)` from the two coordinates, so
any term that has them is a place without a line saying so.

What the id cannot do is see that two spellings are one place: `Fort Worth, TX` and `Fort Worth,
Texas` hash differently, which is why the identity is the service's own three fields rather than
anything built from them. Case and spacing are not spelling, so either way of writing them is one
term. A field the reply did not carry writes no fact, and a reply with no city or no coordinates
writes none at all: the region and country alone would name every town in a country, and a refused
lookup writes no facts and reports its refusal.

The last line is the machine's own clock rather than the place's: how far it stands from UTC, which
is what another place's clock is read against when the machine is not there. Like any reading it is
good for the day it was answered: a day-old offset is not a clock, and the lookup is made again. It hangs off `session`
because it is the machine's, and `data/schema.kb` does not name it - an unnamed predicate is
accepted as written.

Four of the spellings are the other two pages' own - `has-city`, `has-country`, `has-latitude`,
`has-longitude` - written here exactly as they are there, with the same field types, so one schema
line and one rule cover a place whichever service supplied it. `has-continent`, `has-region` and
`has-location` are this page's. `data/schema.kb` types all seven place predicates - the names as
text, the coordinates as numbers - and `is-a` as the two terms its rule writes. The
coordinates are numbers here, where the geocoder's reply writes its two as text:
`has-latitude(place-f1d6b283a52a28dc, 32.725413)` compares,
`has-latitude(way/5013364, "48.8582599")` does not, and the schema line says so by refusing the
geocoder's spelling of a coordinate.

Nothing writes these lines to a file on its own: `src/where.ms` prints them, and a session holds
them once a question has asked for them, where `/save-facts` writes them with the rest of what the
session holds. A run that loads them again finds the saved ones already there and adds nothing
twice.

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

The reply is the one object described above - not a list, and not wrapped in anything. The client
knows the two parameter names and their types, not the service's field names, so `fields` is
passed through as given: a name the service does not know is its own to answer, and the map
reads whatever came back.

## How a host calls it

There is no command-line program for this service: `src/where.ms` runs `src/location.ms`, which asks
for the session's location and prints it as the facts above. `location.ms` imports nothing and
reads no globals - an imported module's imports belong to the entry script, and so does its
globals - so the host in `src/` loads the maps and hands them in:

```
api = globals["api/client"]
declared = globals["services/declared"]
decl = globals["services/ipwhois_map"].build()
location = globals["location"]
where = location.sessionFacts(globals["triples"], globals["uid"], api, declared, decl)
where.facts[0].text               has-location(session, place-f1d6b283a52a28dc)
```

The session at the prompt takes them the same way, but only when a question needs them: the
lookup's endpoint declares
`"provides": [{"fact": ["has-location", "session", "?place"], "request": {}}]`, and
`src/providers.ms` collects that declaration into the registry `main.ms` gives the session. A
question needing `has-location(session, ?p)` - the query itself, or a rule's condition - asks the
service, adds the facts above, and answers, so the domain's `is-a` rule types the place with
nothing pasted into a file. Only a need still unknown at the place does: a reply can fill
`?place` and nothing else, so a need that already names its place - `has-location(session, Dallas)`
bound in a rule body - is left to the prompt rather than asked of a service that could not prove
it. A lookup that fails is a warning and the fact falls through to the
prompt, which asks for it as it asks for any other. Nothing is asked at startup, so a run that
never asks where it is never reaches the network. The request asks for ten seconds rather than
the client's default minute, since it stands between a question and its answer; `declared.fetch`
takes that deadline as its last argument and gives it to the transport.

A host doing the lookup itself reads the same map by hand - `declared.fetch(api, decl, "lookup",
{"fields": ["city", "country"]})` - and finds the request at `result.url` and the service's own
answer at `result.json`; `declared.read(triples, uid, decl, "lookup", result.json)` turns that
answer into the facts above.

`result` is the transport's map - `ok`, `status`, `body`, `json`, `url`, `error` - so a host that
wants the service's own JSON still has it. `fetch` takes the endpoint name first and refuses one
the map does not name by that name (`Unknown endpoint "bulk".`), so a misspelling is reported
rather than requested.
