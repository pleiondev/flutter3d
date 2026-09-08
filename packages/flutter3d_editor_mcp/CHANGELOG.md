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
