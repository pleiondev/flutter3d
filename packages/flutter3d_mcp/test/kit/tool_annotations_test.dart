/// Every tool of the editor's and the modeller's servers says what it does
/// to the world and what it answers with.
///
///     dart test test/kit/tool_annotations_test.dart
///
/// **A hint left to its default is a guess a host makes for us.** `ToolName`
/// and `ToolSpec` default to `ToolHints.writes`, so a tool published under a
/// name the table does not list still carries hints, and the snapshot prints
/// them as if somebody had chosen. The table is where somebody chooses: a
/// tool that is read-only or destroys something says so there. And a tool
/// with no `outputSchema` leaves a host to parse `structuredContent` blind.
library;

import 'dart:io';

import 'package:flutter3d_mcp/editor.dart';
import 'package:flutter3d_mcp/kit.dart'
    show OfferedTool, ToolName, schemaToolName;
import 'package:flutter3d_mcp/model.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// The names [tools] are published under that the [names] table does not
/// give: each one's hints were never chosen.
List<String> _unannotated<S, A>(
  List<OfferedTool<S, A>> tools,
  Map<String, ToolName> names,
) {
  final chosen = <String>{for (final n in names.values) n.name};
  return <String>[
    for (final tool in tools)
      if (tool.name != schemaToolName && !chosen.contains(tool.name)) tool.name,
  ];
}

/// The tools of [tools] that declare no `outputSchema`.
List<String> _schemaless<S, A>(List<OfferedTool<S, A>> tools) => <String>[
  for (final tool in tools)
    if (tool.spec.outputSchema == null) tool.name,
];

void main() {
  late Directory workspace;
  setUp(
    () => workspace = Directory.systemTemp.createTempSync('f3d_annotations_'),
  );
  tearDown(() => workspace.deleteSync(recursive: true));

  test('every editor tool declares its answer and its hints', () {
    // Mutation: leave a tool out of `editorToolNames`, or offer one without
    // `editorAnswerSchema`, and its name is listed here.
    final level = File('${workspace.path}/level.first.json')
      ..writeAsStringSync(
        File('test/editor/fixtures/shooter.first.json').readAsStringSync(),
      );
    final server = EditorMcpServer(
      StreamChannelController<String>(sync: true).local,
      session: EditorSession.open(level.path),
    );
    expect(server.tools, isNotEmpty);
    expect(_schemaless(server.tools), isEmpty);
    expect(_unannotated(server.tools, editorToolNames), isEmpty);
  });

  test('every model tool declares its hints and its answer', () {
    // Mutation: add a tool to `modelTools` without a row in
    // `modelToolNames`, and it is published with the default hints.
    final server = ModelMcpServer(
      StreamChannelController<String>(sync: true).local,
      session: ModelSession.open('${workspace.path}/scene.f3dproj'),
    );
    expect(server.tools, isNotEmpty);
    expect(_unannotated(server.tools, modelToolNames), isEmpty);
    expect(_schemaless(server.tools), isEmpty);
  });
}
