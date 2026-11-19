// prompt.ms — the part of the session at the prompt that knows nothing about the domain.
//
// The prompt is one loop over one record, and most of what it does would serve any
// knowledge base: reading a line, painting it, counting what is held, and keeping a data
// file whole across a save. This module is where that part is being gathered. repl.ms keeps
// the verbs the domain adds - what a fact is, what a question means, which file each
// component lives in - and reaches these by way of the session:
//
//   import "prompt"
//   session = {"prompt": globals["prompt"], ...}
//   problem = session.prompt.writeLines(path, lines)
//
// Like triples.ms and rule.ms, it is handed to the session rather than imported by
// repl.ms, for the same reason: a bare import resolves against the entry script's folder,
// so repl.ms would find the suite's own module of the same name instead of the one beside
// it. Nothing here holds a class, so a copy of this module is only a copy of its functions.
//
// What is here so far is the file-safe save and the word for a count. The loop, the talk
// with the reader, and the slash commands are still in repl.ms, and move here next, so that
// a session becomes this module plus whatever a host adds to it.

// ── Counting ─────────────────────────────────────────────────────────────────

countText = function(count, singular)
	"Says '1 rule' or '2 rules'."
	if count == 1 then return "1 " + singular
	return str(count) + " " + singular + "s"
end function

// ── Writing a data file ──────────────────────────────────────────────────────
// A save writes a temp file and swaps it in, so the file that is already there is only
// replaced once the new one is whole: a save that fails part way through leaves the
// domain's facts.kb as it was rather than truncated to nothing. Only a file the save
// wrote itself is ever removed, and a swap that cannot put the old copy back says where
// it was left.

writeLines = function(path, lines)
	"Replaces the file at path with these lines, or returns an error."
	temp = path + ".tmp"
	problem = writeFresh(temp, lines)
	if problem != null then return problem
	problem = swapIn(temp, path)
	// A temp file is swept up only once the save has finished writing it, which is what
	// makes it this save's own to remove: what went wrong with the save is already the
	// answer, so the sweep's own failure has nowhere to go. Nothing else is ever cleared,
	// so a folder called facts.kb.tmp outlives a save that could not start.
	if problem != null then leftover = file.delete(temp)
	return problem
end function

writeFresh = function(path, lines)
	"Writes the lines to a new file at path, or returns an error, taking away the part-written file it made."
	handle = file.open(path, "w")
	if handle isa error then return handle
	for line in lines
		problem = handle.writeLine(line)
		if problem isa error then
			handle.close
			// The open worked, so the file at path is this write's own and a part-written
			// temp file must not be left to be taken for a whole one later. An open that
			// failed returns above, leaving whatever is at path alone.
			leftover = file.delete(path)
			return problem
		end if
	end for
	handle.close
	return null
end function

swapIn = function(temp, path)
	"Puts the finished temp file where the old file was, moving the old one aside until the new one is there."
	if not file.exists(path) then return moveFile(temp, path)
	// Windows will not move a file onto one that exists, so the old file is moved aside
	// first and put back if the new one cannot take its place: at no point is there no
	// copy of what the session started with.
	old = path + ".old"
	// A copy left by an interrupted swap is cleared so the old file can go there, but
	// only a file is one of ours: a folder named facts.kb.old is left where it is, and
	// the move below then fails with nothing lost.
	if file.exists(old) and file.info(old).isDirectory == 0 then leftover = file.delete(old)
	problem = file.move(path, old)
	if problem isa error then return problem
	problem = moveFile(temp, path)
	if problem == null then
		leftover = file.delete(old)
		return null
	end if
	// The old file goes back where it was, so the session still has what it started with.
	// If even that cannot be done, path is empty and the copy is at old, so the error says
	// where to find it rather than only why the move failed.
	restored = file.move(old, path)
	if restored isa error then return err(problem.message + "; the copy it replaced is at " + old)
	return problem
end function

moveFile = function(from, to)
	"Moves a file, answering an error or null, since file.move does not answer null on success."
	problem = file.move(from, to)
	if problem isa error then return problem
	return null
end function
