# Gaps to close before these APIs are knowledge

Both API references now end with the triples their replies support:
[geocode.maps.co](geocode-maps-co.md) and [Open-Meteo](open-meteo.md). This page is the other half
of that review - what still stands between a reply and a usable domain, grouped by where the seam
is: what the services do not say, what a two-field fact cannot hold, what the engine cannot compute,
and what the two programs do not do.

Nothing here is a defect. Each entry is a place where the shape of a fact, the shape of an answer,
and the work the engine is willing to do leave something out; the last column is the smallest thing
that would close it, not the best thing.

## 1. What the replies do not say

| Gap | Why it bites | Smallest close |
| --- | --- | --- |
| **The model is not in the reply.** `models=auto` combines several, a model host names one in its URL, and no field in the envelope says which produced a number. | A value cannot be attributed to a model, so two fetches with different `models` cannot be compared, and a fact cannot be refreshed from its own provenance. | The model in the folder name - `domains/ecmwf-2026-11-22/` - or a `was-asked` line per file. |
| **The request is not echoed.** `cell_selection`, the requested `elevation`, `forecast_hours`, the unit parameters: all are sent, none comes back. | A file cannot say what was asked, so it cannot be re-derived; a `past_days` or `forecast_hours` window makes its contents different tomorrow. | One `was-asked(?p, models=ecmwf)` fact per parameter per file, written by the writer. |
| **No fetch time.** Neither reply carries a server timestamp, and `generationtime_ms` measures the service rather than the answer. | "These are today's numbers" has nowhere to live, and a relative window loses its anchor. | `fetched-at(berlin@2026-11-22, 2026-11-22T09:14:00)` per file, or the date in the folder name. |
| **The grid cell is invisible.** The reply gives the cell's coordinates but not that it snapped, not the model's resolution, and not whether a marine answer came from the nearest sea point. | A reading cannot be checked against the place it is meant to be about, and a coastal coordinate can quietly answer from offshore. | `has-grid-latitude` and `has-grid-longitude` beside `has-latitude` and `has-longitude`, so the gap between them is at least visible. |
| **A `null` and a missing variable are the same nothing.** | Negation as failure reads "the model has none" and "this place is outside its grid" as "unknown". | The writer records `has-unavailable(?s, snowfall)` for a variable that was asked for and came back null. |
| **The Open-Meteo geocoder gives no OSM ids.** A result has its own `id`, which is a GeoNames id, and no `osm_type`/`osm_id`. | The two services cannot be joined: one city is two subjects unless something says so. | One hand-written bridge fact, `has-osm-object(berlin, way/5013364)`, and the reverse `has-geonames-id`. |
| **No quota, retry or cache in the transport.** `src/api/client.ms` runs one curl with a 60-second timeout: no retry, no backoff, no cache, no count. | A snapshot over many places spends the free allowance with no record of it, and one `429` loses the fetch. | Retry once on `429` after a pause and count requests per run; a `--cache` folder is the larger fix. |

## 2. What a two-field fact cannot hold

| Gap | Why it bites | Smallest close |
| --- | --- | --- |
| **A term cannot be taken apart.** `berlin@2026-11-22T00:00` holds a place and an instant, and no rule can recover either. | Every join on one half - the same instant in another city, everything about one place - needs that half repeated as its own fact. | Accept the duplication (`has-instant` is the first of them), or reify the reading as four facts. |
| **No string or number work in a body.** A body has facts, the three groupings and seven constraints: nothing concatenates, splits, rounds, converts or extracts. | A unit cannot be stripped from a value, `°C` cannot become `celsius`, a coordinate cannot be rounded into a key, and a subject cannot be built from its parts. | All of it belongs in the writer, which is why the writer is the first gap to close. |
| **No term for provenance.** A fact uses all three of its terms. | Model, run, fetch time and service have no seat, so the workarounds are a folder per snapshot or a date in the predicate name. | A folder per snapshot, with a `was-asked` and a `fetched-at` line inside it. |
| **Dates and instants are text.** `datetime` wants `2026-11-22 00:00:00`, the reply writes `2026-11-22T00:00`, and only the comparisons order values. | The reply's timestamps fit no date type as they stand, and none of them can be ordered. | Rewrite to the type's spelling when the type is wanted; ask for `timeformat=unixtime` when ordering is. |
| **A value carries no unit.** A `number` field cannot say celsius. | Two snapshots taken with different unit parameters mix silently, and nothing converts. | `has-unit` per variable per file, and never two unit sets in one folder. |
| **A value carries no height either.** `has-temperature-2m` puts 2 m in the predicate name, so a temperature at 10 m would be a second predicate, and neither field holds the height. | Two heights over one subject are two predicates, so nothing compares them by height, and a rule that meant "any temperature" has to name every height that exists. | One predicate per height, named and typed by the writer as it writes, or a reified reading with `has-height(?r, 2)` beside `measures` and `has-value`. |
| **A series does not fit.** One fact per number: sixteen days hourly is 384 facts for one variable, and 15,360 for five variables over eight places. | A realistic snapshot is tens of thousands of facts and the reader takes the file whole. | Measure it once at that size before a domain depends on it; nothing in the repository sets a size budget. |

## 3. What the engine cannot compute

| Gap | Why it bites | Smallest close |
| --- | --- | --- |
| **No arithmetic but four comparisons and `years-since`.** No difference, mean, minimum, maximum, count, sum, ratio, rounding or conversion. | Weather is numbers: daily means, ranges, totals, anomalies and `°F` to `°C` are facts to compute at write time, not rules. | Compute them in the writer, where the numbers are still numbers, or ask the service for an aggregate it already has - `daily` maxima, the ensemble mean. |
| **No aggregate over a set of facts.** A body proves one binding at a time and nothing counts what it found. | "How many hours below freezing", "the warmest hour this week" and "the spread across 31 members" cannot be asked. | One computed fact per question worth answering: `has-hours-below-freezing(berlin@2026-11-22, 7)`. |
| **Text does not order.** `2026-11-22T00:00` and `2026-11-22T01:00` sort nowhere. | Chronology is impossible without the numeric instant, so a time rule needs `has-instant` and `timeformat=unixtime`. | Always write `has-instant` for a file that is meant to be reasoned over. |
| **Matching is exact.** `52.52437` and `52.512604` are different numbers, `Paris` and `paris` are different places, `°C` and `celsius` are different words. | Nothing joins two sources on a near-match, so the two services' coordinates cannot meet. | Key on a name chosen once, never on a coordinate, and normalise text in the writer. |
| **Negation is failure.** `not(p(...))` means "not provable", which is also "not said". | Absence can never be asserted, only unknown. | Assert the negatives worth knowing, or let the writer record them. |
| **`unique(...)` is per subject, and refused on a derived predicate.** | It cannot say "one reading per variable per instant", and a rule's conclusion cannot be given a one-value rule at all. | A fact's `@` carries the instant, so two hours are two facts without a composite subject; `unique(...)` stays about the subject and predicate a fact names. |

## 4. What the programs do not do

| Gap | Why it bites | Smallest close |
| --- | --- | --- |
| **Nothing writes facts.** Both programs fetch and print; the conversion both reference pages describe does not exist in code. | Every triple in those pages is written by hand today, so neither API is usable as knowledge yet. | A `--facts FILE` switch on each program, or one shared writer both call: the geocoder's loop is property-per-field, the forecast's is index-per-instant. |
| **No domain per source.** `--domain` reads a folder of three files, and nothing writes one. | Two fetches land in one file with no record of which said what. | The writer names a folder - `domains/berlin-2026-11-22/` - and fills all three files. |
| **No multi-location collection.** A coordinate list turns the reply into a list of objects. | The writer needs two code paths, and nothing gathers several places into one snapshot. | One loop over the reply's elements, each with its own subject. |
| **`format=csv` and `xlsx` bypass JSON.** The layer's `json` field is null for them. | A writer built on the parsed reply cannot read them, so the documented formats are not equally reachable. | Leave them to the printer, or parse CSV in the writer; XLSX is not worth it. |
| **No rule ships for either vocabulary.** Both pages name rules that would work, and `data/rules.kb` holds the family's. | Nothing exercises the vocabulary, so a wrong name or type shows up only when someone builds a domain by hand. | A `domains/places/` and `domains/weather/` pair with a dozen facts and two rules each, added to the suite. |

## 5. What to close first

1. **A writer, shared by both programs.** Until a reply can become a `.kb` file without a person
   typing it, everything above is a sketch. This is the one gap that makes the rest worth closing.
2. **A snapshot folder and its provenance.** One folder per fetch, one model set, one unit set, and
   a `was-asked` and a `fetched-at` line inside it. That closes three rows above in one move.
3. **Instants as numbers.** `timeformat=unixtime` whenever a file is meant to be reasoned over, and
   a `has-instant` fact for every reading. It is the only way a time rule can exist.
4. **A place key both services agree on.** One name per place, `has-geonames-id` from Open-Meteo's
   geocoder, `has-osm-object` from geocode.maps.co, written once by hand. Then both services' facts
   land on one subject instead of two.
5. **Unit facts in every weather file.** Cheap to write, and the only thing between a folder and
   silently mixed `°F`.
6. **One measurement at size.** A sixteen-day, five-variable, eight-place snapshot is 15,360 facts;
   find out what the reader and the solver do with that before a domain is built on it.

## What is not a gap

Worth saying, because it looks like one: the layer's tables already carry every parameter the two
documents list, the checks they make are the services' own limits, and an unknown parameter is
passed through rather than dropped. The surface is not what is missing. The conversion is.
