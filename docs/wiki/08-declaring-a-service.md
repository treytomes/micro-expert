# 8. Declaring a service

A domain answers from its facts and rules. A service answers a fact the session cannot prove, and
it is asked only when a question needs one. Declaring a service is writing a document: its host, its
endpoints, what each endpoint can answer, and how its reply becomes facts. `src/services/declared.ms`
reads the map, `src/providers.ms` collects what the maps declare into one registry, and
`src/session.ms` asks them. Nothing in the engine knows a service by name.

This chapter writes one: a local service that reports a room's temperature. It runs on the same
machine, so the whole loop - map, request, reply, fact - can be watched without a key or a network.

## What the session does with a declaration

A declaration is not a fetch at startup. A question is answered from the facts and rules first, and
the missing-fact report names what a solution would still need (chapter 3). When one of those facts
is one an endpoint says it can answer, the session asks that endpoint before it asks the reader: the
reply becomes facts, the question runs again, and the answer is printed. A run with `--offline`
builds no registry at all, so nothing reaches the network and the report is asked the way it was
before there were services.

Two endpoints may declare the same fact - both shipped geocoders declare a place's coordinates - and
then each is asked in the order the declarations are read, and the first that answers stops the
asking. A failure is a warning, not a failed question: the next declaration is tried, and when none
answers the fact falls through to the reader.

Every fact an answer adds carries `# <service>/<endpoint> <day>` in its own line:

```prolog
has-temperature(lab, 21.5) # desk.local/reading 2026-11-25
```

That is how the session, `/facts`, or a facts file it saves tells a provider's fact from a typed one
and sees how old it is. A reading fetched on an earlier day is not today's: a question that needs
the fact asks the service again first, and falls back to the old line with a note only when nothing
can refresh it. A request is remembered for the run, so the same question twice asks once; `/undo`
takes a service's whole answer back and forgets the request with it, so the next question asks
again. The facts a reply adds are held to the schema like typed ones, and a reply that spells a unit
another way than the session holds is refused whole rather than added beside it.

## Where a declaration lives

A declaration is a document in `services/`, named `<service>.grfon`. It is data rather than code:
the shipped services are tables in that format, and the writer reads only what the document resolves
to. Nothing registers it: `src/services/loader.ms` lists the folder, reads every `.grfon` in it
through `src/services/document.ms`, and both hosts build their registry from what it found. Dropping
the file in the folder is the whole of adding a service.

The declarations are read in file-name order, and that is the order a session tries them in when
more than one declares the same fact. Nothing in a declaration runs at answer time, and it has no
imports to make: the request, the reading and the generated terms are the writer's business.

| Key | What it is |
| --- | --- |
| `service` | The name in warnings and in the `#` line: `desk.local` |
| `base` | The scheme and host every endpoint is under, unless an endpoint names its own |
| `keyEnv` | Optional. The environment variable a key is read from, when the service needs one |
| `endpoints` | One entry per endpoint, keyed by the name a declaration and a warning use |

## An endpoint

An endpoint is one request and one reading:

| Key | What it is |
| --- | --- |
| `method` | `GET`. The client sends a GET; the field is recorded for the reader |
| `path` | Appended to `base` |
| `base` | Optional. This endpoint's host, when it differs from the map's |
| `params` | The parameters the request may carry |
| `provides` | What a question may ask this endpoint for |
| `reply` | How a JSON reply becomes facts |
| `key` | Optional. The parameter a key travels as |
| `redact` | The parameters whose values are hidden in a url a result carries |
| `boolAs` | Rewrites true and false the way a service spells them |

### `params`

```miniscript
params: {
  {name: room; type: int; required: 1;
    doc: The room's id, as the session holds it.}
}
```

A spec has a `name` and a `type`, and optionally `required`, `default`, `min`, `max`, `values`,
`allowNan` and `doc`. The types are the ones the API layer checks:

| Type | What it takes |
| --- | --- |
| `text` | Any string |
| `int` | A whole number, within `min` and `max` when given |
| `number` | Any number, within `min` and `max` when given |
| `enum` | One of `values` |
| `bool` | true/false, 1/0, yes/no, on/off |
| `coordinates` | A number, or a comma-separated list of numbers, each within `min` and `max` |
| `csv` | A comma-separated list, given as a string or as a list |
| `date` | `yyyy-mm-dd` |
| `datetime` | `yyyy-mm-ddThh:mm` |

A value is checked before a request is made, and a parameter the table does not list is passed
through untouched, so an endpoint can carry a parameter added after the map was written. Every value
goes on the wire as text; a list joins with commas.

### `provides`

An endpoint says what a question may ask it for, as one capability or a list of them:

```miniscript
provides: {
  {fact: {has-temperature; ?place; ?value}; about: ?place;
    from: {room: has-room-id}}
}
```

| Key | What it is |
| --- | --- |
| `fact` | The one fact this endpoint answers, in the three parts a fact has |
| `about` | The declared part the reply's facts are read onto: the term the question named |
| `from` | Each request field, and the predicates a held fact may fill it from |
| `request` | Fields the declaration fills itself, such as `{"limit": 1}` |
| `timeout` | Seconds the call may take; 10 when left out |

A part beginning `?` is a variable and matches a term the question has not bound yet, which is what
the reply fills. Any other part is a literal and matches only itself, so ipwho.is's lookup answers
`has-location(session, ?p)` and is not asked for `has-location(tim, ?p)` or for an already-ground
`has-location(session, Dallas)`, which no reply can be counted on to prove.

`about` is what lets a question name the subject:

```prolog
has-temperature(lab, ?t)
```

Here `lab` is already ground while the pattern's first part is a variable, so without `about` the
capability would not fit. `about` names the part the reply's facts are read onto: each fact is
written about the term the question named, and the part is bound to it for the reading, so a fact
line can say `?place` and mean `lab`. The service is not sent the place under that name; it is given
only the fields the declaration fills. A `has-unit` fact is the exception, and stays about the
variable the reply named, so a rule can ask it.

`from` fills a request field from facts the session already holds about the subject, trying the
predicates in order and taking the first fact it finds. Today's reading is preferred to an earlier
day's, since a request sent now should not be computed from a stale coordinate. When no fact fills a
field, the request is not sent: the session asks another service for one of the named facts first,
and comes back to this request with it. If nothing can supply it, the reader is asked.

## The reply

The reply half says how one JSON reply becomes facts. Its clauses run in this order:

| Key | What it says |
| --- | --- |
| `each` | The list to read: `"$"` for the reply itself, or a path such as `"$.results"` |
| `refuse` | When the service said no: `{"when": "success", "is": false, "message": "message"}`, or `{"present": "error", "message": "error.message"}` |
| `require` | The fields without which there is no subject to hang facts on |
| `subject` | What identifies the reply: `{"kind": "room", "name": "place", "from": ["name"]}` for a term the writer generates, or `{"name": "place", "from": ["osm_type", "osm_id"], "join": "/"}` for the service's own identity |
| `request` | The request's fields a fact may name, bound under their own names |
| `facts` | One `[predicate, subject, object, annotations]` per line |
| `confirm` | The reply fields that must agree with facts the session holds about the place, when a search takes its first result |
| `series` | Parallel lists read row by row, for a weather-shaped reply; the [Open-Meteo page](../api/open-meteo.md) is the reference |

A refusal is read before a fact is, because a service may refuse with a 200. `require` and
`subject` are the reply's own identity: even when `about` moves the facts onto the question's
subject, the reading still needs something to read the reply against.

Each side of a fact is one of:

| Written | Means |
| --- | --- |
| `?name` | A name the reading bound: the subject, or a field the request carried |
| `$.a.b[0]` | A path into the reply; an index is allowed at any step |
| `$.a[i]`, `$.a[i+1]` | The same, at the reading's row, or one row on |
| `$.a as number` | The field read as a number |
| `$.a as text` | The field read as text |
| `$.a as moment` | The field as the grammar spells a datetime: `2026-11-25T09:00:00` becomes `2026-11-25 09:00:00` |
| `["$.a", "$.b"]` | The first of these the reply carries |
| Anything else | A literal term |

The fourth element of a fact line is optional annotations: `{"at": "?time"}` for the moment it
holds, `{"span": ["?time", "$.a[i+1]"], "or": "?time"}` for a range, and `{"confidence": "$.a[i]"}`
for a percentage. A confidence that is absent leaves the fact fully confident; one that is not a
number from 0 to 100 leaves the fact out.

A field the reply leaves out, a value that will not read as the type it was asked for, and a
confidence outside 0 to 100 all write no fact. The reading names each in its `skipped` list rather
than inventing a value. Nothing in a reply is computed: one line is one fact, a list of objects is
read with `each`, and a table of parallel lists is read with `series`.

## Worked example: the desk service

The service is a Python 3 script on `127.0.0.1:8787` that answers one room's temperature. Save it as
`desk.py` anywhere and start it with `python3 desk.py`. Any HTTP server that answers the same JSON
does as well; the map does not know how the service is written.

```python
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs
from datetime import datetime, timezone
import json

ROOMS = {"3": {"name": "Lab 3", "celsius": 21.5}}


class Desk(BaseHTTPRequestHandler):
    def do_GET(self):
        url = urlparse(self.path)
        if url.path != "/reading":
            return self.reply({"ok": False, "reason": "no such endpoint"})
        room = parse_qs(url.query).get("room", [""])[0]
        if room not in ROOMS:
            return self.reply({"ok": False, "reason": "no room " + room})
        measured = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
        self.reply({"ok": True, "measured": measured, **ROOMS[room]})

    def reply(self, body):
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


HTTPServer(("127.0.0.1", 8787), Desk).serve_forever()
```

A request for room `3` answers:

```json
{"ok": true, "measured": "2026-11-25T09:00:00", "name": "Lab 3", "celsius": 21.5}
```

and a room it does not have answers `{"ok": false, "reason": "no room 9"}` with a 200, which is why
the declaration needs a `refuse` clause.

The declaration goes in `services/desk.grfon`:

```miniscript
service: desk.local
base: http://127.0.0.1\:8787

endpoints: {
  reading: {
    method: GET
    path: /reading
    params: {
      {name: room; type: int; required: 1;
        doc: The room's id, as the session holds it.}
    }
    provides: {
      {fact: {has-temperature; ?place; ?value}; about: ?place;
        from: {room: has-room-id}}
    }
    reply: {
      // A refusal is a 200 with ok false, so it is read before any fact is.
      refuse: {when: ok; is: 0; message: reason}
      require: {name}
      subject: {kind: room; name: place; from: {name}}
      facts: {
        {has-temperature; ?place; $.celsius as number};
        {has-reading-at; ?place; $.measured as moment};
        {has-room; ?place; $.name}
      }
    }
  }
}
```

Read it as four decisions:

- **The fact.** `provides.fact` says the endpoint answers `has-temperature(?place, ?value)`. `about`
  says the reply is about the place the question named, and `from` fills the request's `room` from
  the session's `has-room-id`. A question about `lab` therefore sends `room=3`, and a room the
  session holds no id for is not sent at all.
- **The refusal.** The service says no with a 200 and `"ok": false`, so `refuse` reads `ok` before
  any fact does.
- **The identity.** `require` and `subject` say what makes the reply readable. The subject is
  generated from the room's name, so two replies about Lab 3 are about one term; with `about`, the
  facts themselves are moved onto `lab` anyway.
- **The facts.** `as number` reads the JSON number as the fact's number, and `as moment` turns
  `2026-11-25T09:00:00` into the grammar's `2026-11-25 09:00:00`. The room's name is written as a
  fact of its own, because a fact holds one value.

The domain supplies the id the request needs, and the types of every predicate the reply writes:

`data/facts.kb`:

```prolog
has-room-id(lab, 3)
```

`data/schema.kb`:

```prolog
has-room-id(text, number)
has-temperature(text, number)
has-reading-at(text, datetime)
has-room(text, text)
```

`has-reading-at` is a `datetime` rather than text because `as moment` writes exactly the shape the
type fixes. A predicate the reply writes and the schema does not name is still added, but the schema
is what refuses a value no rule could use, so every line belongs there.

## Registering it

There is nothing to register. Save the document as `services/desk.grfon` and the next run finds
it: `src/services/loader.ms` lists that folder, reads every `.grfon` in it, and both hosts build
their registry from what it found - `src/main.ms` at startup, and `src/notebook.ms` in
`enableServices`, which is what a cell's `/online` attaches.

```miniscript
loaded = globals["services/loader"].load(globals["services/document"], globals["knowledge"])
maps = []
for kv in loaded
	if not (kv.value isa error) then maps.push kv.value
end for
engineSession.providers = providers.registry(globals["api/http_client"],
	globals["services/declared"], globals["uid"], maps)
```

`load` answers a map keyed by file name, so a host that wants one service asks for it by its file -
`loaded["ipwhois.grfon"]`, as `src/where.ms` does - and a file that is refused is an error value
beside that name, which costs that one service rather than the run.

The order is the order the session asks in when more than one declaration claims a fact, and it is
the file name's order: `geocode.grfon` is read before `openmeteo.grfon`, so the geocoder's
coordinates are asked for before the forecast's. A service that should be preferred needs a name
that sorts first.

Now start the server and ask a question the facts cannot answer:

```text
$ python3 desk.py &
$ ./micro-expert.sh
? has-temperature(lab, ?t)
  added has-temperature(lab, 21.5) # desk.local/reading 2026-11-25
  added has-reading-at(lab, 2026-11-25 09:00:00) # desk.local/reading 2026-11-25
  added has-room(lab, Lab 3) # desk.local/reading 2026-11-25
  has-temperature(lab, 21.5) # desk.local/reading 2026-11-25
```

The three lines before the answer are the facts the reply became, and the answer carries the same
source and day. `/facts` shows them afterwards, and `/save-facts` writes them with their `#` lines,
so a file keeps where each reading came from and how old it is.

Stop the server and ask again in a new session:

```text
? has-temperature(lab, ?t)
  desk.local could not answer has-temperature(lab, ?t): The request failed (curl exit 7): ...
  no solution found at depth 8
  A solution would need one of these:
    a fact like has-temperature(lab, ?t)
```

The failure is a warning, and the question is reported and asked the way it was before the map
existed - chapter 3's report, with the reader asked for the value. A service that is down does not
take the question down with it.

## Checklist for a new service

1. Write the declaration in `services/<service>.grfon`: the base, the endpoint's path and
   params, the one fact it answers, and how its reply is read.
2. Decide where each request field comes from. A field the session can hold belongs in `from`; a
   constant belongs in `request`.
3. Read the reply before writing the map: a refusal sent as a 200, the fields that identify an
   answer, and the spelling of each value. `as number`, `as text` and `as moment` are the three
   conversions; a value that needs a fourth is a fact to write differently.
4. Add a schema line for every predicate the reply writes, not only the one it declares.
5. Drop the file in `services/` - both hosts pick it up - and name it so that it sorts where you
   want the session to ask it.
6. Ask a question that needs the fact, stop the service and ask again, and read `/facts` to see the
   `#` line. A service that answers and a service that fails are both worth one check in
   `test/providers.ms`, which asks the registry the way a session does without a network.

## Where to read more

- `src/providers.ms` - what the registry does with a declaration, and what a request is sent with.
- `src/services/declared.ms` - the reading, clause by clause, including `series`, `once` and
  `confirm`.
- The three shipped services are the worked examples of a single object, a table of readings, and a
  list of results: `services/ipwhois.grfon`, `geocode.grfon` and `openmeteo.grfon`, the folder
  `src/services/loader.ms` reads.
- The API pages under [`docs/api`](../api/) write each shipped service's surface out: its request,
  its reply, and the facts the map makes of it.
