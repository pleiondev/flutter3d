/// What this server offers under `prompts/list` — `ux-44`.
///
/// **The tool table says what can be done; this says in what order.** An agent
/// that has never driven a modeller can read a hundred and fifty tool
/// descriptions and still start by extruding a face it has not looked at, then
/// export a project with two fatal issues in it, then be surprised. None of
/// that is in any one tool's description, because none of it is about one
/// tool.
///
/// **One prompt, no arguments.** A prompt with arguments is a tool wearing a
/// different hat, and there are plenty of tools. What is missing is advice.
library;

import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';

/// The advice, offered to every client that asks for it.
const List<OfferedPrompt> modelPrompts = <OfferedPrompt>[
  OfferedPrompt(
    name: 'modelling_strategy',
    description:
        'How to drive this editor without guessing: what to call first, '
        'when to look at a picture, and what to check before exporting.',
    text: _strategy,
  ),
];

const String _strategy = '''
You are driving a 3D modelling application over MCP. It has a document open,
an undo stack, and — sometimes — a person watching the same window. Work in
this order.

**Look before you edit.** `list` says what is in the project: every object
with its id, its parent, where it is, its version and how much topology it
has. `describe` says where each vertex, edge and face of one object is, which
way it faces and how big it is. Between them there is no reason to guess an
id. If you catch yourself picking a number because a cube has six faces, call
`describe` instead.

**Name what you are acting on.** Every command that would otherwise read the
selection takes a target: `object` with `faces`, `edges` or `vertices`, or
`ids` for whole objects. A named target leaves the person's own selection
alone, which matters when there is a person. `selectFacing` finds "the top" by
direction and `selectNear` takes a region, so neither is a number you invented.

**Render before and after a change you cannot predict.** `render` draws the
project from one of seven views; `renderSheet` draws several at once, which is
the cheaper way to see whether a shape is right. Use `mode: "normals"` to find
an inside-out shell and `mode: "selection"` to confirm you are about to edit
what you think you are.

**Adjust rather than re-do.** `amend` replaces the step on top of the undo
stack with a different version of the same command — that is how you try an
extrude at 0.3 after trying it at 0.5, without leaving both on the stack.
`undo` takes back your own last step and refuses to take back a person's.

**Group what belongs together.** `batch` runs several commands as one undo
step and takes the whole thing back if any of them refuses, so a person's ⌘Z
takes back the change you made rather than the last third of it.

**Use the recipes for the work that is the same every time.** `cleanup` welds,
drops degenerate faces and fixes winding across the whole project.
`makeGameReady` triangulates, recalculates normals and fits textures to a
profile. `buildFrom` builds a hierarchy of primitives in one step.

**Check before you export.** `check` says what is wrong with the project as an
export would see it; `export` refuses on a fatal issue unless you force it.
Fix what it names rather than forcing, unless the person asked for the file
regardless.

Distances are metres, angles radians unless a field says degrees, and the
world is Y-up. An argument this server does not take is refused by name — a
refusal about a key is a misspelling, not a project that would not cooperate.
''';
