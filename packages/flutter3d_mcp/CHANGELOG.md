## 1.0.0-rc.1

- **The editor server draws its level through `flutter3d_level_scene`**,
  where `LevelScene` lives since it left `flutter3d_editor_core`.

- **`McpToolRegistry` is declared here**, the slot `McpTools` fills; it was
  a marker in `flutter3d_plugin_api`.

- **Breaking: a call watcher is handed one `AnsweredCall`.**
  `ToolTableServer.onCall` and `onProjectCall`, `ModelMcpServer(onCall:)`
  and `ModelHttpServer.start(onToolCall:)` take an `AnsweredCall` (tool
  name, arguments, answer, elapsed) where they took four arguments, so a
  feed keeps working when a call says more. `model.dart` re-exports it and
  `PictureAnswer`.
- **Breaking: `ToolContent` is an `abstract base class`, no longer
  `sealed`**, so an exhaustive `switch` over it needs a default. It gains
  `ToolAudio`, `ToolResource`, `ToolResourceLink`, `ToolOtherContent` and
  `ToolContent.fromJson`; content of a kind this build does not know is
  kept as `ToolOtherContent` instead of becoming an empty `ToolText`.
- **`McpTools.declareSchemaVersion` is honoured whenever it is called, and
  returns a `Registration`.** Tools already added get the version and a
  running server offers them again; through a plugin's view the
  declaration is withdrawn with the plugin.
- **Every editor tool declares an `outputSchema`** (`editorAnswerSchema`)
  and answers `structuredContent` `{did, says, selection, hasPicture}`.
  `render.saveCapture` and `play.keepTape` are marked destructive: they
  write over a file.
- **The servers' schema versions start at 1.0.0** with the first stable
  release (editor, model, project).
- **The stdio servers exit with the command's contract codes**: 2 for usage
  and 1 for a document they cannot open, not 64 and 66; a project that will
  not open throws a `ProjectFormatException`.

- **New: one package for what was three.** `flutter3d_mcp_kit`,
  `flutter3d_editor_mcp`, `flutter3d_model_mcp` are libraries of this package
  now: `kit.dart`, `editor.dart`, `model.dart`, each with the API its package
  had, and `flutter3d_mcp.dart` exports them all. `dart run
  flutter3d_build:migrate` moves a project's dependencies and imports; the
  packages' own histories are in `doc/changelogs/`.
- **The commands keep their names**: `dart run flutter3d_mcp:editor_mcp`,
  `:model_mcp` and `:project_mcp`, and each server announces the name and schema
  version it did. The skills are `flutter3d-mcp-editor-*` and
  `flutter3d-mcp-model-*`.

### `kit.dart`, from `flutter3d_mcp_kit` 1.0.0-rc.1

- **Breaking: tools and answers are flutter3d's own types.** A tool is a
  `ToolSpec` (name, description, JSON Schema input and output, `ToolHints`,
  `_meta`) and an answer a `ToolResult` (`ToolText` and `ToolImage` content,
  `structuredContent`, `isError`). The MCP library underneath is pre-1.0, and
  none of its types is in a signature any more: `OfferedTool.tool` is
  `OfferedTool.spec`, `ProjectTool.tool` is `ProjectTool.spec`,
  `ProjectToolRun` and `onProjectCall` speak `ToolResult`, `toResult`,
  `resultOf` and `pictureResultOf` answer `ToolResult`, `refuseArguments`
  takes a `ToolSpec`, and `OfferedPrompt.prompt` is gone (the server builds
  the prompt itself). `ToolTableServer` holds the protocol server instead of
  extending it, so it no longer has `MCPServer`'s members; `done`,
  `shutdown`, `serverInfo` and `offeredSpecs` are what a caller needs.
- **One naming scheme, `area.verb`, with the old names kept.** A server
  takes `names:` — each tool's written name to a `ToolName`, the name it is
  published under and its hints — and keeps the written name answering as an
  alias until 2.0. `ToolName.pattern` is the rule; the area may be
  camel-cased like any other word (`textureGraph.addNode`), which the
  modelling server's names need to start at all.
- **Every server says what its tools do and which schema it speaks.** Each
  tool carries `ToolHints` (read-only, destructive, idempotent, open world)
  as the protocol's annotations and its schema version in `_meta`
  (`flutter3d/schemaVersion`); the `initialize` result carries it in `_meta`
  too, and every server answers `flutter3d.schema` with its own version and
  each plugin namespace's. A structured answer comes from a tool that
  declared its `outputSchema`.
- **A plugin asks for the `tools` permission to add a tool.**
  `McpTools.addTool` refuses a plugin whose manifest does not list
  `PluginPermission.tools`, with a `PluginException` naming it, so a person
  installing a plugin sees that it talks to agents.
  `McpTools.declareSchemaVersion` gives a namespace's own schema version, and
  `schema_snapshot --plugin package:<package>#<Plugin>` in `tool/api`
  snapshots a plugin's tools to its `api/<package>.plugin.mcp`.
- **`ProjectMcpServer` announces itself as `flutter3d.project`**, the
  scheme every server follows now (`flutter3d.editor`, `flutter3d.sim`,
  `flutter3d.diagnostics`, `flutter3d.model`, `flutter3d.plugins`). Schema
  1.1.0.
- **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

- **The project server starts from the command line**, as `dart run
  flutter3d_mcp_kit:project_mcp`. `project_tools.dart` exports `McpTools`
  alone, without `dart:io`, so an application built for the browser can fill
  the registry too.

- **A server announces its schema version, and a renamed tool keeps its old
  name.** `ToolTableServer` takes an optional `schemaVersion`, sent in the
  `initialize` result's `serverInfo` beside `version`, so a host can tell
  whether the tool list it cached still holds; it moves only when the tools
  do. And an optional `aliases`, old name to new: the old name stays in
  `tools/list` with the new tool's schema and a description that opens by
  saying it is deprecated and what to call instead, and a call to it runs
  the new tool through the same brake, argument check and watcher. An alias
  that names no tool, or shadows one, is refused when the server is built.
  Both are additions; every server built on this passes the first, and no
  tool has been renamed. The tools themselves are held to `api/<package>.mcp`
  in each server's package — see "Tools for agents are a contract too" in
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#tools-for-agents-are-a-contract-too).

- **A plugin brings its own tools, and every server of the project offers
  them.** `McpTools` fills the plugin API's `McpToolRegistry` slot: a
  plugin's `install` calls `host.registry<McpTools>().addTool(tool, run)`,
  and the tool is published as `<plugin id>.<name>`, so two plugins'
  `reset`s do not meet. The application adds its own under a namespace it
  names. A name that is not letters, digits, `_` and `-`, or one already
  added, is refused with the owner's name, and switching a plugin off
  withdraws its tools. `ToolTableServer` takes the registry as an optional
  `projectTools` and offers it after its own tools, through the same brake
  and argument check, with `onProjectCall` as its watcher. It keeps the list
  in step while it runs and tells the client when it changes. A project
  tool named like one of the server's own is not offered, and
  `shadowedProjectTools` says which. `ProjectMcpServer` offers the
  registry alone, for a project that runs no other server; its own surface
  is empty and is snapshotted in `api/flutter3d_mcp_kit.mcp`. The plugins'
  tools are snapshotted and versioned by the packages that bring them. All
  of it is an addition. The package now depends on `flutter3d_plugin_api`,
  which is plain Dart with no dependencies.

**Moves with the stack to 1.0.0**, whose `flutter3d_hardware` gives
`PassEncoder.draw` a window of the bound indices and every `PassEncoder`
`setAlphaToCoverage`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^1.0.0`.

### `editor.dart`, from `flutter3d_editor_mcp` 1.0.0-rc.1

- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `removeBehaviour` is `removeBehavior`, `setBehaviour` is
  `setBehavior`. Only the Dart names changed: a file keeps the keys it was
  written with, and `dart fix` carries the renames.
- **Tools are named `area.verb`, and the old names still answer.**
  `brush.add`, `selection.move`, `prefab.place`, `render.passes`,
  `play.start`: `editorToolNames` lists each with what it does to the level
  (read-only, writes, destructive), and `addBrush`, `moveBy`, `play_status`
  and the rest stay aliases until 2.0. The server announces itself as
  `flutter3d.editor`, schema 1.2.0.
- **`command.run` reaches every command the editor knows, a plugin's
  included.** It takes a command's name and its arguments, and reads it
  through the session's `EditorPieces` (`EditorSession.pieces`, filled by the
  plugins `serveEditorMcp` installs), so a plugin's `boats.sink` is called
  the way `moveBy` is.
- **Breaking:** `EditorSession.run` takes any `DocumentCommand`, a plugin's
  too, and tools are `ToolSpec`s (see `flutter3d_mcp_kit`): the `Tool` type
  of the MCP library is in no signature.
- **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

- **Captures saved and opened, memory and debug views listed.**
  `render_capture_save` writes the running game's frame to a capture file,
  `capture_open` and `capture_draw` read one back with a picture of its last
  pass, `render_memory` reports what the renderer holds, and
  `render_debug_views` lists the views `screenshot` and the renderer take.

- **Prefab tools for agents.** `createPrefab`, `placePrefab`,
  `setOverride`, `applyOverrides`, `revertOverrides`, `unpackPrefab` and
  `setPrefabField` are the editor's prefab commands; `prefabs` lists the
  templates with the paths their overrides take; `select` takes `also` to
  pick several things. All additions: the schema version is 1.1.0.

- **Breaking: `editorMcpSchemaVersion` is `'1.1.0'`**, as the tools above
  require. Code that compared it with `'1.0.0'` should compare versions.

- **The editor's server offers a project's plugin tools.**
  `serveEditorMcp(arguments, plugins:)` installs the plugins into an
  `McpTools` and hands it to the server as `projectTools`.
  `bin/editor_mcp.dart` is that call with no plugins; a project that wants
  its plugins' tools calls it from its own `bin/` with its
  `installedPlugins`.

- **The project's plugin tools are offered beside the server's own.**
  `EditorMcpServer` takes an optional `projectTools`, the project's
  `McpTools` from `flutter3d_mcp_kit`, and `onProjectCall` to watch calls
  to them. Each plugin tool is listed as `<plugin id>.<name>` after the
  server's own, and the list follows plugins as they are switched on and
  off. A server built without it offers exactly what
  `api/flutter3d_editor_mcp.mcp` lists, so the schema version does not
  move. An addition.

- **The tools are a contract too.** Their names and input schemas are
  written down in `api/flutter3d_editor_mcp.mcp` and held to the same semver
  as the Dart API: a tool removed or renamed without an alias, or a new
  required argument, waits for a major. The server announces
  `editorMcpSchemaVersion` (1.0.0) as `schemaVersion` in its `initialize`
  result, and it moves only when the tools do.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#tools-for-agents-are-a-contract-too)
  has the rules.

- **`play_build` says whether the game compiles without running it.** It
  runs `flutter build` in the project above the level, for this computer's
  desktop or a named target, debug unless `release` is given, and answers
  a failure with the lines that carry an error rather than the whole log.
  It is refused while `play` runs the game, since both would write into the
  same `build` directory.

- **`play_send_level` hands the running game the level as it stands.**
  Unsaved changes go with it and the file on disk is left alone, so an
  agent can try a change in the game before keeping it, or put the level
  back after a hot restart.

- **`play_events` hears what the running game says about itself.** A level
  loaded, the player died or came back, a pickup taken, the way out
  reached: whatever the game posts with `postToolEvent`, in order, each
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

- **An agent writes behaviour trees.** `setBehavior` and
  `removeBehavior`, the first describing every composite, leaf and
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

Its `flutter3d_*` dependencies ask for `^1.0.0`.

### `model.dart`, from `flutter3d_model_mcp` 1.0.0-rc.1

- **Breaking: one suffix for settings, Settings, and Descriptor in the
  HAL.** `ImportOptions` is `ImportSettings`. Every settings class is
  `final` with a `const` constructor and a `copyWith` over every field; a
  nullable field is reset with `copyWith(clearX: true)`. `dart fix` carries
  the renames.
- **Breaking: `ModelSession.makeGameReady` is `prepareForGame`.** The MCP
  tool keeps its name; `dart fix` carries the Dart call.
- **Tools are named `area.verb`, and the old names still answer.**
  `object.addPrimitive`, `mesh.extrude`, `selection.facing`,
  `material.setField`: `modelToolNames` lists every one with what it does to
  the project, and the command names (`addPrimitive`, `extrude`), which
  `history.batch` still takes inside its list, stay aliases until 2.0. The
  server announces itself as `flutter3d.model`, schema 1.1.0.
- **Every tool declares the shape of its structured answer.**
  `modelAnswerSchema` (`did`, `says`, `ids`, `selection`) is each tool's
  `outputSchema`, so a host can validate what it reads.
- **Breaking:** tools are `ToolSpec`s and answers `ToolResult`s (see
  `flutter3d_mcp_kit`); this package re-exports them, so a host adding its
  own tools needs no import of the MCP library.
- **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

- **The modeller's server takes the project's tools.**
  `serveModelMcp(arguments, projectTools:)` is what `bin/model_mcp.dart`
  runs, and a project's own `bin/` passes the registry its plugins filled.

- **The project's plugin tools are offered beside the server's own.**
  `ModelMcpServer` takes an optional `projectTools`, the project's
  `McpTools` from `flutter3d_mcp_kit`, and `onProjectCall` to watch calls
  to them. Each plugin tool is listed as `<plugin id>.<name>` after the
  server's own and after `extraTools`, and the list follows plugins as they
  are switched on and off. A server built without it offers exactly what
  `api/flutter3d_model_mcp.mcp` lists, so the schema version does not move.
  An addition.

- **The tools are a contract too.** Their names and input schemas — as the
  server offers them, with the target arguments every selection command
  gains — are written down in `api/flutter3d_model_mcp.mcp` and held to the
  same semver as the Dart API: a tool removed or renamed without an alias,
  or a new required argument, waits for a major. The server announces
  `modelMcpSchemaVersion` (1.0.0) as `schemaVersion` in its `initialize`
  result, and it moves only when the tools do; tools a GUI host adds through
  `extraTools` are the host's and not part of it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#tools-for-agents-are-a-contract-too)
  has the rules.

**`setAnimationGraph` and `removeAnimationGraph`.** An agent sets a
character's graph by name over the project's clips, with the whole shape
described in the tool, and is told where a wrong one is wrong.

Its `flutter3d_*` dependencies ask for `^1.0.0`.
