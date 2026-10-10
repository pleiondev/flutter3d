/// `ToolTableServer`, driven through the real protocol over a pair of streams.
///
///     dart test test/tool_table_test.dart
library;

import 'package:dart_mcp/client.dart' hide ToolAnnotations;
import 'package:flutter3d_mcp/kit.dart';
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
            ToolSpec(
              name: 'count',
              description: 'Counts, and refuses after the first.',
              inputSchema: const <String, Object?>{'type': 'object'},
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
            ToolSpec(
              name: 'ping',
              description: 'Answers, whatever the watcher does about it.',
              inputSchema: const <String, Object?>{'type': 'object'},
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

  static void _throwing(AnsweredCall<Answer> call) =>
      throw Exception('DeviceBuffer creation failed');
}

/// The one tool `count`, offered under the old name `tally` too.
List<OfferedTool<List<String>, Answer>> get _countTool =>
    <OfferedTool<List<String>, Answer>>[
      OfferedTool<List<String>, Answer>(
        ToolSpec(
          name: 'count',
          description: 'Counts.',
          inputSchema:
              ObjectSchema(properties: <String, Schema>{'by': IntegerSchema()})
                  as Map<String, Object?>,
        ),
        (List<String> calls, Map<String, Object?> arguments) {
          calls.add('count');
          return (did: true, says: 'call ${calls.length}');
        },
      ),
    ];

base class _Renamed extends ToolTableServer<List<String>, Answer> {
  _Renamed(
    super.channel, {
    required super.session,
    super.aliases = const <String, String>{'tally': 'count'},
    super.onCall,
  }) : super(
         name: 'renamed',
         version: '0.0.0',
         schemaVersion: '2.1.0',
         instructions: 'Call `count`.',
         tools: _countTool,
         toResult: resultOf,
       );
}

void main() {
  test('the server announces its schema version, and a renamed tool still '
      'answers to its old name', () async {
    final pipe = StreamChannelController<String>(sync: true);
    final calls = <String>[];
    final heard = <String>[];
    _Renamed(
      pipe.local,
      session: calls,
      onCall: (AnsweredCall<Answer> call) => heard.add(call.toolName),
    );

    final client = MCPClient(Implementation(name: 'suite', version: '0.0.0'));
    final connection = client.connectServer(pipe.foreign);
    final hello = await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    connection.notifyInitialized();

    // Mutation: build `Implementation` from the name and version alone. A
    // host has nothing to compare its cached tool list against.
    expect(
      (hello.serverInfo as Map<String, Object?>)['schemaVersion'],
      '2.1.0',
    );

    // Mutation: skip the aliases when registering. `tally` disappears from
    // the list and an agent configured with it is told there is no such
    // tool — the break an alias exists to defer.
    // `flutter3d.schema` comes after the server's own tools and aliases.
    final offered = await connection.listTools(ListToolsRequest());
    expect(offered.tools.map((Tool t) => t.name), <String>[
      'count',
      'tally',
      schemaToolName,
    ]);
    final Tool tally = offered.tools[1];
    expect(
      tally.description,
      startsWith(
        'Deprecated: `tally` is the old name '
        'of `count`',
      ),
    );
    expect(tally.description, endsWith('Counts.'));
    expect(
      tally.inputSchema.properties!.keys,
      offered.tools.first.inputSchema.properties!.keys,
    );

    final answer = await connection.callTool(
      CallToolRequest(name: 'tally', arguments: <String, Object?>{'by': 1}),
    );
    expect(answer.isError, isNot(true));
    expect(calls, <String>['count']);
    expect(heard, <String>['count']);

    // Mutation: answer `flutter3d.schema` without the server's version. A
    // host that cached the list has nothing to compare against.
    final schema = await connection.callTool(
      CallToolRequest(name: schemaToolName),
    );
    expect(schema.isError, isNot(true));
    expect(schema.structuredContent?['schemaVersion'], '2.1.0');

    await client.shutdown();
  });

  test('every kind of content reads back as itself, and one this build '
      'does not know is kept as it came', () {
    final json = <String, Object?>{
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': 'hello'},
        <String, Object?>{
          'type': 'audio',
          'data': 'AAEC',
          'mimeType': 'audio/wav',
        },
        <String, Object?>{
          'type': 'resource',
          'resource': <String, Object?>{
            'uri': 'file:///level.json',
            'mimeType': 'application/json',
            'text': '{}',
          },
        },
        <String, Object?>{
          'type': 'resource_link',
          'uri': 'file:///lap.ghost.json',
          'name': 'lap',
        },
        <String, Object?>{'type': 'hologram', 'depth': 3},
      ],
    };
    final result = ToolResult.fromJson(json);

    // Mutation: read an unknown kind as `ToolText('')`, as before. The
    // hologram is gone from the result written back, and so is the audio.
    expect(result.content.map((ToolContent c) => c.runtimeType), <Type>[
      ToolText,
      ToolAudio,
      ToolResource,
      ToolResourceLink,
      ToolOtherContent,
    ]);
    expect((result.content[4] as ToolOtherContent).type, 'hologram');
    expect(result.toJson()['content'], json['content']);
  });

  test('an alias that names no tool, or shadows one, is refused', () {
    for (final Map<String, String> wrong in <Map<String, String>>[
      <String, String>{'tally': 'missing'},
      <String, String>{'count': 'count'},
    ]) {
      expect(
        () => _Renamed(
          StreamChannelController<String>(sync: true).local,
          session: <String>[],
          aliases: wrong,
        ),
        throwsArgumentError,
        reason: '$wrong',
      );
    }
  });

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
    expect(offered.tools.map((Tool it) => it.name), <String>[
      'count',
      schemaToolName,
    ]);

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
