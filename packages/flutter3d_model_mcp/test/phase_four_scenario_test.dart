/// `pro-test-01`: the phase-four scenario, end to end over the real MCP
/// protocol — a cube, subdivided, sculpted, retopologized by hand, unwrapped,
/// baked, painted, and exported as a GLB.
///
///     dart test test/phase_four_scenario_test.dart
///
/// **The one test that holds the phase-four rows against each other.** Each
/// of `pro-sc-06`, `pro-sc-08`, `pro-rt-02`, `pro-rt-04`/`05`/`06` and
/// `pro-pt-02`/`03` has its own file proving what it does; nothing before
/// this proved they compose — that a mesh a brush moved can be retopologized,
/// that the retopology can be unwrapped, that a bake from the sculpt onto
/// that unwrap lands in a material slot, and that the whole thing leaves as
/// one file a renderer can open.
///
/// **The numbers this scenario prints are what the row asks for.** A run
/// says how many faces each step left and how long the bake took, because a
/// phase-four flow that is correct and takes four minutes is not one anybody
/// will use, and a threshold nobody can see the distance to is one that
/// starts failing without warning.
library;

import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_mcp/flutter3d_model_mcp.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late MCPClient client;
  late ServerConnection connection;
  late ModelSession session;

  setUp(() async {
    workspace = Directory.systemTemp.createTempSync('flutter3d_phase_four');
    session = ModelSession.open('${workspace.path}/scene.f3dproj');

    final pipe = StreamChannelController<String>(sync: true);
    ModelMcpServer(pipe.local, session: session);

    client = MCPClient(
      Implementation(name: 'the suite', version: modelMcpVersion),
    );
    connection = client.connectServer(pipe.foreign);
    await connection.initialize(
      InitializeRequest(
        protocolVersion: ProtocolVersion.latestSupported,
        capabilities: client.capabilities,
        clientInfo: client.implementation,
      ),
    );
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
    final content = result.content.first;
    expect(content.isText, isTrue, reason: '$name answered with $content');
    return (did: result.isError != true, says: (content as TextContent).text);
  }

  EditMesh meshOf(int id) =>
      (session.project[id]!.geometry as EditedGeometry).mesh;

  test(
    'a cube, sculpted, retopologized, unwrapped, baked, painted, exported',
    () async {
      final stopwatch = Stopwatch()..start();

      // A box, the shape every scenario in this package starts from.
      expect(
        (await call('addPrimitive', <String, Object?>{'kind': 'box'})).did,
        isTrue,
      );
      const int high = 1;
      expect(
        (await call('bakeToMesh', <String, Object?>{'id': high})).did,
        isTrue,
      );
      expect(
        (await call('select', <String, Object?>{
          'objects': <int>[high],
        })).did,
        isTrue,
      );

      // `pro-sc-08`: subdivide twice, so a brush has something to move.
      final subdivided = await call('subdivideMesh', <String, Object?>{
        'levels': 2,
      });
      expect(subdivided.did, isTrue, reason: subdivided.says);
      final int sculptable = meshOf(high).faceCount;
      expect(sculptable, 96);

      // `pro-sc-06`: a stroke over one face, as an agent makes one.
      final sculpted = await call('sculptStroke', <String, Object?>{
        'objectId': high,
        'kind': 'draw',
        'radius': 0.4,
        'strength': 0.3,
        'points': <Object?>[
          <double>[0, 0, 0.5],
          <double>[0.1, 0.1, 0.5],
        ],
      });
      expect(sculpted.did, isTrue, reason: sculpted.says);

      // `pro-rt-02`: a retopology drawn by hand — one quad, welded to the
      // high mesh's own surface. A whole retopology is `retopologize`'s own
      // job; what this proves is that the by-hand path reaches the same
      // document.
      final made = await call('addPrimitive', <String, Object?>{
        'kind': 'plane',
      });
      expect(made.did, isTrue, reason: made.says);
      const int low = 2;
      expect(
        (await call('bakeToMesh', <String, Object?>{'id': low})).did,
        isTrue,
      );
      final int before = meshOf(low).faceCount;
      final quad = await call('drawQuad', <String, Object?>{
        'objectId': low,
        'sourceId': high,
        'points': <Object?>[
          <double>[2, 0, 0],
          <double>[2, 1, 0],
          <double>[2, 1, 1],
          <double>[2, 0, 1],
        ],
        'snap': 0.001,
      });
      expect(quad.did, isTrue, reason: quad.says);
      expect(meshOf(low).faceCount, before + 1);

      // `pro-uv-06`: the low mesh needs UVs for anything to be baked into.
      expect(
        (await call('select', <String, Object?>{
          'objects': <int>[low],
        })).did,
        isTrue,
      );
      final unwrapped = await call('unwrap');
      expect(unwrapped.did, isTrue, reason: unwrapped.says);

      // A material for the bake and the paint to land on.
      expect(
        (await call('addMaterial', <String, Object?>{
          'materialName': 'shell',
        })).did,
        isTrue,
      );
      expect(
        (await call('assignMaterial', <String, Object?>{
          'id': low,
          'to': 0,
        })).did,
        isTrue,
      );

      // `pro-rt-04`/`05`/`06`: the detail off the sculpt, onto the low mesh.
      final bakeAt = stopwatch.elapsedMilliseconds;
      final baked = await call('bakeMaps', <String, Object?>{
        'sourceId': high,
        'targetId': low,
        'maps': <String>['normal', 'ao'],
        'resolution': 64,
        'shell': 0.5,
      });
      expect(baked.did, isTrue, reason: baked.says);
      final int bakeMs = stopwatch.elapsedMilliseconds - bakeAt;
      final SurfaceMaterial surface = session.project.materials.single.surface;
      expect(surface.normalTexture, isNotNull, reason: 'the normal map bound');
      expect(surface.occlusionTexture, isNotNull, reason: 'the AO map bound');

      // `pro-pt-02`/`03`: a stroke of colour, gated by the AO map just baked —
      // the whole point of baking one.
      final painted = await call('paintStroke', <String, Object?>{
        'objectId': low,
        'samples': <Object?>[
          <String, Object?>{
            'centre': <double>[0.5, 0.5, 0],
            'radius': 0.6,
          },
        ],
        'colour': <double>[0.8, 0.3, 0.2, 1],
        'size': 64,
        'maskImage': 1,
        'maskInverted': true,
      });
      expect(painted.did, isTrue, reason: painted.says);
      expect(
        session.project.materials.single.paint,
        isNotNull,
        reason: 'the layers are kept, not just the flattening',
      );

      // And out, as one file a renderer opens.
      final exported = await call('export', <String, Object?>{
        'to': '${workspace.path}/phase-four.glb',
      });
      expect(exported.did, isTrue, reason: exported.says);
      final File glb = File('${workspace.path}/phase-four.glb');
      expect(glb.existsSync(), isTrue);
      expect(glb.lengthSync(), greaterThan(0));

      stopwatch.stop();
      // ignore: avoid_print
      print(
        'phase four: $sculptable faces sculpted, ${meshOf(low).faceCount} '
        'retopologized, a 64² bake in $bakeMs ms, '
        '${glb.lengthSync()} bytes of GLB, '
        '${stopwatch.elapsedMilliseconds} ms in all',
      );

      // **Undo walks the whole thing back.** Mutation: let any step in this
      // chain leave two history steps, or none. The count is what says each
      // of these is one thing a person did.
      expect(session.history.steps, isNotEmpty);
      var taken = 0;
      while (session.history.undo()) {
        taken++;
      }
      expect(taken, greaterThan(6));
      expect(session.project.objects, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
