// Cases for the date, time and datetime types: the three field types, the DateTime a
// fitting text is read into, and the TimeSpan that measures between two of them. They live
// together because a date field's misfit is whatever temporal.DateTime.receive says it is,
// so the reader and the fields typed by it are one subject; the schema's own format and
// unique(...) checks stay in test/schema.ms.

run = function(t, parser, dates, h)
	"Checks the three date field types, the value their texts are read into, and the span between two."
	spo = function(s, p, o)
		return t.SpoTriple.make(s, p, o)
	end function

	dated = parser.parseSchema([
		"founded-on(text, date)",
		"opens-at(text, time)",
		"seen-at(text, datetime)",
		"born-on(text, unique(date))",
	])
	h.check("date, time and datetime are field types", dated["opens-at"][1] == "time")
	h.check("a calendar date fits",
		parser.schemaMisfit(dated, spo("acme", "founded-on", "2019-04-01")) == null)
	h.check("a date is not a value list",
		parser.schemaMisfit(dated, spo("acme", "founded-on", "date")) ==
			"the object should be a date")
	h.check("a day the calendar does not have is refused",
		parser.schemaMisfit(dated, spo("acme", "founded-on", "2019-02-30")) ==
			"the object should be a date")
	h.check("a date written another way is refused",
		parser.schemaMisfit(dated, spo("acme", "founded-on", "3/15/2019")) ==
			"the object should be a date")
	h.check("a clock time fits",
		parser.schemaMisfit(dated, spo("acme", "opens-at", "09:30:00")) == null)
	h.check("a time is written to the second",
		parser.schemaMisfit(dated, spo("acme", "opens-at", "09:30")) ==
			"the object should be a time")
	h.check("there is no minute 60",
		parser.schemaMisfit(dated, spo("acme", "opens-at", "09:60")) ==
			"the object should be a time")
	h.check("a date and a time together fit a datetime",
		parser.schemaMisfit(dated, spo("acme", "seen-at", "2019-04-01 09:30:00")) == null)
	h.check("a date alone is not a datetime",
		parser.schemaMisfit(dated, spo("acme", "seen-at", "2019-04-01")) ==
			"the object should be a date and time")
	h.check("unique(...) wraps a date as it wraps any type",
		parser.schemaMisfit(dated, spo("acme", "born-on", "2019-04-01")) == null)

	// The text is what a fact stores; the DateTime is what it means. temporal.ms reads all
	// three types into one object, so a value can be formatted, moved and ordered without going
	// back to text.
	when = dates.DateTime.receive("2019-04-01 09:30:00")
	h.check("a fitting text is read into a DateTime", when isa dates.DateTime)
	h.check("it keeps its shape and its parts",
		when.kind == "datetime" and when.year == 2019 and when.month == 4 and
			when.day == 1 and when.hour == 9 and when.minute == 30 and when.second == 0)
	h.check("it formats itself in the type's form", when.str == "2019-04-01 09:30:00")
	h.check("and in any format asked for", when.str("HH:mm") == "09:30")
	h.check("it moves by seconds", when.addSeconds(90).str == "2019-04-01 09:31:30")
	h.check("a time moves around midnight",
		dates.DateTime.receive("23:59:30").addSeconds(60).str == "00:00:30")
	// The host's own dates begin in 1970, so an older one is counted here. A step back over
	// that boundary lands on an older date too, and has to read and order like one.
	old = dates.DateTime.receive("1948-03-14")
	h.check("a date before 1970 keeps the shape it was written in", old.str == "1948-03-14")
	h.check("an older date moves by seconds", old.addSeconds(86400).str == "1948-03-15")
	h.check("a step back over 1970 does not stop at it",
		dates.DateTime.receive("1970-01-01").addSeconds(-86400).str == "1969-12-31")
	h.check("and the two sides order by their dates",
		dates.DateTime.receive("1969-12-31").compare(dates.DateTime.receive("1970-01-01")) == -1)
	// A datetime crosses the same boundary with its clock: the step into 1970 lands on a
	// value the host can print, and the step back out of it lands on one it cannot, so both
	// directions have to read back as the day and clock they are.
	lastOld = dates.DateTime.receive("1969-12-31 23:59:59")
	newYear = dates.DateTime.receive("1970-01-01 00:00:00")
	h.check("an old datetime keeps its day and its clock",
		lastOld.str == "1969-12-31 23:59:59" and lastOld.compare(newYear) == -1)
	h.check("the last second of 1969 crosses into the host's year",
		lastOld.addSeconds(1).str == "1970-01-01 00:00:00")
	h.check("and the first second of 1970 steps back out of it",
		newYear.addSeconds(-1).str == "1969-12-31 23:59:59")
	h.check("an older datetime moves by seconds where it stands",
		dates.DateTime.receive("1948-03-14 09:30:00").addSeconds(3600).str == "1948-03-14 10:30:00")
	h.check("it orders against its own kind",
		when.compare(dates.DateTime.receive("2019-04-01 10:00:00")) == -1 and
			when.compare(dates.DateTime.receive("2019-04-01 09:30:00")) == 0)
	h.check("a bare time has no date",
		dates.DateTime.receive("09:30:00").year == null and dates.DateTime.receive("09:30:00").day == null)
	h.check("a datetime is written with a space, not a T",
		dates.DateTime.receive("2019-04-01T09:30:00") isa error)
	h.check("another kind is not compared", when.compare(dates.DateTime.receive("09:30:00")) isa error)
	h.check("the kind is read off the text",
		dates.DateTime.receive("2019-04-01").kind == "date" and dates.DateTime.receive("09:30:00").kind == "time")
	h.check("a text of no kind is refused", dates.DateTime.receive("nonsense") isa error)

	// A TimeSpan is how much time passed between two values of one kind: the difference of
	// their counts, which are wall-clock seconds from the same base, so two dates differ by
	// whole days and two datetimes by the seconds between them.
	evening = dates.DateTime.receive("2019-04-01 09:00:00")
	span = when.since(evening)
	h.check("a span between two values is a TimeSpan", span isa dates.TimeSpan)
	h.check("it counts the seconds between them",
		span.seconds == 1800 and span.minutes == 30 and span.hours == 0)
	h.check("and reads as a duration", span.str == "00:30:00")
	twoDays = dates.DateTime.receive("2019-04-03").since(dates.DateTime.receive("2019-04-01"))
	h.check("a date's span counts whole days",
		twoDays.days == 2 and twoDays.seconds == 172800 and twoDays.str == "2d 00:00:00")
	h.check("the same span the other way is negative",
		dates.TimeSpan.between(dates.DateTime.receive("2019-04-03"),
			dates.DateTime.receive("2019-04-01")).str == "-2d 00:00:00")
	h.check("whole units round toward zero",
		dates.TimeSpan.between(dates.DateTime.receive("09:30:00"),
			dates.DateTime.receive("08:00:00")).hours == -1)
	h.check("only one kind is measured",
		dates.TimeSpan.between(dates.DateTime.receive("2019-04-01"),
			dates.DateTime.receive("09:30:00")) isa error)
	h.check("a span is between values, not text",
		dates.TimeSpan.between("2019-04-01", "2019-04-02") isa error)
end function
