// Cases for the command line: the defaults a run starts from, and what a flag turns on.
//
// The table is src/options.ms, so this module can parse against the same declarations the
// program uses - which is how a wrong default is caught here instead of in a run nobody can
// explain: --verbose once defaulted to 1, so every session printed a proof tree.

run = function(cli, options, h)
	"Checks the option table with the cli library handed in, as a run builds it."

	values = function(arguments)
		"Parses one argument list the way a run does, and returns the values it reads."
		cmd = cli.newCommand("micro-expert", "0.2.0", "the suite")
		options.declare(cli, cmd)
		// The script path is the first argument, as the shell hands it over.
		return cli.parse(cmd, ["micro-expert"] + arguments).values
	end function

	plain = values([])
	h.check("a run with no flags is not verbose", plain.verbose == 0)
	h.check("and does not say answers in words", plain.nlp == 0)
	h.check("--verbose asks for the proof tree", values(["--verbose"]).verbose == 1)
	h.check("--nlp asks for the words", values(["--nlp"]).nlp == 1)
	h.check("and each flag leaves the other alone",
		values(["--nlp"]).verbose == 0 and values(["--verbose"]).nlp == 0)
	h.check("depth still starts at 8", plain.depth == 8)
	// A run talks to the network only when it was not told not to.
	h.check("a run with no flags may ask a service", plain.offline == 0)
	h.check("--offline refuses every network call", values(["--offline"]).offline == 1)
end function
