/// A model editor offered to an agent, over the Model Context Protocol.
///
/// **The same commands a person uses, offered as tools.** Every command tool
/// here is a [ModelCommand] from `flutter3d_model_core` — the values the
/// modeller application's own toolbar and keyboard go through — so an edit
/// made by an agent and an edit made by a hand take one route into the
/// project, get one name in the history, and come back out under the same
/// undo.
///
/// Beyond the commands, [ModelSession] adds the verbs a screen would
/// otherwise supply: [ModelSession.listing] and [ModelSession.select],
/// because a program with no screen cannot point at anything; `check`, `save`,
/// `export` and `import`, because a project has a life outside the commands
/// that shape it; `journal`, because `doc-16`'s `CommandJournal` is worth
/// writing to disk from the one place that already runs every command; and
/// `mcp-09n`'s own composite recipes — `cleanup`, `buildFrom` and
/// `inspect` — because an agent assembling one out of the commands above
/// by hand is slow, expensive, and leaves a whole batch of edits as many
/// undo steps instead of one.
///
/// ## What it is not
///
/// **Not a connection to a running editor.** The server owns one project for
/// the life of one process, started by `dart run`. This is the half that can
/// be tested without a device: deterministic text out, and a suite that
/// drives the real protocol over a pair of streams in memory.
///
/// **It does draw, though nothing else here answers with a picture.**
/// `render` (`mcp-06n`) and `renderSheet` (`mcp-07n`, a 2×2 contact sheet of
/// four views) are the two tools built on `flutter3d_cpu`'s own `CpuDevice`
/// — no GPU, no display, and, since `flutter3d_conformance` and
/// `flutter3d_shaders` stopped carrying the Flutter SDK in behind it, no cost
/// to `dart run`'s own ability to start this server with no Flutter tool on
/// the machine at all. See `render_tool.dart`'s own doc comment for why
/// every other tool still answers with no `png` rather than every tool body
/// here having grown one.
///
/// ```sh
/// dart run flutter3d_model_mcp:model_mcp my-model.f3dproj
/// ```
library;

export 'src/model_http_server.dart';
export 'src/model_server.dart';
export 'src/model_session.dart';
export 'src/model_tools.dart';
export 'src/render_tool.dart';
