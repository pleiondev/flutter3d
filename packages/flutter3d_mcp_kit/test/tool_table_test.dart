/// `ToolTableServer`, driven through the real protocol over a pair of streams.
///
///     dart test test/tool_table_test.dart
library;

import 'package:dart_mcp/client.dart';
import 'package:flutter3d_mcp_kit/flutter3d_mcp_kit.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// A server whose one tool counts its calls and refuses the second.
base class _Counter extends ToolTableServer<List<String>, Answer> {
  _Counter(super.channel, {required super.session})
    : super(
        name: 'counter',
        version: '0.0.0',
        instructions: 'Call `count`.',
        tools: <OfferedTool<List<String>, Answer>>[
          OfferedTool<List<String>, Answer>(
            Tool(
              name: 'count',
              description: 'Counts, and refuses after the first.',
              inputSchema: ObjectSchema(),
            ),
            (List<String> calls, Map<String, Object?> arguments) {
              calls.add('count');
              return (did: calls.length < 2, says: 'call ${calls.length}');
            },
          ),
        ],
        toResult: resultOf,
      );
}

/// A server whose watcher throws — `ux-02`'s own case, where the hook
/// re-synced a scene and an object the device had refused threw again.
base class _Watched extends ToolTableServer<List<String>, Answer> {
  _Watched(super.channel, {required super.session})
    : super(
        name: 'watched',
        version: '0.0.0',
        instructions: 'Call `ping`.',
        tools: <OfferedTool<List<String>, Answer>>[
          OfferedTool<List<String>, Answer>(
            Tool(
              name: 'ping',
              description: 'Answers, whatever the watcher does about it.',
              inputSchema: ObjectSchema(),
            ),
            (List<String> calls, Map<String, Object?> arguments) {
              calls.add('ping');
              return (did: true, says: 'pong ${calls.length}');
            },
          ),
        ],
        toResult: resultOf,
        onCall: _throwing,
      );

  static void _throwing(
    String name,
    Map<String, Object?> arguments,
    Answer answer,
    Duration elapsed,
  ) => throw Exception('DeviceBuffer creation failed');
}

void main() {
  test(
    'a watcher that throws does not fail the call it was watching',
    () async {
      final pipe = StreamChannelController<String>(sync: true);
      final calls = <String>[];
      _Watched(pipe.local, session: calls);

      final client = MCPClient(Implementation(name: 'suite', version: '0.0.0'));
      final connection = client.connectServer(pipe.foreign);
      await connection.initialize(
        InitializeRequest(
          protocolVersion: ProtocolVersion.latestSupported,
          capabilities: client.capabilities,
          clientInfo: client.implementation,
        ),
      );
      connection.notifyInitialized();

      // Mutation: let the hook's exception out. The answer — already computed,
      // already correct — comes back as a stack trace, and so does every call
      // after it, which is exactly what the live run saw.
      final first = await connection.callTool(CallToolRequest(name: 'ping'));
      expect(first.isError, isNot(true));
      expect((first.content.single as TextContent).text, 'pong 1');

      final second = await connection.callTool(CallToolRequest(name: 'ping'));
      expect(second.isError, isNot(true));
      expect((second.content.single as TextContent).text, 'pong 2');

      await client.shutdown();
    },
  );

  test('every offered tool is registered, and a refusal is an error result '
      'rather than a failed server', () async {
    final pipe = StreamChannelController<String>(sync: true);
    final calls = <String>[];
    _Counter(pipe.local, session: calls);

    final client = MCPClient(Implementation(name: 'suite', version: '0.0.0'));
    final connection = client.connectServer(pipe.foreign);
    await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    connection.notifyInitialized();

    final offered = await connection.listTools(ListToolsRequest());
    expect(offered.tools.map((Tool it) => it.name), <String>['count']);

    final first = await connection.callTool(CallToolRequest(name: 'count'));
    expect(first.isError, isNot(true));
    expect((first.content.single as TextContent).text, 'call 1');

    // Mutation: throw on a refusal instead of answering it. The client sees a
    // protocol error in place of a sentence it could act on.
    final second = await connection.callTool(CallToolRequest(name: 'count'));
    expect(second.isError, isTrue);
    expect((second.content.single as TextContent).text, 'call 2');
    expect(calls, hasLength(2));

    await client.shutdown();
  });
}
