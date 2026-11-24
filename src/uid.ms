// uid.ms — one id per entity, generated from what identifies it.
//
// A subject has to be a term, and a term holds one entity: the same entity always under the same
// term, and two entities never under one. Some services hand over an identity worth keeping - an
// OSM object, a GeoNames id - and those are the ones to use. A lookup like ipwho.is's hands over
// nothing but a city, a region and a country, so the identity is generated here from the text that
// says which entity is meant:
//
//   import "uid"
//   uid = globals["uid"]
//   print uid.of("place", ["Fort Worth", "Texas", "United States"])
//   // place-f1d6b283a52a28dc
//
// The id is a hash of that text, in hex, under the kind's prefix. It is derived rather than minted,
// and that is the property that matters here: two runs, two machines and two services that identify
// the same entity the same way agree on its term with no store to look it up in, so a fact written
// today and one written next month land on one subject. A minted id - a UUID drawn from randomness
// - would be unique and useless for that, because nothing would recognize the same city tomorrow
// and every run would write a second copy of every fact.
//
// What it cannot do is see that two spellings are one entity. "Fort Worth, TX" and "Fort Worth,
// Texas" are two identities, and so are two cities of one name in one region once the service's
// other fields stop telling them apart. Case and spacing are not spelling, though: each part is
// lowered and has its runs of spaces squeezed to one, so " Fort  Worth " and "fort worth" are the
// same id.
//
// A part is identity only when it is text or a number. A map or a list holds none of its own - it
// prints as braces or brackets, and hashing those would hand an unnamed entity a term - so it is
// dropped the way a null is. An entity whose parts leave no text at all has no id: the call
// answers "" and the caller writes no facts, rather than every such entity sharing one term.
//
// Sixty-four bits are written, two 32-bit hashes of the text under different salts, so two
// entities share a term only if that many bits fall together. At a million entities the chance is
// about one in forty million: a number worth knowing rather than one to fear at this scale.


hexDigits = "0123456789abcdef"


hexOf = function(number, width)
	"One hash in hex, zero-padded to the width asked for."
	text = ""
	n = number
	for i in range(1, width)
		text = hexDigits[n % 16] + text
		n = floor(n / 16)
	end for
	return text
end function


squeezed = function(text)
	"One part as an identity reads it: lower case, runs of spaces become one, the edges dropped."
	words = []
	for word in text.lower.split(" ")
		if word != "" then words.push word
	end for
	return words.join(" ")
end function


identityOf = function(parts)
	"The text that says which entity is meant: each part squeezed, empties dropped, joined by '|'."
	if parts isa string then parts = [parts]
	written = []
	for part in parts
		// Only text and numbers say anything; a map or a list would contribute the braces it
		// prints as, which names no entity and would give every such part the same term.
		if part == null or not (part isa string or part isa number) then continue
		text = squeezed(str(part))
		if text != "" then written.push text
	end for
	return written.join("|")
end function


of = function(kind, parts)
	"An id for the entity those parts identify: the kind, a dash and 64 bits of hash in hex; empty when nothing identifies it, or when there is no kind to name it by."
	identity = identityOf(parts)
	if identity == "" then return ""
	// The kind says what the term is, and is what gives it a letter to start with: a name's first
	// section starts with a letter, and hex on its own may not.
	prefix = squeezed(kind).replace(" ", "-")
	if prefix == "" then return ""
	// Two salts, so the id is 64 bits rather than the 32 one hash gives: the second half is not a
	// repeat of the first, and an entity whose text collides on one of them does not collide on both.
	return prefix + "-" + hexOf(hash("1|" + identity), 8) + hexOf(hash("2|" + identity), 8)
end function
