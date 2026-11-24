// Cases for the id generator: one term per entity, the same one from run to run, and the
// normalization that stops case and spacing from naming a second entity.
//
// Fort Worth is the entity throughout, because it is what src/location.ms answers with: the
// city, the region and the country are the three fields a place term is built from.

run = function(uid, triples, h)
	id = uid.of("place", ["Fort Worth", "Texas", "United States"])

	// ── What an id looks like ─────────────────────────────────────────────

	h.check("an id starts with its kind", id[:6] == "place-")
	h.check("and carries sixty-four bits of hex after it", id.len == 22)
	h.check("the hex is lower case", id[6:] == id[6:].lower)
	notHex = 0
	for c in id[6:]
		if uid.hexDigits.indexOf(c) == null then notHex = notHex + 1
	end for
	h.check("and made of hex digits", notHex == 0)
	h.check("the id is a legal name", triples.predicateProblem(id) == null)

	// ── The same entity, the same id ──────────────────────────────────────
	// Pinned rather than computed, so a change to the salts or to what counts as the identity has
	// to be deliberate: every id already written into a facts file depends on this line.

	h.check("the id for a known entity is pinned", id == "place-f1d6b283a52a28dc")
	h.check("the same identity is the same id", uid.of("place", ["Fort Worth", "Texas", "United States"]) == id)
	h.check("case is not identity", uid.of("place", ["FORT WORTH", "texas", "UNITED STATES"]) == id)
	h.check("nor is spacing", uid.of("place", ["  Fort   Worth ", " Texas", "United States  "]) == id)

	// ── A different entity, a different id ────────────────────────────────

	h.check("another city is another id", uid.of("place", ["Austin", "Texas", "United States"]) != id)
	h.check("another region is another id", uid.of("place", ["Fort Worth", "Oregon", "United States"]) != id)
	h.check("the parts matter in their order", uid.of("place", ["Texas", "Fort Worth", "United States"]) != id)
	h.check("a missing part is dropped rather than left blank",
		uid.of("place", ["Fort Worth", null, "", "Texas", "United States"]) == id)
	h.check("a number part is read as its text", uid.of("place", [42]) == uid.of("place", ["42"]))
	h.check("a map or a list holds no identity of its own",
		uid.of("place", [{}]) == "" and uid.of("place", [[]]) == "")
	h.check("but other parts still name the entity",
		uid.of("place", [{}, "Fort Worth", [], "Texas", "United States"]) == id)

	// ── What cannot be named ──────────────────────────────────────────────

	h.check("nothing to identify is no id", uid.of("place", []) == "" and uid.of("place", "") == "")
	h.check("and text that is only spaces is nothing to identify", uid.of("place", ["  "]) == "")
	h.check("a kind is needed to name the term", uid.of("", ["Fort Worth"]) == "")

	// ── The kind ──────────────────────────────────────────────────────────

	h.check("the kind is a label rather than part of the identity",
		uid.of("city", ["Fort Worth", "Texas", "United States"])[5:] == id[6:])
	h.check("a kind is spelled like a name", uid.of("Place Type", ["x"])[:11] == "place-type-")
end function
