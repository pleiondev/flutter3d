/// `mat-32`'s own scenario, over the real MCP protocol: an agent paints a
/// table and places a light.
///
/// **Every material and lighting tool this row asks for, reached the way an
/// agent would reach them** — `tools/call`'s own JSON, not `ModelSession`'s
/// Dart API directly — with the project's own state checked afterward
/// through the `ModelSession` the server was handed, the same harness
/// `agent_builds_a_table_test.dart` and `bake_texture_graph_mcp_test.dart`
/// both use.
///
///     dart test test/paint_and_light_mcp_test.dart
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late ModelSession session;
  late MCPClient client;
  late ServerConnection connection;

  setUp(() async {
    workspace = Directory.systemTemp.createTempSync(
      'flutter3d_model_mcp_paint_and_light',
    );
    session = ModelSession.open('${workspace.path}/scene.f3dproj');
    final pipe = StreamChannelController<String>(sync: true);
    ModelMcpServer(pipe.local, session: session);

    client = MCPClient(
      Implementation(name: 'the suite', version: modelMcpVersion),
    );
    connection = client.connectServer(pipe.foreign);
    final ready = await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
    expect(ready.capabilities.tools, isNotNull);
    connection.notifyInitialized();
  });

  tearDown(() async {
    await client.shutdown();
    workspace.deleteSync(recursive: true);
  });

  Future<({bool did, String says})> call(
    String name, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    final result = await connection.callTool(
      CallToolRequest(name: name, arguments: arguments),
    );
    final content = result.content.single;
    expect(content.isText, isTrue, reason: '$name answered with $content');
    return (did: result.isError != true, says: (content as TextContent).text);
  }

  test('an agent paints a table and places a light', () async {
    // Build the table and select it.
    final top = await call('addPrimitive', <String, Object?>{
      'kind': 'box',
      'size': 1.2,
      'at': <double>[0, 1.0, 0],
    });
    expect(top.did, isTrue, reason: top.says);
    await call('rename', <String, Object?>{'id': 1, 'to': 'table top'});

    // Paint it: a material, painted by field, then assigned.
    final material = await call('addMaterial', <String, Object?>{
      'materialName': 'oak',
    });
    expect(material.did, isTrue, reason: material.says);

    final baseColor = await call('setMaterialField', <String, Object?>{
      'index': 0,
      'field': 'baseColor',
      'value': <double>[0.6, 0.35, 0.15, 1.0],
    });
    expect(baseColor.did, isTrue, reason: baseColor.says);

    final roughness = await call('setMaterialField', <String, Object?>{
      'index': 0,
      'field': 'roughness',
      'value': 0.8,
    });
    expect(roughness.did, isTrue, reason: roughness.says);

    final metallic = await call('setMaterialField', <String, Object?>{
      'index': 0,
      'field': 'metallic',
      'value': 0.0,
    });
    expect(metallic.did, isTrue, reason: metallic.says);

    // listMaterials shows a row's real numbers, not just its name.
    final listed = await call('listMaterials');
    expect(listed.did, isTrue, reason: listed.says);
    expect(listed.says, contains('oak'));
    expect(listed.says, contains('roughness 0.8'));

    final painted = await call('assignMaterial', <String, Object?>{
      'id': 1,
      'to': 0,
    });
    expect(painted.did, isTrue, reason: painted.says);

    // Place a light over the table and shape it.
    final added = await call('addLight', <String, Object?>{'type': 'point'});
    expect(added.did, isTrue, reason: added.says);

    final colored = await call('setLightField', <String, Object?>{
      'index': 0,
      'field': 'color',
      'value': <double>[1.0, 0.95, 0.85],
    });
    expect(colored.did, isTrue, reason: colored.says);

    final brightened = await call('setLightField', <String, Object?>{
      'index': 0,
      'field': 'intensity',
      'value': 3.5,
    });
    expect(brightened.did, isTrue, reason: brightened.says);

    final shadowed = await call('setLightField', <String, Object?>{
      'index': 0,
      'field': 'castsShadow',
      'value': true,
    });
    expect(shadowed.did, isTrue, reason: shadowed.says);

    // The scene around it: an environment preset and the shadow request.
    final environment = await call('setEnvironment', <String, Object?>{
      'preset': 'studio',
    });
    expect(environment.did, isTrue, reason: environment.says);

    final shadowsOn = await call('setSceneLightingField', <String, Object?>{
      'field': 'shadows',
      'value': true,
    });
    expect(shadowsOn.did, isTrue, reason: shadowsOn.says);

    expect((await call('check')).says, 'no issues');

    // Every edit landed on the one project this session shares with the
    // protocol calls above — not just a message saying so.
    final ModelProject project = session.history.project;

    expect(project.materials, hasLength(1));
    final SurfaceMaterial oak = project.materials.single.surface;
    expect(oak.name, 'oak');
    expect(oak.baseColor.r, closeTo(0.6, 1e-6));
    expect(oak.baseColor.g, closeTo(0.35, 1e-6));
    expect(oak.baseColor.b, closeTo(0.15, 1e-6));
    expect(oak.roughness, closeTo(0.8, 1e-6));
    expect(oak.metallic, 0.0);
    expect(project[1]!.materialSlots, <int>[0]);

    expect(project.lighting.lights, hasLength(1));
    final ProjectLight light = project.lighting.lights.single;
    expect(light.type, ProjectLightType.point);
    expect(light.color.r, closeTo(1.0, 1e-6));
    expect(light.color.g, closeTo(0.95, 1e-6));
    expect(light.color.b, closeTo(0.85, 1e-6));
    expect(light.intensity, closeTo(3.5, 1e-6));
    expect(light.castsShadow, isTrue);

    expect(project.lighting.environment, SceneEnvironmentPreset.studio);
    expect(project.lighting.shadows, isTrue);
  });

  test(
    'setMaterialField refuses a value the wrong shape for the field',
    () async {
      await call('addMaterial');
      final refused = await call('setMaterialField', <String, Object?>{
        'index': 0,
        'field': 'roughness',
        'value': 'not a number',
      });
      expect(refused.did, isFalse);
      expect(refused.says, contains('is not a material field'));
    },
  );

  test(
    'setLightField and removeLight refuse a light that is not there',
    () async {
      final refusedSet = await call('setLightField', <String, Object?>{
        'index': 0,
        'field': 'intensity',
        'value': 2.0,
      });
      expect(refusedSet.did, isFalse);
      expect(refusedSet.says, contains('there is no light 0'));

      final refusedRemove = await call('removeLight', <String, Object?>{
        'index': 0,
      });
      expect(refusedRemove.did, isFalse);
      expect(refusedRemove.says, contains('there is no light 0'));
    },
  );

  test(
    'linkMaterialFile adopts a look and embedMaterial detaches it again',
    () async {
      await call('addMaterial');
      final linked = await call('linkMaterialFile', <String, Object?>{
        'index': 0,
        'path': 'oak.fmat',
      });
      expect(linked.did, isTrue, reason: linked.says);
      expect(session.history.project.materials.single.fmat, 'oak.fmat');

      final embedded = await call('embedMaterial', <String, Object?>{
        'index': 0,
      });
      expect(embedded.did, isTrue, reason: embedded.says);
      expect(session.history.project.materials.single.fmat, isNull);
    },
  );

  test('listMaterials says so when the table is empty', () async {
    final empty = await call('listMaterials');
    expect(empty.did, isTrue, reason: empty.says);
    expect(empty.says, contains('no materials'));
  });
}
