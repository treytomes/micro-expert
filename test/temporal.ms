// Cases for the date, time and datetime types: the three field types, the DateTime a
// fitting text is read into - written in full or with a part left short - and the TimeSpan
// that measures between two of them, which also reads the two from one bracketed text. They live
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
	// A short text is a convenience for a reader, not a spelling a fact may keep: a date field
	// stores the day it is on, so one month written without it is not a date a fact holds.
	h.check("a date without its day is not one a fact stores",
		parser.schemaMisfit(dated, spo("acme", "founded-on", "2019-04")) ==
			"the object should be a date")

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

	// A part may be written short: a date without its day is the first of that month, and a
	// clock without its seconds is the start of that minute. The value is that instant, so it
	// prints in the full shape its kind has.
	month = dates.DateTime.receive("2019-04")
	h.check("a date written to the month is read as its first day",
		month isa dates.DateTime and month.kind == "date" and month.year == 2019 and
			month.month == 4 and month.day == 1)
	h.check("and prints in the calendar's full shape", month.str == "2019-04-01")
	h.check("it is the same value the full date is",
		month.compare(dates.DateTime.receive("2019-04-01")) == 0)
	h.check("a month the year does not have is refused", dates.DateTime.receive("2019-13") isa error)
	h.check("a year of three digits is not a date", dates.DateTime.receive("201-04") isa error)
	minute = dates.DateTime.receive("09:30")
	h.check("a clock time without its seconds reads from the minute's start",
		minute isa dates.DateTime and minute.kind == "time" and minute.second == 0 and
			minute.str == "09:30:00")
	h.check("there is still no minute 60", dates.DateTime.receive("09:60") isa error)
	h.check("a datetime reads with a short clock",
		dates.DateTime.receive("2019-04-01 09:30").str == "2019-04-01 09:30:00")
	h.check("and with a short date",
		dates.DateTime.receive("2019-04 09:30:00").str == "2019-04-01 09:30:00")
	h.check("or with both short",
		dates.DateTime.receive("2019-04 09:30").str == "2019-04-01 09:30:00")
	h.check("a short text moved by seconds prints the full shape",
		dates.DateTime.receive("09:30").addSeconds(30).str == "09:30:30" and
			dates.DateTime.receive("2019-04").addSeconds(86400).str == "2019-04-02")
	// The space around a value is padding a reader steps over, the way a prompt's leading
	// space is; the value is the same either way.
	h.check("space around a value is not part of it",
		dates.DateTime.receive(" 2019-04-01 09:30 ").str == "2019-04-01 09:30:00")
	h.check("but a fact does not store that padding",
		parser.schemaMisfit(dated, spo("acme", "founded-on", " 2019-04-01")) ==
			"the object should be a date")

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

	// A span reads from text too: the two values it lies between, in square brackets with a
	// comma between them, each written in any shape a DateTime reads.
	read = dates.TimeSpan.receive("[2019-04-01 09:00:00, 2019-04-01 09:30:00]")
	h.check("a span reads from two values in brackets",
		read isa dates.TimeSpan and read.seconds == 1800 and read.str == "00:30:00")
	h.check("the later value may come first, and the span is negative",
		dates.TimeSpan.receive("[2019-04-03, 2019-04-01]").str == "-2d 00:00:00")
	h.check("the values inside may be written short",
		dates.TimeSpan.receive("[2019-04-01 09:00, 2019-04-01 09:30]").minutes == 30)
	h.check("a month to a month counts the days between them",
		dates.TimeSpan.receive("[2019-04, 2019-06]").days == 61)
	h.check("a span with no brackets is refused",
		dates.TimeSpan.receive("2019-04-01 09:00:00, 2019-04-01 09:30:00") isa error)
	h.check("a span needs both values", dates.TimeSpan.receive("[2019-04-01 09:00:00]") isa error)
	h.check("and needs a comma between them",
		dates.TimeSpan.receive("[2019-04-01 09:00:00 2019-04-01 09:30:00]") isa error)
	h.check("a span of two kinds is refused",
		dates.TimeSpan.receive("[2019-04-01, 09:30:00]") isa error)

	// A span keeps the two values it was measured between, so a value can be asked whether it
	// is inside it: both ends count, and a span written the other way round holds the same
	// ground, since the two ends are what it has rather than a direction.
	h.check("a span keeps its two ends",
		span.start.str == "2019-04-01 09:00:00" and span.finish.str == "2019-04-01 09:30:00")
	h.check("a value gathered from text keeps them too",
		read.start.str == "2019-04-01 09:00:00" and read.finish.str == "2019-04-01 09:30:00")
	h.check("a value between the ends is inside",
		span.contains(dates.DateTime.receive("2019-04-01 09:15:00")))
	h.check("both ends are inside", span.contains(evening) and span.contains(when))
	h.check("a value outside either end is not",
		not span.contains(dates.DateTime.receive("2019-04-01 08:59:59")) and
			not span.contains(dates.DateTime.receive("2019-04-01 09:30:01")))
	h.check("the same span written the other way round holds the same instants",
		dates.TimeSpan.receive("[2019-04-01 09:30:00, 2019-04-01 09:00:00]").contains(
			dates.DateTime.receive("2019-04-01 09:15:00")))
	h.check("a span of dates holds a day between them and their last day",
		twoDays.contains(dates.DateTime.receive("2019-04-02")) and
			twoDays.contains(dates.DateTime.receive("2019-04-03")) and
			not twoDays.contains(dates.DateTime.receive("2019-04-04")))
	h.check("a value of another kind is not asked about",
		span.contains(dates.DateTime.receive("2019-04-01")) isa error)
	h.check("nor is a text", span.contains("2019-04-01 09:15:00") isa error)
	h.check("a value that does not read is what the span says is wrong",
		dates.TimeSpan.receive("[2019-02-30, 2019-04-01]") isa error and
			dates.TimeSpan.receive("[the morning, 2019-04-01]") isa error)
end function
