## 1.0.0-rc.1

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

## 0.8.0

**Moves with the stack to 0.8.0**, whose `flutter3d_hardware` changes
`PassEncoder.bindTexture` to return `bool` and makes every backend forget its
bindings at `bindPipeline`. Nothing in this package changed.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**Released with the rest of the stack at 0.7.1.** Nothing in this package
changed. The release it resolves against builds from pub.dev again and no
longer crashes Metal on the first unlit draw.

Its `flutter3d_*` dependencies ask for `^0.7.1`.

## 0.7.0

- **The first publication.** The 0.6.0 below was a number carried inside the
  workspace and never reached pub.dev. 0.7.0 is the number the whole shelf
  goes out on, so that one number names one tree and `^0.7.0` on any
  `flutter3d_*` package resolves against every other;
  `doc/boundary-0.7.0.md` lists the thirteen packages that begin here. Three
  servers depend on this one: `flutter3d_model_mcp`, `flutter3d_editor_mcp`
  and `flutter3d_sim_mcp`.
- **The names the entry below describes without naming.**
  `OfferedTool<S, A>(tool, run)` is a tool and its handler as one value, and
  `run` may return a `Future`. `ToolTableServer<S, A>` registers a list of them
  over one `session` and turns each answer into a result with `toResult`.
  `Answer` is `({bool did, String says})` and `PictureAnswer` adds a nullable
  `png`; `resultOf` and `pictureResultOf` make the results, with `isError` set
  when `did` is false. `LoopbackMcpServer.start` binds 127.0.0.1 only, takes
  one JSON-RPC message per POST and wants a bearer token of 32 random bytes;
  `writeMcpSessionFile` and `deleteMcpSessionFile` keep the `{port, token}`
  file a client finds it by.
- **A wrong argument is refused by name.** With `refusal` given,
  `ToolTableServer` switches off `dart_mcp`'s `validateArguments` and runs
  `refuseArguments(tool, arguments)` first. It answers a sentence for an
  unknown key, saying which keys the tool does take, and then for the first
  schema error: an enum miss, a wrong type, a wrong item count, a number out
  of range, a missing required key. The sentence comes back as an ordinary
  error result the model can act on. Without `refusal` the framework's own
  check runs as before.
- **`pausedBecause`: the person stays in charge.** A function asked before
  every call; a non-null sentence is returned as the refusal and the tool does
  not run. It is asked ahead of the argument check, since a complaint about a
  misspelt key is a strange answer to "you are paused". It is consulted only on
  a server that was also given `refusal`, because that is what builds the
  answer.
- **`onCall` and `onInitialize`, for whoever is watching.** `onCall(toolName,
  arguments, answer, elapsed)` runs after each tool and
  `onInitialize(clientName)` when a client connects. An exception thrown by
  either is swallowed: a re-sync inside the hook once threw for one object a
  device had refused, and the answer, already computed and correct, reached
  the agent as a stack trace, for that call and every one after it. The
  stopwatch is started only when `onCall` is set, so a headless server never
  reads the clock.
- **Prompts.** `OfferedPrompt(name:, description:, text:)` and the `prompts`
  list; `prompts/get` hands back the text as one user message. A prompt here
  takes no arguments. `ToolTableServer` mixes in `PromptsSupport` for it.
- Plain Dart on `dart_mcp` `>=0.5.2 <0.6.0` and `stream_channel` `^2.1.4`, with
  no sibling dependency. `loopback_http.dart` imports `dart:io`.

## 0.6.0

- **The arrangement four servers each wrote, written once.** A tool paired with
  its handler, a server that registers a list of them over one session, the
  two shapes of answer and the functions that turn them into results, and the
  loopback HTTP transport that used to belong to the modeller's server alone.
