// Test harness: counts checks and decides the exit status.

tally = {"passed": 0, "failed": 0}

check = function(name, ok)
	"Records one expectation, printing it so a failure names itself."
	if ok then
		tally.passed = tally.passed + 1
		print "PASS  " + name
	else
		tally.failed = tally.failed + 1
		print "FAIL  " + name
	end if
end function

summary = function()
	"Prints the totals and exits non-zero when anything failed."
	print ""
	print tally.passed + " passed, " + tally.failed + " failed"
	if tally.failed > 0 then exit 1
	exit 0
end function
