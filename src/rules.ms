// rules.ms — the rule loader: the rules are data now, in data/rules.kb at the repo
// root.
//
// A rule is written there as 'head => body':
//
//   uncle-of(?x, ?y) => and(parent-of(?p, ?y), sibling-of(?x, ?p), has-gender(?x, male))
//
// knowledge.ms reads that format; this module finds the file and wraps each piece in
// the Rule class. The file is loaded on request rather than at import time, because
// the rules have to come from the host's copy of triples.ms: a module that imports
// triples.ms gets a copy of its own, and the solver only recognizes the copy it
// holds. main.ms hands its copy in, and gets the array back:
//
//   import "rules"
//   rules = globals["rules"].build(triples)
//
// The class itself lives in rule.ms.

import "knowledge"
import "rule"

build = function(triples)
	"Reads the rules data and returns its rules, built with the caller's triples, or an error."
	pieces = knowledge.loadRules(triples, info(@build).sourceLoc, "../data/rules.kb")
	if pieces isa error then return pieces
	rules = []
	for piece in pieces
		rules.push(rule.Rule.make(piece.head, piece.body))
	end for
	return rules
end function
