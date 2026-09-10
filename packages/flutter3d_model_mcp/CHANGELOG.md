## 0.6.0

**The server itself, offering every model command as a tool.** `ModelSession`
wraps a project with `list`, `select`, `undo`, `redo`, `check`, `save`,
`export`, `import` and `journal`; `ModelMcpServer` speaks the rest of
`modelCommandNames` over MCP, one tool each, dispatched through
`modelCommandFromJson` the same reader the project file and `CommandJournal`
use. `export` writes `.f3d` and `.obj` and refuses `glb`/`gltf` by name, since
`fmt-06` is not built yet. `test/agent_builds_a_table_test.dart` drives the
real protocol over an in-memory pair of streams and diffs the files a table,
built from primitives, comes out as.

Along the way: `modelCommandFromJson` learned to default `AddPrimitive`'s
`size`/`segments`, `AddLathe`'s `segments`/`closedProfile`/`label`, `LoopCut`'s
`cuts`/`factor` and `RecalculateNormals`'s `flip` when a caller leaves them
out, matching what their constructors already default to — a gap only a
partial JSON call could have found, and this tool table is the first one that
sends one. `flutter3d_model_core` also gained `ReplaceDocument`, the one
command not addressable by name or replayable from a journal, for `import`'s
sake: bringing a whole decoded file's objects in is not an edit any existing
command describes.

**An entry point that said what it could not do yet, and a graph that proved
what it could.** `dart run flutter3d_model_mcp:model_mcp --help` resolved and
printed usage on a machine with the Dart SDK and no Flutter before any of the
above existed — which is the property the whole package split keeps, checked
from the first commit rather than after the server was written.
