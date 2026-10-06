## Unreleased

- **`play_events` hears what the running game says about itself.** A level
  loaded, the player died or came back, a pickup taken, the way out
  reached: whatever the game posts with `postGameEvent`, in order, each
  with a sequence number, kind, time and data. An agent passes back the
  `next` it was given and sees nothing twice and skips nothing, through a
  `play_stop` and a `play` as well; `kinds` narrows it, and `missed` says
  when more was posted than was kept before it asked.

- **`generate_level`** replaces the open level with one made from a seed
  and rules.

- **`screenshot` takes a `debugView`**, which draws each surface as one of
  its numbers.

- **The frame the running game drew, for an agent.**
  - `render_*` tools sit over the game's `ext.flutter3d.render.*`. Among
    them is `render_pick`, which answers which draws painted a pixel.
  - `play_keep_tape` keeps the run the game recorded in `test/tapes/`.

- **`setCutscene` and `removeCutscene`.** An agent writes a level's
  cutscene from nothing — camera keys, subtitles, fades, signals and actor
  cues in one document — and is told every problem with it, and where,
  before anything changes.

- **An agent writes behaviour trees.** `setBehaviour` and
  `removeBehaviour`, the first describing every composite, leaf and
  consideration a tree may use and refusing one that does not read with
  each problem; `list` names the level's trees and `validate` reports an
  entity running a tree the level does not have.

- **An agent can play the level it is editing.** `play` runs the game the
  level belongs to through `flutter3d_editor_play`, the editor's own Play,
  and waits until it is up or has failed; `play_status`, `play_swap`,
  `play_stop` and `play_devices` follow it. While it runs, `save` sends the
  level to the game, which takes it without starting over.
- **`EditorSession.save` returns a `Future`**, for that send.
  `EditorSession(play:)` takes a `PlaySession` of the caller's making.

## 0.8.0

Twenty-one tools, where 0.7 had seventeen, and the server can see the level.

**Breaking for code that extends the server.** `EditorMcpServer` extends
`ToolTableServer<EditorSession, PictureAnswer>` and `EditorTool` is
`OfferedTool<EditorSession, PictureAnswer>`, so a tool's `run` returns a
`png` beside `did` and `says`, null when it has nothing to show. An agent sees
no change in the seventeen tools it had.

**`screenshot` draws the level.** It used to refuse. It renders the level on
the software rasteriser at 320 by 200 from a camera given as `from` and `at`,
or from near an upper corner looking at the middle when both are left out.
Every brush is drawn flat in its material's colour, since this process has no
image decoder, and a small box stands in for each light and entity.

**`report` says who owns the screen.** It draws the same view one brush per
draw, reads the object ids back, and says for every brush, light and entity
how many pixels it owns, its box on the screen, its depth range, and what
covers the part of the screen it would fill. That answers whether a torch can
be seen from where a player stands and which wall is in the way. `LevelView`,
`LevelCamera` and `PieceReport` are what the two tools use, exported for a
host.

**`generate` adds a room, a corridor or a scatter from a seed.** The kind,
the seed and the params become a recipe in the open level, and the answer says
how many brushes, entities and lights it builds. The document keeps the
recipe, so `list` does not show what it builds. The skill
`flutter3d-editor-mcp-editing-order` says so and says to `validate` after it,
since walls that meet another brush overlap it.

**`optimizeLights` asks for fewer lights, and `setLights` is a tool.**
`optimizeLights` runs `flutter3d_editor_core`'s `LightOptimizer` from the
`views` given, or four headings from every player spawn, applies the new set
as one `setLights` step that undo takes back (`apply: false` only reports),
and answers with the moves, the numbers and a picture of the new lighting. A
set that misses the bounds once drawn is reported and not applied. `N1`

**What a recipe builds is not drawn or judged yet.** `screenshot`, `report`
and `optimizeLights` read the document's own brushes and lights, so a room
added with `generate` is missing from the picture, from the report and from
the scene the optimizer lights.

`editorMcpVersion` is `'0.8.0'`. `flutter3d_core` and `flutter3d_cpu` are new
dependencies, both plain Dart, so `dart run flutter3d_editor_mcp:editor_mcp`
still runs on a machine with no Flutter.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**Released with the rest of the stack at 0.7.1.** Nothing in this package
changed. The release it resolves against builds from pub.dev again and no
longer crashes Metal on the first unlit draw.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

The same seventeen tools, on the server the other two share.

* **Breaking for code that extends the server, and for no agent.**
  `EditorMcpServer` extends `flutter3d_mcp_kit`'s
  `ToolTableServer<EditorSession, Answer>` where it extended `MCPServer with
  ToolsSupport`, and the registration loop and the turning of an answer into a
  result are the kit's. `EditorTool` is a typedef of
  `OfferedTool<EditorSession, Answer>`, so `EditorTool(tool, run)` still
  constructs one, but it is no longer a class of this package and `run` may
  return a `Future`. `Answer` is the kit's record, re-exported from here under
  the name it had. The model server and the simulation server are built on
  the same three types, which is why they moved.
* **Nothing an agent sees changed.** The seventeen tools keep their names,
  their schemas and their sentences, and a refusal is still an error result
  and not a thrown exception. This server passes the kit no `refusal`, so
  argument checking is `dart_mcp`'s own as before.
* **The three skills are renamed.** `editing-order`, `level-document` and
  `what-it-refuses` under `skills/` each gained the prefix
  `flutter3d-editor-mcp-`. `dart run skills@ get` skips a skill whose directory
  does not start with its package's name, and a project that depends on
  several packages can tell whose `editing-order` it is looking at.
* **The server says the version it is.** `editorMcpVersion`, which a client
  sees in the handshake, was the constant `'0.1.0'` while the package went out
  at 0.6.0. It is `'0.7.0'`, and a test reads the pubspec and holds the two
  together.
* `flutter3d_mcp_kit` `^0.7.0` is a new dependency; the floors on
  `flutter3d_editor_core` and `flutter3d_sim` are `^0.7.0`. Still plain Dart,
  and `dart run flutter3d_editor_mcp:editor_mcp <level.json>` still resolves
  on a machine with no Flutter.

## 0.6.0

An agent edits a level with the editor's own commands.

**The first release, at the set's number rather than a first number of its
own.** It goes out beside `flutter3d_editor_core` and `flutter3d_sim`, which are
the two packages it is a thin skin over, and a floor that named an older either
would be a server offering tools the document underneath does not have. What
follows is what this package is, not what changed in it: the version it wore
inside the repository was never uploaded.

* **A Model Context Protocol server over stdio, with one document per process.**
  `dart run flutter3d_editor_mcp:editor_mcp <level.json>` opens one level and
  offers seventeen tools on it. The alternative — a socket into a running editor,
  so that an agent and a person watch the same level change — is a different and
  much harder program: two writers on one undo stack, a camera that has to follow
  somebody else's selection, and a test that needs a GPU before it can assert
  anything. This is the half that can be checked.

* **The tools are `EditorCommand`, not a second implementation of one.** Ten of
  the seventeen are the sealed hierarchy `flutter3d_editor_core` defines, called
  by the names that package already gives them, and a tool call is its arguments
  handed to `EditorCommand.fromJson` — the function whose doc says it was written
  for a caller like this. So an agent's edit and a person's edit reach the
  document by one route, get one name in the history, and are undone by the same
  key. The table is built from `editorCommandNames`, and the suite holds it to
  that list both ways round: a server keeping its own copy is a server that
  silently cannot call the eleventh command.

* **Two tools that are not commands, and both were missing from every sketch.**
  `list` prints everything in the level with the kind and index `select` takes —
  every other verb works on "the selection", and a selection is something a
  program with no screen cannot guess, so without this driving the editor means
  moving the third brush without ever finding out there is a third brush. It is
  `contentsOf` in the core package, beside `handlesOf`, because it is the same
  question asked by a caller with no pixels. `validate` runs the level through
  `LevelValidator` against the document's own vocabulary; without it the first
  news of a broken level is a diff somebody reads later.

* **It cannot draw, and says so rather than going quiet.** `screenshot` is
  offered and refuses with its reason: every backend in this repository reaches a
  `GraphicsDevice` whose finished frame is a Flutter widget, so a process that
  can render a level is a Flutter process — and `dart run` cannot resolve a
  package that depends on the Flutter SDK. An absent tool would have an agent
  inventing ways around it; a refusal with a reason ends the question.

* **A generated document is not written back over.** A level carrying
  `generatedBy` may be opened, changed and saved somewhere else, and the copy
  claims itself. Saving over the original is refused, because that save would
  look like it worked right up until the next run of the generator threw the
  afternoon away — and `tool/ci.sh` re-runs every generator in the repository and
  diffs. The suite proves the refusal and then proves the file on disk did not
  move, because "will not be overwritten" printed after a write is worse than
  silence.

* **The suite drives the real protocol.** A client and a server, joined by a pair
  of in-memory streams instead of a process's stdin and stdout: three torches
  placed in the shooter template, saved to a new path, and the text compared
  against a fixture byte for byte. Fair to compare because stability was settled
  before this package existed — a JSON encoder with a two-space indent, and every
  coordinate snapped to a quarter of a metre.
