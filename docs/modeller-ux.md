# The modeller — design and UX decisions

Companion to `docs/modeller.md`, which catalogues *what exists*. This
document is about *why it looks and behaves the way it does* — the
decisions, and the reasoning behind them, as recorded in the code's own
comments (not paraphrased from memory: every claim below traces to a
specific file). Where a decision was later reconsidered, that reversal is
kept in, because it is usually more informative than the decision itself.

## 1. Where the shape came from

The modeller's screen layout traces to a "3D editor with Material Design"
handoff archive — a handoff README, 19 numbered screens, a four-phase
development plan (`doc/model-editor.md:3-12`). The 19 screens are still
the app's own organizing unit: comments throughout the UI code cite a
screen number (`screen 26`, "Agent session") the way a design system cites
a component name. Four phases, still visible in `ModelerMode`'s own
`phase` field (§4): phase 1 is Object/Mesh, phase 2 is Material/Scene,
phase 3 is Animation, phase 4 (UV, Sculpt, Render) is declared but not
built.

Underneath the screens, the modeller deliberately reused a shape the level
editor (`apps/flutter3d_editor`) had already arrived at, rather than
reinventing one (`doc/model-editor.md:94-129`): a command as a value with
a human-readable `says` sentence; history with transactions (one undo step
per drag, not per pointer event); an inspector built from *hints*
describing a control rather than hard-coding one; a Cubit/State split
where the 60fps viewport's own camera and gizmos never go through the
Cubit; and MCP as a second, equally real user of the same command table a
keyboard shortcut uses. What was deliberately **not** reused: the level
editor's `Piece`/`Editing` types, because a level document and a model
document are different enough things that sharing one class for both was
judged the specific mistake worth avoiding.

## 2. Visual language

`apps/flutter3d_modeler/lib/src/ui/theme.dart` states every colour as a
literal hex rather than deriving one:

> "An explicit `ColorScheme.dark` and not `ColorScheme.fromSeed`. A seed
> generates thirty roles from one colour, and the generator is free to
> change what it generates between Flutter versions: a design that was
> signed off then arrives a shade different after an upgrade, and nobody
> can say which of the thirty moved."

The chrome's own palette is built outward from colours the viewport
already draws with — `#0E1112` behind the model, `#2A3234`/`#3D4A4D` for
grid lines, `#FF9926` for a selected mesh element — "so that the chrome
and the picture belong to one palette" (theme.dart:10-14). The full token
table is owned by the design hand-over outside this repository; where the
two disagree, the hand-over wins and this file is the place to fix.

Sizes are the same kind of decision: `ModelerMetrics` is a set of named
constants (`topBar = 52`, `rail = 52`, `propertiesMin/Max = 250/330`,
`statusBar = 30`, …) rather than numbers repeated at call sites, because
the acceptance criterion for the layout is a measurement, and a literal
copied into both the widget and its test can drift without either side
noticing (theme.dart:24-28). A `railButtonWidth` of 40 is kept apart from
`railButton`'s own 36 specifically because widening every `IconButton` in
the app to match one rail was never asked for — a narrowly scoped
exception, not a renamed constant (theme.dart:60-69).

**Status has three tones, and the move from two to three is recorded as a
deliberate change of mind** (`status_line.dart:9-16`):

> "This used to colour only a refusal, on the reasoning that a bar which
> turns orange whenever anything at all is imperfect is a bar people stop
> reading. That reasoning is right about a bar with two states and wrong
> about the model: a quad that the exporter will cut and an object that
> will not load are different news, and flattening them meant the first
> was invisible until somebody opened the export dialogue."

`quiet` (nothing wrong — narrates the last action), `warn` (will export,
someone will be disappointed by it), `refuse` (will not export at all) —
each colour means exactly one thing, and the budget-warning card's own
background/text colour (`tertiaryContainer`/`onTertiaryContainer`) is
called out in the theme file as taken from the hand-over verbatim, not
improvised (theme.dart:241-245).

A smaller, deliberately low-tech typographic decision: large numbers in
the status line are grouped with a literal U+2009 thin space rather than
pulled in through `intl`'s locale-aware `NumberFormat`, because that
package arrives with the whole interface's own localization pass and
taking a dependency now for one call site "would be a dependency taken for
a tenth of what it does" (`status_line.dart:44-53`).

## 3. One properties panel, replaced wholesale

The properties panel does not accumulate controls as a mode adds them —
it swaps its whole content per mode, keeping only what genuinely applies
everywhere (`properties_panel.dart:141-146`):

> "Object mode wants the object list, the transform grid and the modifier
> stack; mesh mode wants the last-operation card and the selection
> summary. Display/View/Budget are cross-mode utility — the camera and the
> export budget mean the same thing regardless of what is being edited —
> so they stay in every mode rather than disappearing along with the
> mode-specific sections."

This is a real, stated design rule — "content replaced wholesale," in
`properties_sections.dart`'s own words — not an emergent property of the
code. Its one currently unresolved edge: `Material` mode is a real,
`ready: true` button in the mode switcher, but has no panel of its own
yet (`properties_sections.dart:56-61`). The comment names this explicitly
as an interim decision rather than an oversight — phase 1's own "clean a
mesh, fix its material, export to GLB" scenario needed *some* way to paint
an object before a dedicated `Material` workspace existed, so material
editing was left under Object mode for now, and the `Material` button
switches modes cleanly into a screen with nothing on it. A person clicking
`Material` expecting material controls needs to know to go back to
`Object` instead — a genuine, named UX debt (see `docs/modeller.md` §20
for the equivalent functional framing).

## 4. Three shells, one layout classifier

`LayoutClass.of(width)` (`layout_class.dart:41`) buckets a window into
`phone` (<600), `tablet` (<1200), or `desktop`, with named, hard-coded
thresholds rather than a device-detection heuristic — deliberately, for
stable classification across a resize. All three shells are built and
wired (`shell_for_width.dart`): `ModelerShell` (desktop), `
ModelerTabletShell`, `ModelerPhoneShell`.

The tablet and phone shells are not the desktop shell with things hidden
— each re-solves the same problem for its own hand and screen:

- **Tablet**: the tool rail narrows to 48px ("a tablet's own hand does not
  need the desktop's full 52 to land a tap," `theme.dart:41-42`); the
  properties panel becomes a 200px bottom sheet with a drag handle,
  keeping access rather than removing it.
- **Phone**: mode-switching moves to a bottom `NavigationBar` (only four
  of the eight `ModelerMode` values fit — `kPhoneModes` drops `animation`
  even though it is `ready`, tools.dart:101); every tool on the current
  mode's rail collapses into one FAB sized for a thumb (56px) that opens
  the same tool table as a sheet, shorter still (130px) than the tablet's
  own.

## 5. The operation card: adjusting, not redoing

`OperationCard` (`operation_card.dart:1-18`) is the panel's own
"just did this, still editable" affordance — a distinct visual container
("not a section that reads like every other one... the whole point is
that a person can tell at a glance 'this is still editable' apart from
'this is just information'," operation_card.dart:167-170) showing the
last command's own numeric arguments as live fields and, where a
parameter has a bounded range, a slider beside the field.

Two decisions worth naming:

- **Adjusting a number re-runs `amend`, not a second command.**
  Dragging the slider sixty times during one gesture is sixty
  re-applications of the same step against the document as it was
  *before* that step, not sixty pushes onto the undo stack — the stack
  does not grow and the model does not flicker through an intermediate
  state (operation_card.dart:4-11).
- **Dismissing the card's own detail is not undo.** A ✕ on the card
  collapses its own display; nothing about the step it describes changes
  on the history stack. This is local widget state (`_dismissed`, a
  `StatefulWidget` for exactly this one reason), reset only when a
  genuinely new command lands on top — dismissing should not also hide
  the next command's own card (operation_card.dart:28-36, 70-77).

## 6. Command-as-a-value: one list, four readers

Every edit in this application is a `ModelCommand` with a name, a `says`
sentence, and a JSON `arguments` map — and that single list feeds four
different surfaces without any of them re-describing the vocabulary
themselves:

- The **status line** narrates `command.says` after it runs.
- The **operation card** reads `command.arguments`/`command.hints` to
  build its own editable fields.
- **Keyboard shortcuts** (`ModelerKeys`, `modeler_keys.dart:1-8`) use
  `Shortcuts`/`Actions` rather than a raw keyboard listener specifically
  so a person typing `1.5` into a number field never fires the `1` key's
  own vertex-level shortcut — Flutter's own focus system already knows
  the difference between a keystroke aimed at a text field and one aimed
  at the shell. Crucially, the shortcut table is built from **the same
  table the rail reads** (`toolsFor`), "so a key that arms nothing is a
  key nobody wrote down twice."
- The **MCP tool table** builds each tool's schema from the same command,
  so an agent and a person's keyboard describe the same action through
  the same words.

The practical payoff: there is no separate place where "what does `2`
extrude do" or "what does the extrude tool's status message say" could
drift from what the command itself actually does, because none of these
surfaces hard-code a description — they all read the command.

## 7. Undo as a shared, authored stack

Undo is one stack, not two — an agent's tool calls and a person's own
edits interleave on the identical `ModelHistory`, in whatever order they
actually happened. The UX decision on top of that shared stack is
asymmetric by design: a person's ⌘Z reaches straight past anyone's last
step regardless of author, but an agent's own `undo` tool call is refused
the moment the top step was not the agent's own
(`ModelHistory.undo(onlyIfAuthoredBy:)`, `history.dart:427-440`) — a
narrower door for the agent than for the person, on purpose (see
`docs/modeller.md` §2 for the mechanism). The **Agent Session panel**
surfaces this as a visible trust boundary rather than a silent rule: a
history list with "You"/"Agent" badges, and an "Undo agent steps" button
that is only enabled while the top step is the agent's.

## 8. The Agent Session panel: additive, and honest about what it shows

`AgentSessionPanel` is **appended after** the ordinary properties panel
whenever `--mcp-port` is open, never replacing it
(`agent_session_panel.dart` — see `docs/modeller.md` §4). This is itself
a UX statement: watching an agent work is something added to a person's
own workspace, not a mode the person's own tools disappear into.

The panel's own **contact sheet** is the more interesting design choice.
It is explicitly *not* a live multi-angle camera feed — nothing in the
application renders more than one view at a time outside the `render`/
`renderSheet` tools themselves. Rather than fake a live rig, the panel
shows the actual pictures those two tools drew during the session, most
recent first, captioned with whatever view was asked for. The panel's own
library comment frames the choice directly: this is "real answers an
agent received," not "a camera rig standing by for a call that may never
come." Given a choice between a more impressive-looking but synthetic
feature and an honest record of what actually happened, the honest record
won.

## 9. Background jobs stay presentational

`JobButton` (`job_button.dart:1-9`) is the visible half of a background
bake (LOD regeneration, cloth simulation, weight computation): idle shows
a labelled button, running shows a progress indicator with a cancel
affordance, and that is the entire widget's own state. Where the job
actually runs, what its progress means, and what happens when it finishes
all live in `ModelerCubit` — the same split every other control in the
shell keeps (`status_line.dart` reads readiness rather than computing it;
this button reads `ModelerReady.jobs` rather than owning a job). The
payoff of keeping this split rigid across the whole shell: a widget test
can build any of these controls alone, handing it whatever state it wants
to assert against, without also standing up the cubit that would normally
produce that state.

## 10. Crash and recovery: promise first, then explain

`CrashDialog` ("Something went wrong," `crash_handling.dart:118-188`) is
shown only *after* an emergency autosave has already been attempted, on
purpose — "so the message can promise it happened rather than ask
somebody to wait for it." The dialog's own body is three pieces, in
order: what happened (a plain sentence, not an apology), the raw error,
and up to the last 20 commands run before it — "everything that landed
before the one that did not," enough to read what led up to a crash
without pasting a whole session's editing history into a bug report
(`kCrashLogCommandCount`, crash_handling.dart:28-31). "Report a problem"
prefills a browser form with exactly that same text — the dialog and the
bug report describe the crash identically, because both read the same
`CrashReport.describe()`.

`RestoreAutosaveDialog` ("предложение восстановить" — the offer to restore,
on a session that did not close cleanly) makes a smaller but pointed
choice: it names **how many objects** the autosave would bring back,
rather than only that something was found (`restore_autosave_dialog.dart:1-3`)
— a concrete number over a vague confirmation, the same instinct as the
status line's three tones over two: don't make a person guess how much is
actually at stake in a choice.

## 11. Two languages, on purpose, for two audiences

The interface itself ships bilingual (Russian and English,
`AppLocalizations` — the `RestoreAutosaveDialog`/`CrashDialog` split above
is also a localization split: the recovery dialog is localized, the crash
dialog reads a raw, unlocalized English error and command trail).
`ModelerCubit.say(...)`, the status-line sentence machinery, is documented
as staying English regardless of interface locale — "that is the
diagnostic language this repository already uses in core and MCP, not the
interface language" (`app_wiring.dart`). The boundary is drawn at
audience, not at feature: what a person reads as interface chrome is
localized; what either a person or an agent reads as a diagnostic sentence
about the document itself is not, because the MCP surface an agent reads
never localizes, and a status message that changed wording depending on
interface locale would be a message two different debugging sessions
could no longer compare.

## 12. Accessibility as a recurring, named pass

A specific accessibility distinction — tagged `ui-23` — recurs across at
least five files (`undo_redo_buttons.dart`, `shell.dart`, `shell_phone.dart`,
`top_bar_actions.dart`, and others): `Tooltip.message`/`IconButton.tooltip`
sets a control's `SemanticsNode.tooltip`, not its `.label` — a screen
reader announcing a button reads the label, not the tooltip, so a button
whose only text is its tooltip string reads as silent to a screen reader
despite looking labelled to a sighted person. The fix pattern, repeated
identically at each call site: wrap the control in `MergeSemantics` around
an explicit `Semantics(label: ..., button: true, child: ...)`, folding a
real label onto the button's own actually-tappable node
(`operation_card.dart:118-121` is one instance among several). This is
treated as a pass applied consistently across the shell, not a one-off
fix — the same comment, verbatim in intent, appears wherever an icon
button's only visible text was a tooltip.

A second accessibility detail, narrower but concrete: `OperationCard`'s
own slider gives a `semanticFormatterCallback` reading `'$label
${NumberField.show(v)}'`, because a bare slider announces only a raw
number to a screen reader and has no adjacent label the way a
`NumberField` does to fall back on (operation_card.dart:217-223) — the
slider's accessible name is manufactured at the one call site that needs
it, rather than left to whatever Flutter's default slider semantics would
say.

## 13. The tutorial pages are the UX documentation that ships

`cloud/server/content/learn/modeler/*.md` (six cases) are not a separate
marketing or onboarding artifact bolted on afterward — they are written
to walk the exact screens and MCP calls a person or an agent would
actually use, and their own "Notes on this page" sections are honest
about what is still a placeholder screenshot versus what has a real one,
naming the exact regeneration steps rather than leaving a stale picture
unremarked. Case 6 in particular ("An agent beside you") is built entirely
around demonstrating the shared-undo/authorship design from §7 on a real,
mixed-authorship document rather than only asserting the mechanism exists
— screen 26's own tool-call feed and history badges, driven by an actual
five-agent-step-plus-one-person-step session, with the agent's own
`undo` call refused by name mid-page. Several real UI/engine bugs were
found and fixed specifically *because* someone tried to walk these pages
literally (the mirror modifier's `bisect`/`flipUv` requirement, the
`baseColor` RGBA shape, a `lockFeet` crash on a real rig, a cold-replay
gap that silently dropped a person's own edit from the journal) — the
tutorials function as an ongoing UX/correctness test as much as
documentation.

## 14. Known UX rough edges

Distinct from `docs/modeller.md`'s functional gap list — these are about
how something *feels*, not what is missing outright:

- **`Material` mode is a dead end** (§3): a real, enabled button that
  switches cleanly into an empty panel. The functioning material editor
  is one click away, under `Object` mode, with no signpost pointing there.
- **The properties panel's per-object keys used to collide.** Four
  different widgets sharing one object's identity as their own `Key`
  (rather than each carrying a role-qualified key) went unnoticed until a
  live MCP session hit the exact frame where three sections all inserted
  at once — a framework-level crash, not a refused command, so nothing
  about it looked like a bug in the UI's own logic until it was
  reproduced headlessly. Fixed; kept here as a reminder that this
  panel's per-mode wholesale-replacement design (§3) makes simultaneous,
  multi-section insertions a real and recurring shape, worth keeping an
  eye on wherever a new section is added with its own per-object key.
- **Tablet and phone shells are less exercised than desktop.** Both are
  fully built and wired, not a stub, but the bulk of live, hands-on
  walkthroughs (the tutorial pages, this session's own screenshot work)
  happened at desktop width; a tablet/phone-specific rough edge is more
  likely to still be waiting to be found than a desktop one.
- **`renderSheet`'s own name invites the wrong expectation.** Tutorial
  prose describing the Agent Session panel's contact sheet (§8) has, at
  least once, described a hypothetical "six-camera rig" the actual
  `renderSheet` tool does not provide (it draws a 2×2 sheet — front,
  right, top, iso). The panel's own honesty about "real answers, not a
  live camera rig" (§8) is itself partly a response to that gap between
  what the name suggests and what the tool draws.
