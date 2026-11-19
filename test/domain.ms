// Cases for the domain: which three files a run reads.

run = function(domain, h)
	"Checks the three paths --domain and the per-file options produce."

	// A run with no options reads the folder the program ships, which is data/.
	plain = domain.pathsFor({"domain": null, "facts": null, "rules": null, "schema": null})
	h.check("no options reads data/facts.kb", plain.facts == file.child("data", "facts.kb"))
	h.check("no options reads data/rules.kb", plain.rules == file.child("data", "rules.kb"))
	h.check("no options reads data/schema.kb", plain.schema == file.child("data", "schema.kb"))

	// --domain moves all three at once, by the names a domain folder holds.
	folder = domain.pathsFor({"domain": "domains/invoices", "facts": null, "rules": null, "schema": null})
	h.check("a domain folder holds the three files",
		folder.facts == file.child("domains/invoices", "facts.kb") and
			folder.rules == file.child("domains/invoices", "rules.kb") and
			folder.schema == file.child("domains/invoices", "schema.kb"))

	// One file can be replaced while the folder provides the other two, which is how a
	// draft of one component is tried against the rest of a domain.
	mixed = domain.pathsFor({"domain": "domains/invoices", "facts": "~/draft-facts.kb",
		"rules": null, "schema": "draft-schema.kb",})
	h.check("--facts overrides the folder's facts", mixed.facts == "~/draft-facts.kb")
	h.check("the folder still provides the rules",
		mixed.rules == file.child("domains/invoices", "rules.kb"))
	h.check("--schema overrides the folder's schema", mixed.schema == "draft-schema.kb")

	// A blank value is the same as not giving the option at all, so a shell variable that
	// is set but empty does not ask for a file named "".
	blank = domain.pathsFor({"domain": "", "facts": "", "rules": "", "schema": ""})
	h.check("a blank option falls back to the default",
		blank.facts == file.child("data", "facts.kb"))
	h.check("a blank folder falls back to data/",
		blank.rules == file.child("data", "rules.kb"))

	// --facts without --domain still replaces the default folder's facts file, leaving the
	// other two where they were.
	alone = domain.pathsFor({"domain": null, "facts": "mine.kb", "rules": null, "schema": null})
	h.check("--facts alone replaces the default facts file", alone.facts == "mine.kb" and
		alone.rules == file.child("data", "rules.kb"))
end function
