/// What every flutter3d MCP server shares.
///
/// **One arrangement, written once.** The level editor's, the modeller's, the
/// renderer's and the simulation's servers each wrote the same forty lines —
/// a pair of a tool and its handler, a loop registering them, a function
/// turning an answer into a result — with four names for the pair, two shapes
/// of answer both called `Answer`, and a loopback transport only one of them
/// had. They differ in what their tools do; everything here is what they are.
library;

export 'src/answers.dart';
export 'src/argument_check.dart';
export 'src/loopback_http.dart';
export 'src/tool_table.dart';
