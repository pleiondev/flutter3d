/// `McpTools`, the project's registry of plugin tools, and the servers that
/// offer it: names, owners, order, and a running server kept in step.
///
///     dart test test/mcp_tools_test.dart
///
/// Each test was written by breaking what it covers; the mutation is named.
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter3d_mcp/kit.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// A plugin's scope, as the host would make it: an id, a place in the
/// install order, and the registrations it keeps. It asks for the `tools`
/// permission unless [permissions] says otherwise.
final class _Scope extends PluginScope {
  _Scope(String id, this.rank, {Set<PluginPermission>? permissions})
    : manifest = PluginManifest(
        id: id,
        apiVersion: const PluginApiVersion(1, 0),
        permissions: permissions ?? <PluginPermission>{PluginPermission.tools},
      );

  @override
  final PluginManifest manifest;

  @override
  final int rank;

  final List<Registration> kept = <Registration>[];

  @override
  void track(Registration registration) => kept.add(registration);
}

ToolSpec _tool(String name, {Map<String, Schema>? properties}) => ToolSpec(
  name: name,
  description: 'The $name tool.',
  inputSchema: ObjectSchema(properties: properties) as Map<String, Object?>,
);

ToolResult _says(String text) => ToolResult.text(text);

/// A server with one tool of its own, `count`, and maybe one named like a
/// plugin's.
base class _Server extends ToolTableServer<List<String>, Answer> {
  _Server(
    super.channel, {
    required super.projectTools,
    super.pausedBecause,
    super.onProjectCall,
    List<String> own = const <String>['count'],
  }) : super(
         session: <String>[],
         name: 'server',
         version: '0.0.0',
         instructions: 'Call anything.',
         tools: <OfferedTool<List<String>, Answer>>[
           for (final name in own)
             OfferedTool<List<String>, Answer>(
               _tool(name),
               (List<String> calls, Map<String, Object?> arguments) =>
                   (did: true, says: name),
             ),
         ],
         toResult: resultOf,
         refusal: (String says) => (did: false, says: says),
       );
}

/// A client connected to [server]'s other end and initialized.
Future<(MCPClient, ServerConnection)> _connect(
  StreamChannelController<String> pipe,
) async {
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
  return (client, connection);
}

Future<List<String>> _names(ServerConnection connection) async => <String>[
  for (final Tool t in (await connection.listTools(ListToolsRequest())).tools)
    t.name,
];

void main() {
  test('a plugin\'s tool is published under its id, the application\'s '
      'under the namespace it names, in install order', () {
    final tools = McpTools();
    final heat = _Scope('heat', 1);
    final wind = _Scope('wind', 0);
    tools.forPlugin(heat).addTool(_tool('spread'), (_) => _says('spread'));
    tools.forPlugin(wind).addTool(_tool('gust'), (_) => _says('gust'));
    tools.addTool(_tool('reset'), (_) => _says('reset'), namespace: 'game');

    // Mutation: publish the tool's own name. Two plugins' `reset`s would
    // collide, and nothing in the list says whose a tool is.
    // Mutation: sort by sequence alone. `heat`, added first, would come
    // before the application's and before `wind`, which installs first.
    expect(tools.tools.map((ProjectTool t) => t.name), <String>[
      'game.reset',
      'wind.gust',
      'heat.spread',
    ]);
    expect(tools.named('wind.gust')!.owner, 'plugin "wind"');
    expect(tools.named('game.reset')!.owner, 'the application');
    // Mutation: leave the registration untracked. Switching the plugin off
    // would leave its tool offered.
    expect(heat.kept, hasLength(1));
    expect(wind.kept, hasLength(1));
  });

  test('a name, a namespace or a second claim that cannot be is refused, '
      'naming who holds it', () {
    final tools = McpTools();
    final wind = tools.forPlugin(_Scope('wind', 0));
    wind.addTool(_tool('gust'), (_) => _says('gust'));

    // Mutation: drop the duplicate check. The second `wind.gust` replaces
    // the first in a running server, and which one an agent reaches depends
    // on the order they were registered in.
    expect(
      () => tools
          .forPlugin(_Scope('wind', 0))
          .addTool(_tool('gust'), (_) => _says('again')),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.message,
          'message',
          contains('plugin "wind"'),
        ),
      ),
    );
    // Mutation: accept a dot in the tool's own name. `gust.x` under `heat`
    // reads as a tool of a plugin called `heat.gust`.
    expect(
      () => tools
          .forPlugin(_Scope('heat', 1))
          .addTool(_tool('gust.x'), (_) => _says('')),
      throwsArgumentError,
    );
    // Mutation: let a plugin name another namespace. It could publish
    // under somebody else's id.
    expect(
      () => wind.addTool(_tool('calm'), (_) => _says(''), namespace: 'heat'),
      throwsArgumentError,
    );
    // Mutation: default the application's namespace. Its tools would read
    // as nobody's.
    expect(
      () => tools.addTool(_tool('reset'), (_) => _says('')),
      throwsArgumentError,
    );
    // Mutation: drop the permission check in `addTool`. A plugin that never
    // said it talks to agents would publish a tool anyway, and whoever
    // installed it would not have seen that it can.
    expect(
      () => tools
          .forPlugin(_Scope('mute', 2, permissions: <PluginPermission>{}))
          .addTool(_tool('hush'), (_) => _says('')),
      throwsA(
        isA<PluginException>().having(
          (PluginException e) => e.message,
          'message',
          allOf(contains('plugin "mute"'), contains('`tools` permission')),
        ),
      ),
    );
  });

  test('a schema version declared after the tools reaches them and a '
      'running server, and goes when the plugin does', () async {
    final tools = McpTools();
    final scope = _Scope('wind', 0);
    final wind = tools.forPlugin(scope);
    wind.addTool(_tool('gust'), (_) => _says('blew'));

    final pipe = StreamChannelController<String>(sync: true);
    final server = _Server(pipe.local, projectTools: tools);
    final (client, connection) = await _connect(pipe);

    Future<Object?> metaOfGust() async {
      final listed = await connection.listTools(ListToolsRequest());
      final gust = listed.tools.firstWhere((Tool t) => t.name == 'wind.gust');
      return ((gust as Map<String, Object?>)['_meta']
          as Map<String, Object?>?)?['flutter3d/schemaVersion'];
    }

    // Mutation: stamp the version only on tools added after it. `gust`
    // announces nothing however long the server runs.
    wind.declareSchemaVersion('1.0.0');
    expect(
      tools.named('wind.gust')!.spec.meta['flutter3d/schemaVersion'],
      '1.0.0',
    );
    expect(await metaOfGust(), '1.0.0');
    expect(tools.schemaVersions, <String, String>{'wind': '1.0.0'});

    // Mutation: leave the declaration untracked by the plugin's scope. A
    // plugin switched off would go on being named by `flutter3d.schema`.
    for (final registration in scope.kept) {
      registration.cancel();
    }
    expect(tools.schemaVersions, isEmpty);
    expect(tools.tools, isEmpty);

    await client.shutdown();
    await server.shutdown();
  });

  test('a running server offers the project\'s tools after its own and '
      'keeps the list in step as plugins come and go', () async {
    final tools = McpTools();
    final wind = tools.forPlugin(_Scope('wind', 0));
    final gust = wind.addTool(_tool('gust'), (_) => _says('blew'));

    final pipe = StreamChannelController<String>(sync: true);
    final called = <String>[];
    final server = _Server(
      pipe.local,
      projectTools: tools,
      onProjectCall: (AnsweredCall<ToolResult> call) =>
          called.add(call.toolName),
    );
    final (client, connection) = await _connect(pipe);

    expect(await _names(connection), <String>[
      'count',
      schemaToolName,
      'wind.gust',
    ]);
    final answer = await connection.callTool(
      CallToolRequest(name: 'wind.gust'),
    );
    expect((answer.content.single as TextContent).text, 'blew');
    expect(called, <String>['wind.gust']);

    // Mutation: register the project's tools once, in `initialize`, and
    // never listen. A plugin switched off leaves its tool listed, and one
    // switched on is never offered.
    gust.cancel();
    expect(await _names(connection), <String>['count', schemaToolName]);
    wind.addTool(_tool('calm'), (_) => _says('calmed'));
    expect(await _names(connection), <String>[
      'count',
      schemaToolName,
      'wind.calm',
    ]);

    await client.shutdown();
    await server.shutdown();
    // Mutation: keep listening after shutdown. A plugin switched on later
    // registers a tool on a server whose channel is closed.
    expect(
      () => wind.addTool(_tool('still'), (_) => _says('')),
      returnsNormally,
    );
  });

  test('a project tool named like the server\'s own is not offered, and '
      'the server says which', () async {
    final tools = McpTools();
    tools.forPlugin(_Scope('wind', 0)).addTool(_tool('gust'), (_) {
      return _says('the plugin');
    });
    final pipe = StreamChannelController<String>(sync: true);
    final server = _Server(
      pipe.local,
      projectTools: tools,
      own: const <String>['wind.gust'],
    );

    // Mutation: register project tools without the check. `registerTool`
    // throws on the second `wind.gust` and the server fails to start.
    final (client, connection) = await _connect(pipe);
    expect(await _names(connection), <String>['wind.gust', schemaToolName]);
    expect(server.shadowedProjectTools, <String>['wind.gust']);
    final answer = await connection.callTool(
      CallToolRequest(name: 'wind.gust'),
    );
    expect((answer.content.single as TextContent).text, 'wind.gust');

    await client.shutdown();
  });

  test('a project tool passes the brake and the argument check the '
      'server\'s own tools pass', () async {
    final tools = McpTools();
    final ran = <String>[];
    tools.forPlugin(_Scope('wind', 0)).addTool(
      _tool('gust', properties: <String, Schema>{'strength': NumberSchema()}),
      (Map<String, Object?> arguments) {
        ran.add('gust');
        return _says('blew');
      },
    );
    String? paused = 'a person has the brake on';
    final pipe = StreamChannelController<String>(sync: true);
    _Server(pipe.local, projectTools: tools, pausedBecause: () => paused);
    final (client, connection) = await _connect(pipe);

    // Mutation: register project tools with `registerTool`'s defaults. A
    // paused session runs the plugin's tool anyway.
    final refused = await connection.callTool(
      CallToolRequest(name: 'wind.gust'),
    );
    expect(refused.isError, isTrue);
    expect(
      (refused.content.single as TextContent).text,
      'a person has the brake on',
    );

    // Mutation: skip `refuseArguments`. A misspelt key runs the tool
    // without it, and the agent never learns it was misspelt.
    paused = null;
    final misspelt = await connection.callTool(
      CallToolRequest(
        name: 'wind.gust',
        arguments: <String, Object?>{'strenght': 2},
      ),
    );
    expect(misspelt.isError, isTrue);
    expect(
      (misspelt.content.single as TextContent).text,
      contains('"strenght"'),
    );
    expect(ran, isEmpty);

    final blew = await connection.callTool(
      CallToolRequest(
        name: 'wind.gust',
        arguments: <String, Object?>{'strength': 2},
      ),
    );
    expect(blew.isError, isNot(true));
    expect(ran, <String>['gust']);

    await client.shutdown();
  });

  test('the project server offers the plugins\' tools alone, and says the '
      'version its pubspec carries', () async {
    final tools = McpTools();
    tools.forPlugin(_Scope('wind', 0)).addTool(_tool('gust'), (_) {
      return _says('blew');
    });
    final pipe = StreamChannelController<String>(sync: true);
    ProjectMcpServer(pipe.local, tools: tools);
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

    // Mutation: leave `projectMcpVersion` behind when the pubspec moves. A
    // host reads one version and the package is another.
    final pubspec = RegExp(
      r'^version: (\S+)$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())?.group(1);
    expect((hello.serverInfo as Map<String, Object?>)['version'], pubspec);
    expect(await _names(connection), <String>[schemaToolName, 'wind.gust']);

    await client.shutdown();
  });
}
