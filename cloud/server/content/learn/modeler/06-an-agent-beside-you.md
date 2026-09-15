---
title: An agent beside you
summary: Case 1's own STL-to-GLB flow, redone by an agent over the real MCP tool surface on a document a person already has open — with a shared undo stack that will not let the agent take back a person's own step.
---

# An agent beside you

**What you have:** the modeler, running, with `teapot.stl` open — case 1's
own starting point. **What you want:** an agent, working beside you in the
same window, doing case 1's own five edits over MCP — while you keep your
own hands on the document too, and neither of you can undo the other's work
by accident.

This is screen 26, "Agent session": the tool-call feed, a history list with
"You"/"Agent" badges, undo restricted to the agent's own steps, and a
six-view contact sheet under the viewport. No new fixture geometry —
case 6 is entirely about *how* the work gets in, not what it is.

## 1. Start the agent's door

Launch the modeler with an MCP port open:

```
cd apps/flutter3d_modeler
flutter run -d macos --dart-define=mcpPort=0 -a --window=1440x900
```

`mcpPort=0` picks any free port rather than a fixed one. Once the document
finishes opening, the app writes `mcp-session.json` (in the platform's own
application-support directory) naming the port it bound and a token every
request must present — the file an agent's own MCP client reads to find and
authenticate to this exact running window. This is `ModelHttpServer.start`,
bound over **the same `ModelHistory` the app itself is already editing** —
not a second document, not a copy. `--mcp-port` in the plan's own shorthand
is this one flag; the app calls it `mcpPort` because it is read through
Dart's own `--dart-define`, not a separate command-line parser.

*(screenshot: the "Agent session" panel — tool-call feed, You/Agent history
badges, the six-view contact sheet — placeholder, see the note at the end of
this page. This screen has no implementation in this build yet; see that
note for why)*

## 2. The agent does case 1's own five steps — over the tool surface

An agent connecting to that port sees the same tools
`packages/flutter3d_model_mcp/test/tools_test.dart` already tests directly:
`list`, `rename`, `addMaterial`, `setMaterialField`, `assignMaterial`, and
the rest. Case 1's own five steps, run again, but this time as an MCP client
actually would — a tool name plus a JSON object, not a typed Dart
constructor:

```json
{"tool": "rename", "arguments": {"id": 1, "to": "teapot"}}
{"tool": "addMaterial", "arguments": {"materialName": "glazed ceramic"}}
{"tool": "setMaterialField", "arguments": {"index": 0, "field": "baseColor", "value": [0.92, 0.89, 0.82, 1.0]}}
{"tool": "setMaterialField", "arguments": {"index": 0, "field": "metallic", "value": 0.0}}
```

Underneath, each call reaches `modelCommandFromJson` — the exact reader the
project file and the recovery journal both use — and then
`session.run(command)`, recorded as `StepAuthor.agent`. The status line
reads the same after each call as it would after a person clicked the same
thing: `list` right after `rename` shows `1: "teapot" (mesh)`, and the
material count moves from 0 to 1 after `addMaterial`.

## 3. You, meanwhile, touch the same document

While the agent is mid-flow, you drag the roughness slider yourself, in the
same window, on the same object — say `0.35`, a touch glossier than the
`0.28` case 1 landed on. This lands on the identical `ModelHistory` the
agent's own tool calls are acting on (`ModelerCubit.run` calling
`now.history.run(command)` directly, no author named, which defaults to
`StepAuthor.person`) — not a merge, not a conflict dialog: one shared undo
stack, one step at a time, in whatever order the two of you actually work.

## 4. The agent finishes, and paints the teapot

```json
{"tool": "assignMaterial", "arguments": {"id": 1, "to": 0}}
```

The history now reads, top to bottom: your own roughness edit, sitting
between the agent's `setMaterialField(metallic)` and its own
`assignMaterial` — five agent steps and one of yours, six in total, none of
them undone yet.

## 5. Undo, restricted to the agent's own steps

Ask the agent to undo. It calls the `undo` tool — the same one `tools_test
.dart` exercises directly — which answers `undid assign a material`: its own
last step, taken back cleanly. Ask it to undo again, and it refuses, by
name:

```
the top step ("set roughness") is a person's own, not this session's — an
agent does not undo someone else's work
```

Your own roughness edit is untouched — the refusal changes nothing. This is
`ModelSession.undo`'s own real, working rule (`mcp-10n`), checked directly
rather than only asserted: it reads `history.topStepAuthor` before deciding,
and calls `history.undo(onlyIfAuthoredBy: StepAuthor.agent)`, which itself
refuses (returns `false`, changes nothing) the moment the top step's author
does not match. Your own ⌘Z, on the other hand, is not gated the same
way — the app's own `ModelerCubit` calls `ModelHistory.undo()` with no
restriction at all, and it would reach straight past the agent's steps *and*
your own, taking back whichever step is on top regardless of whose it was.
One shared stack, two different doors into `undo` — an agent's is narrower
than yours, on purpose.

---

Below is this exact mixed-authorship project, rendered headlessly through
`renderProject` — case 1's own teapot, the agent's own base colour and
metallic, your own roughness:

![The teapot after case 6's own mixed session — the agent's own base colour and metallic, the person's own roughness (0.35, not case 1's 0.28) — real geometry, real material, both authors' own edits landed on one project.](/assets/learn/modeler/an-agent-beside-you/02-final-material.png)

---

## Notes on this page

**Time to complete:** not recorded yet. `TODO`: a person should walk this
case by hand on a real machine and fill in a line here — "*n* minutes,
*date*, *machine*" — the way `rel-09`'s own cohort rows do. Nothing in this
session could actually run the desktop app, so no time is claimed.

**Screenshots.** One picture on this page is a placeholder — a plain colour
with "screenshot pending" on it, at `cloud/server/web/assets/learn/modeler/
an-agent-beside-you/01-agent-session-placeholder.png` — standing in for
screen 26's own "Agent session" panel. Unlike every earlier case's own
placeholders, this one is not only a screenshot this sandbox cannot take —
**the panel itself does not exist in this build yet.** Checked directly
while writing this case: `apps/flutter3d_modeler/lib/src/mcp_ui_tools.dart`
offers exactly the seven `ui.*` tools `mcp-16d` scoped (`setMode`,
`setSubmode`, `setTool`, `standardView`, `frameSubject`, `openDialog`,
`say`), and nothing in the app renders a tool-call feed, a "You"/"Agent"
history list, or the six-view contact sheet the design handoff's own screen
26 describes (`doc/design/modeler-handoff/README-дополнение.md`, row 26).
`--mcp-port` itself is real and working — this whole case ran over it — but
there is no live screen for it to show yet. This is `tut-16`
(`doc/modeler-tutorial-gaps.md`): a real, app-facing gap, not a screenshot
this sandbox merely failed to take. To replace the placeholder once screen
26 has a real implementation:

1. `cd apps/flutter3d_modeler && flutter run -d macos --dart-define=mcpPort=0 -a --window=1440x900`
2. `dart run tool/tutorial/bin/shoot.dart` against a scenario that opens the
   Agent session panel mid-way through this case's own steps, with at least
   one agent step and one person step visible in the history list.
3. Copy the PNG over the placeholder at the path above and remove this note.

**The tool-call layer, and why the journal it writes looks the way it
does.** Case 6's own fixtures (`packages/flutter3d_model_mcp/test/fixtures/
tutorial/case6_scenario.dart`) drive `modelTools.firstWhere(...).run(session,
arguments)` for every agent step — a JSON map in, an `Answer` out — rather
than constructing a `ModelCommand` directly the way cases 1–5 do. Underneath,
`model_tools.dart`'s own `_command` helper builds the exact same
`ModelCommand` through `modelCommandFromJson` and calls the exact same
`session.run`, so `case6.jsonl` is the same `CommandJournal` shape every
other case's `.jsonl` is — there is no second journal format here, only a
different door into writing the same one. The person's own roughness edit
runs directly against `session.history` instead, `ModelerCubit.run`'s own
door in the real app — and used to be *missing* from the journal for
exactly that reason: `ModelHistory.run` recorded to nothing of its own,
only `ModelSession.run`/`amend` ever touched a `CommandJournal`, so a step
that came in through the other door was not refused and not recorded,
simply not there. This was `tut-15` (`doc/modeler-tutorial-gaps.md`), a
quieter, more dangerous shape than case 2's own `tut-05` (which at least
*refused* rather than succeeding on the wrong answer) — a cold replay
looked entirely successful and silently reached a project whose roughness
read `SetMaterialField`'s own default (`0.5`), not the real `0.35`.
**Closed 2026-09-15, together with `tut-05`:** `ModelHistory` itself now
carries an optional recovery journal that `run`/`amend`/every transaction
record to on every success, regardless of which door the caller came in
through — the person's own edit records under `StepAuthor.person` the same
way a step from `ModelerCubit` always has, an agent's own tool calls keep
recording under `StepAuthor.agent` through `ModelSession.run` as before,
and `case6.jsonl` now carries the roughness line in between them, in the
order it actually happened.

**Undo restricted to the agent's own steps: real, and confirmed directly.**
This is the one part of this case that is not a gap. `ModelHistory.undo`
takes an optional `onlyIfAuthoredBy`, `ModelSession.undo` calls it with
`StepAuthor.agent` and checks `topStepAuthor` first to give the clear
refusal sentence quoted above, and `tutorial_scenarios_test.dart`'s own
case-6 group exercises exactly this: five agent tool calls around one direct
person edit, then the `undo` tool called twice — the first undoes the
agent's own last step, the second refuses by name, and the person's own
edit is confirmed untouched afterward. A final assertion in the same test
calls `ModelHistory.undo()` with no restriction — standing in for a
person's own ⌘Z in the real app — and confirms it reaches straight past the
same step the agent's own call had just refused. `mcp-10n`'s own row is
closed; case 6 exists to show it working on a real, mixed-authorship
document rather than only asserting it in isolation.

**Case 1's own import gap, re-checked and now closed.** `tut-01`'s own text
already flagged that case 6 would need to re-check whether an agent-driven
import needs `ImportOptions` sooner — it did, and the `import` tool now
takes them: `unit`, `upAxis`, and `weld`/`fixNormals`/`triangulate`, the
identical choice the app's own import screen offers a person. Case 6 still
starts from `case1ImportedProject()` (the same helper case 1's own fixture
uses, itself now built through `ModelSession.import` rather than around it)
rather than calling the `import` tool a second time here — this case is
about what an agent does to a document already open, not about repeating
case 1's own import step — so nothing on `case6.jsonl` or its fixtures
changes; only the tool's own reach did.

**Proving it.** `packages/flutter3d_model_mcp/test/fixtures/tutorial/
case6_scenario.dart` builds exactly the mixed-authorship project this page
describes, calling the real tool table for every agent step and
`session.history.run` directly for the one person step.
`tutorial_scenarios_test.dart`'s own case-6 group checks three things: a
cold replay of `case6.jsonl` now reproduces the person's own edit too
(`tut-15`, closed — confirmed by reading back the real roughness, `0.35`,
under `StepAuthor.person`, rather than the silent `0.5` default a build
before this fix landed on); building the scenario fresh over the real MCP
tool handlers reaches the exact project committed as `case6.f3dproj` and
exports the exact `case6.glb`, byte for byte; and the agent's own `undo`
tool refuses to reach past the person's own step while a raw,
unrestricted `ModelHistory.undo()` does not, confirming `mcp-10n`'s own
mechanism directly on this case's own mixed history rather than only
trusting its unit tests elsewhere.
