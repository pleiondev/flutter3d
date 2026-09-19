# Running without a screen

An agent playing a game through an MCP server, or a farm of playtests running
in a container, need a game with no window and no GPU: a step, a way to save,
and answers in words and in data instead of a picture. `HeadlessRun` and
`HeadlessGame` are that vocabulary, shared across genres so a tool built
against one does not have to be rewritten for the next.

## Step 1: Implement the interface

A real game answers `step`, `save`, `outcome`, `position`, `eye`, `aim`, a
one-sentence `summary` and a `reading` as data. This page's walker is a toy
that stands in for one: it moves towards a target and reports `won` once it
gets there.

{{code run}}

## Step 2: Drive it with no renderer at all

Nothing here builds a scene to look at. The loop just calls `step` until the
outcome says the run is over.

{{code loop}}

## Step 3: Read the result as words and as data

The same run answers a sentence for a log and a map for a program, plus
whatever `save` would write to a file.

{{code report}}

This is the shape `bin/`'s own command line tool drives: it opens a real game
through `HeadlessGame.start`, and everything after that is exactly this loop.
