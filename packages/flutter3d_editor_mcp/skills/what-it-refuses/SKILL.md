---
name: what-it-refuses
description: Use when a call to the flutter3d editor's MCP server comes back as an error, or when planning work around it — every refusal it can give, what it means, and which ones are decisions rather than gaps.
---

# Every refusal, and what to do about it

A refused call comes back as a tool result marked as an error, with a sentence
in it, and **nothing was changed**. It is not a broken server: the editor answers
"no" to questions that have that answer, because a caller who has to catch
something to find out is a caller who will eventually catch it in the wrong
place.

| The answer | What it means | What to do |
|---|---|---|
| `there is no brush 40 — call list` | The index is not in that list | `list`, then select something that is there |
| `nothing did resize by …: light 0 · point` | The verb does not apply to what is selected | Select a brush; `resize` is brushes only |
| `nothing did …: nothing selected` | No selection at all | `select` first |
| `moveBy cannot be read from those arguments` | The argument shape is wrong | Read the schema `tools/list` gave for that tool |
| `… was written by tool/make_templates.py` | A generated document | `save` to another path |
| `nothing to undo` / `nothing to redo` | The stack is at one end | Nothing; this is information |
| `this server cannot draw` | `screenshot` | Read the level with `list` and `validate` |

## The four that are decisions and will not be fixed

**It will not overwrite a generated document.** A file with `generatedBy` in it
belongs to the tool that wrote it, and CI re-runs every one of those generators
and diffs the result. A save that succeeded would look like work saved right up
until the next run threw it away. Saving elsewhere is allowed and the copy claims
itself.

**It will not draw.** `screenshot` is offered and refuses with its reason, which
is a fact about this repository rather than an unfinished feature: every backend
here reaches a `GraphicsDevice` whose finished frame is a Flutter widget, so a
process that can render a level is a Flutter process — and `dart run`, which is
how this server starts, cannot resolve a package that depends on the Flutter SDK.
The tool exists rather than being absent so that the reason is an answer; an
agent that finds no such tool concludes the server is incomplete and goes looking
for another way.

To look at a level, open it in `apps/flutter3d_editor`. To find out whether it is
*correct*, `validate` is what this process has instead, and it is the better
question anyway.

**It will not open a second document.** One level per process, given on the
command line. An editor that could swap the document underneath itself would be
left holding sixty-four snapshots of a file it is no longer editing, every one of
which restores cleanly. Two levels means two processes, which costs nothing.

**It will not invent an entity's insides.** `place` copies the last thing of that
type the document already contains. The editor has no vocabulary of its own — it
cannot know what a `door` or a `lift` needs written on it — so a type the level
has never used is placed bare and may not work in the game. Add one to the
document by hand first, or copy an existing one and change it with `setField`.

## The one that is a gap

**A value the level format cannot read is refused by `setField`**, and the answer
says the call did nothing but not which field was wrong. The reader that rejects
it is `Level.fromJson`, which throws on the whole document rather than reporting a
key. Nothing is written and nothing is corrupted; finding out *why* means reading
the format. That is a smaller problem than a tool that writes documents which do
not load, which is what the alternative would be.
