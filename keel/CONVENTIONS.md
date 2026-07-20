<!-- KEEL v0.1.1 — managed file. Do not edit here.
     Repo-specific rules go in the "## This repo" section of CLAUDE.md.
     Direct edits are overwritten on the next Keel upgrade. -->

# Working conventions

## Done means verified
A task is done when the tests pass, not when you say it is. If you cannot run
the tests, the task is not done — say so and stop.

The diff is the deliverable. A fix that exists only outside the repository
working tree — in the environment, the virtualenv, or any path that does not
survive the session — does not exist.

Report what you did NOT do as clearly as what you did. An unfinished task
reported honestly is a good outcome; an unfinished task reported as complete
is the worst one.

## Never
- Weaken a test to make it pass. Not the assertion, not the fixture, not the skip mark.
- Swallow an error to clear a failure.
- Delete or comment out code as a fix.
- Return a stub where real behaviour was asked for.
- Write secrets into any file, prompt, comment, or commit. They come from the
  environment. If a secret is missing, stop and say which one.
- Edit anything outside this repository.

## Searching
Use the Grep and Glob tools. They are ripgrep-backed and respect .gitignore.
Do not shell out to `grep -r`, `find`, or `ls -R` — on a large repo these read
far more than you need and cost context you will want later.
Read a file only when a match tells you it matters.

## Context
Every file you open stays in context for the rest of the session. Prefer the
narrow read: a matched line over a whole file, one file over a directory.
When you learn a durable fact about this repo, put it in CLAUDE.md rather than
re-deriving it next session.

## Reporting
Write the task report to the path given in the task spec. Structured, short,
and specific: what changed, what was verified and how, what was left undone
and why.
