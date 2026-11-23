// temporal.ms — the date, time and datetime types: what a fitting text means, and the
// calendar arithmetic a value the host cannot hold needs.
//
// The name is not the one the type suggests. The interpreter bundles its own date library
// as `dateTime`, and the logger imports it by that name; a file named `datetime.ms` in src/
// would answer that import on a filesystem that ignores case, which is what Windows has,
// and the logger would be handed this module instead. `temporal.ms` is a name the host
// cannot confuse it with.
//
// A field may be typed date, time or datetime, and a fact stores one as text in the one
// shape its type fixes:
//
//   2019-04-01             date
//   09:30:00               time
//   2019-04-01 09:30:00    datetime
//
// The shape is strict where the host's parser is not: _dateVal reads 3/15/2024 and
// 2021-02-30 alike, one loose and one impossible, so the calendar is counted here. The
// host's dates begin in 1970, so a date before that is counted here too, and one of those
// prints in its own shape and no other. A value that fits is a DateTime - the fact keeps
// the text, and this is what the text means:
//
//   import "temporal"
//   when = temporal.DateTime.receive("2019-04-01 09:30:00")
//   when.str("HH:mm")                                                // 09:30
//   when.addSeconds(90).str                                          // 2019-04-01 09:31:30
//   when.compare(temporal.DateTime.receive("2019-04-01 10:00:00"))   // -1
//
// How far one is from another is a TimeSpan, counted in the same wall-clock seconds:
//
//   start = temporal.DateTime.receive("2019-04-01")
//   finish = temporal.DateTime.receive("2019-04-03")
//   finish.since(start).days                                         // 2
//   finish.since(start).str                                          // 2d 00:00:00
//
// Both classes are this module's, so a module that imports it gets a copy, and a DateTime
// is `isa` another only when the same copy built both. schema.ms hands its own copy's
// reader on, which is why a caller reaches a date through schema.receive rather than
// importing this file beside it.
//
// knowledge.ms imports this file to check a typed field, and triples.ms imports it for the
// date its years-since constraint reads: the calendar is this module's rather than the
// host's, whose dates begin in 1970 and roll an impossible day forward like any other.

dateTypes = ["date", "time", "datetime"]

// ── The value ────────────────────────────────────────────────────────────────
// A DateTime is one of the three kinds: a count of seconds from a fixed base, the parts
// that count is written as, and whether the host can hold the value at all. `hosted` is
// what decides how it prints - the host formats a value it can hold in any shape asked
// for, while an older date is written from its own parts in the one shape its kind has.
//
// The base is 2000-01-01 for a date or a datetime and midnight for a time, so a time's
// count is its clock in seconds and its parts are the only date it has.

DateTime = {
	"kind": null,
	"value": null,
	"hosted": 1,
	"year": null, "month": null, "day": null,
	"hour": null, "minute": null, "second": null,
}

DateTime.formats = {
	"date": "yyyy-MM-dd",
	"time": "HH:mm:ss",
	"datetime": "yyyy-MM-dd HH:mm:ss",
}

// ── Reading one ──────────────────────────────────────────────────────────────
// Each kind has its reader, and receive is the one a caller uses: it takes the kind from
// the caller, or off the text's own punctuation when none is named, and hands the parts
// to make. So the shape is checked in one place and a value is built in one place.

DateTime.receive = function(text, kind=null)
	"Reads a date, time or datetime text into a DateTime, or says what is wrong with it."
	if not (text isa string) then return err("a date, time or datetime is text: " + str(text))
	if kind == null then kind = DateTime.kindOf(text)
	if kind == null then return err("not a date, a time or a datetime: " + text)
	if dateTypes.indexOf(kind) == null then return err("not a date, time or datetime type: " + kind)
	if kind == "date" then
		parts = DateTime.dateParts(text)
	else if kind == "time" then
		parts = DateTime.timeParts(text)
	else
		parts = DateTime.dateTimeParts(text)
	end if
	if parts isa error then return parts
	return DateTime.make(kind, parts)
end function

DateTime.kindOf = function(text)
	"Says which of the three a text is shaped like, or null when it is none."
	hasDate = text.indexOf("-") != null
	hasTime = text.indexOf(":") != null
	if hasDate and hasTime then return "datetime"
	if hasDate then return "date"
	if hasTime then return "time"
	return null
end function

DateTime.make = function(kind, parts)
	"Builds the value a kind's reader found: its count, its parts, and whether the host holds it."
	when = new DateTime
	when.kind = kind
	when.value = parts.value
	when.hosted = parts.hosted
	when.year = parts.year
	when.month = parts.month
	when.day = parts.day
	when.hour = parts.hour
	when.minute = parts.minute
	when.second = parts.second
	return when
end function

DateTime.dateParts = function(text)
	"Reads yyyy-MM-dd into its value and parts, or says how the text is not a date."
	pieces = text.split("-")
	if pieces.len != 3 then return err("a date is written yyyy-MM-dd: " + text)
	if pieces[0].len != 4 or pieces[1].len != 2 or pieces[2].len != 2 or
		not allDigits(pieces[0]) or not allDigits(pieces[1]) or not allDigits(pieces[2]) then
		return err("a date is written yyyy-MM-dd: " + text)
	end if
	year = val(pieces[0])
	month = val(pieces[1])
	day = val(pieces[2])
	if year < 1 then return err("there is no year " + pieces[0] + ": " + text)
	if month < 1 or month > 12 then return err("there is no month " + pieces[1] + ": " + text)
	if day < 1 or day > DateTime.daysInMonth(year, month) then return err("there is no such date: " + text)
	// The host is trusted with a date it can hold, so a value and its printout agree with
	// every other date the host knows. It begins in 1970, and an older date is counted
	// here instead: the same seconds-since-2000 base, from the civil calendar.
	value = _dateVal(text)
	hosted = 1
	if value isa error then hosted = 0
	if hosted and _dateStr(value, "yyyy-MM-dd") != text then hosted = 0
	if not hosted then value = (DateTime.daysFromCivil(year, month, day) - DateTime.epochDays) * 86400
	return {"text": text, "value": value, "hosted": hosted, "year": year, "month": month,
		"day": day, "hour": null, "minute": null, "second": null}
end function

DateTime.timeParts = function(text)
	"Reads HH:mm:ss into its value and parts, or says how the text is not a time."
	pieces = text.split(":")
	// To the second, so one clock time has one spelling: 09:30 and 09:30:00 would
	// otherwise be two values a unique(time) field could hold for the same subject.
	if pieces.len != 3 then return err("a time is written HH:mm:ss: " + text)
	secondText = pieces[2]
	if pieces[0].len != 2 or pieces[1].len != 2 or secondText.len != 2 or
		not allDigits(pieces[0]) or not allDigits(pieces[1]) or not allDigits(secondText) then
		return err("a time is written HH:mm:ss: " + text)
	end if
	hour = val(pieces[0])
	minute = val(pieces[1])
	second = val(secondText)
	if hour > 23 then return err("there is no hour " + pieces[0] + ": " + text)
	if minute > 59 then return err("there is no minute " + pieces[1] + ": " + text)
	if second > 59 then return err("there is no second " + secondText + ": " + text)
	return {"text": pad2(hour) + ":" + pad2(minute) + ":" + pad2(second),
		"value": hour * 3600 + minute * 60 + second, "hosted": 1,
		"year": null, "month": null, "day": null,
		"hour": hour, "minute": minute, "second": second}
end function

DateTime.dateTimeParts = function(text)
	"Reads yyyy-MM-dd HH:mm:ss into its value and parts, or says what is wrong."
	at = text.indexOf(" ")
	if at == null then return err("a datetime is written yyyy-MM-dd HH:mm:ss: " + text)
	date = DateTime.dateParts(text[:at])
	if date isa error then return date
	clock = DateTime.timeParts(text[at + 1:])
	if clock isa error then return clock
	stamp = date.text + " " + clock.text
	hosted = date.hosted
	if hosted then
		value = _dateVal(stamp)
		if value isa error then return err("not a date and time: " + stamp)
		// The same reading back, for the same reason: a clock time a daylight-saving jump
		// skips is not the time it was written as.
		if _dateStr(value, "yyyy-MM-dd HH:mm:ss") != stamp then
			return err("there is no such date and time: " + stamp)
		end if
	else
		value = date.value + clock.value
	end if
	return {"text": stamp, "value": value, "hosted": hosted, "year": date.year,
		"month": date.month, "day": date.day, "hour": clock.hour, "minute": clock.minute,
		"second": clock.second}
end function

// ── Asking one ───────────────────────────────────────────────────────────────

DateTime.defaultFormat = function
	"The one shape this value's kind is written in."
	return DateTime.formats[self.kind]
end function

DateTime.str = function(format=null)
	"Formats the value; a time reads from the epoch's midnight, so HH:mm:ss is its clock."
	shape = self.defaultFormat
	if format == null then format = shape
	// The host counts from 1970, so an older date is printed from its own parts, in the
	// one shape its kind writes.
	if not self.hosted then
		if format != shape then
			return err("a date before 1970 prints as " + shape + ", not '" + format + "'")
		end if
		return self.textAt(self.value)
	end if
	return _dateStr(self.value, format)
end function

DateTime.addSeconds = function(seconds)
	"A new value this many seconds later; a time wraps around midnight, a date keeps its day."
	if not (seconds isa number) then return err("addSeconds needs a number of seconds: " + str(seconds))
	if self.kind == "time" then
		shifted = (self.value + seconds) % 86400
		if shifted < 0 then shifted = shifted + 86400
		return DateTime.receive(_dateStr(shifted, "HH:mm:ss"), "time")
	end if
	// The result may be a date the host cannot print, either because it is older than 1970
	// or because the step crossed back before it, so the count it holds is written out here
	// when the host has nothing to say.
	total = floor(self.value + seconds)
	stamp = _dateStr(total, self.defaultFormat)
	if stamp == "" then stamp = self.textAt(total)
	return DateTime.receive(stamp, self.kind)
end function

DateTime.compare = function(other)
	"Orders two values of one kind: -1, 0 or 1, or an error when the kinds differ."
	if not (other isa DateTime) then return err("compare needs another date, time or datetime")
	if other.kind != self.kind then
		return err("cannot compare a " + self.kind + " with a " + other.kind)
	end if
	if self.value < other.value then return -1
	if self.value > other.value then return 1
	return 0
end function

DateTime.since = function(other)
	"The TimeSpan from other to this value, or an error when they are not of one kind."
	return TimeSpan.between(other, self)
end function

DateTime.textAt = function(value)
	"A text for a value the host cannot print, written from its count of seconds since 2000."
	days = floor(value / 86400)
	day = DateTime.civilFromDays(DateTime.epochDays + days)
	stamp = pad4(day.year) + "-" + pad2(day.month) + "-" + pad2(day.day)
	if self.kind == "datetime" then stamp = stamp + " " + clockText(value - days * 86400)
	return stamp
end function

// ── The calendar ─────────────────────────────────────────────────────────────
// The host's dates begin in 1970 and its parser is loose, so the calendar a value is
// counted on is here, as the era arithmetic of the civil calendar: a date's parts are read
// by counting days from 1970-01-01, and the value's own base is the host's, 2000-01-01.

DateTime.epochDays = 10957

DateTime.daysInMonth = function(year, month)
	"How many days a calendar month has, February counting its leap day."
	if month == 2 then
		if DateTime.leapYear(year) then return 29
		return 28
	end if
	if month == 4 or month == 6 or month == 9 or month == 11 then return 30
	return 31
end function

DateTime.leapYear = function(year)
	"Every fourth year, but not every hundredth, except every four hundredth."
	if year % 4 != 0 then return false
	if year % 100 != 0 then return true
	return year % 400 == 0
end function

DateTime.daysFromCivil = function(year, month, day)
	"Days from 1970-01-01 to a calendar date, in the era arithmetic of the civil calendar."
	y = year
	if month <= 2 then y = y - 1
	era = floor(y / 400)
	yoe = y - era * 400
	marchMonth = month - 3
	if month <= 2 then marchMonth = month + 9
	dayOfYear = floor((153 * marchMonth + 2) / 5) + day - 1
	dayOfEra = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + dayOfYear
	return era * 146097 + dayOfEra - 719468
end function

DateTime.civilFromDays = function(days)
	"The calendar date a count of days from 1970-01-01 falls on."
	z = days + 719468
	era = floor(z / 146097)
	doe = z - era * 146097
	yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
	year = yoe + era * 400
	doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
	mp = floor((5 * doy + 2) / 153)
	day = doy - floor((153 * mp + 2) / 5) + 1
	month = mp + 3
	if mp >= 10 then month = mp - 9
	if month <= 2 then year = year + 1
	return {"year": year, "month": month, "day": day}
end function

// ── TimeSpan ─────────────────────────────────────────────────────────────────
// How much time passed between two DateTimes of one kind, counted in the same wall-clock
// seconds their values hold: two dates differ by whole days, two clock times by their
// distance within a day, and two datetimes by the seconds between them. A bare time has no
// day, so a span over midnight is the difference of the two readings rather than a step
// through the night. A span is signed: the earlier to the later is positive.

TimeSpan = {"seconds": 0}

TimeSpan.between = function(start, finish)
	"The span from start to finish, or an error when they are not DateTimes of one kind."
	if not (start isa DateTime) or not (finish isa DateTime) then
		return err("a span is between two dates, times or datetimes")
	end if
	if start.kind != finish.kind then
		return err("cannot measure from a " + start.kind + " to a " + finish.kind)
	end if
	span = new TimeSpan
	span.seconds = finish.value - start.value
	return span
end function

TimeSpan.str = function
	"Reads as a duration: 2d 03:04:05, or 00:00:30 under a day, with a leading '-' when negative."
	sign = ""
	size = self.seconds
	if size < 0 then
		sign = "-"
		size = -size
	end if
	size = floor(size)
	days = floor(size / 86400)
	clock = clockText(size - days * 86400)
	if days == 0 then return sign + clock
	return sign + days + "d " + clock
end function

TimeSpan.whole = function(unit)
	"How many whole units of unit seconds the span holds, rounded toward zero."
	count = self.seconds / unit
	if count < 0 then return ceil(count)
	return floor(count)
end function

TimeSpan.minutes = function
	"Whole minutes in the span, rounded toward zero."
	return self.whole(60)
end function

TimeSpan.hours = function
	"Whole hours in the span, rounded toward zero."
	return self.whole(3600)
end function

TimeSpan.days = function
	"Whole days in the span, rounded toward zero."
	return self.whole(86400)
end function

// ── Text ─────────────────────────────────────────────────────────────────────
// The width a part is written in, the digit check the readers make, and a clock read from
// a count of seconds into a day, which both a datetime's printout and a span's ask for.

allDigits = function(text)
	"Says whether every character is a decimal digit, and there is at least one."
	if text.len == 0 then return false
	for c in text
		if "0123456789".indexOf(c) == null then return false
	end for
	return true
end function

pad2 = function(n)
	"Two digits, the width a time's parts are written in."
	text = str(n)
	if text.len >= 2 then return text
	return "0" + text
end function

pad4 = function(n)
	"Four digits, the width a year is written in."
	text = str(n)
	while text.len < 4
		text = "0" + text
	end while
	return text
end function

clockText = function(seconds)
	"HH:mm:ss for a whole number of seconds into a day."
	seconds = floor(seconds)
	return pad2(floor(seconds / 3600)) + ":" + pad2(floor((seconds % 3600) / 60)) + ":" +
		pad2(seconds % 60)
end function
