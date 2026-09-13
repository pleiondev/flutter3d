/// A professional-modes flow, end to end, over the real MCP protocol: an
/// agent unwraps a cube's UV, gives it a level of detail, bakes a
/// (pre-supplied) simulation into shape keys, and exports the result — the
/// same harness `agent_builds_a_table_test.dart` uses for the basic-editing
/// flow and `rig_pipeline_mcp_test.dart` uses for rigging, but for the
/// phase-4 capabilities that had no scenario of their own tying them
/// together: `pro-uv-06`'s `unwrap`, `pro-lod-03`'s `addLod`, and
/// `pro-sim-02`/`pro-sim-05`'s bake-to-shapes-and-export.
///
///     dart test test/professional_modes_scenario_test.dart
///
/// **What this does not prove.** `applySimulationCache` is handed a cache
/// built directly in this file rather than one `BakeClothJobRequest`
/// produced — that command has no synchronous, single-call shape a tool
/// call could wait on, exactly `applySimulationCache`'s own tool
/// description says, so an agent always arrives with a cache from
/// somewhere else. This scenario picks up from there, the same boundary a
/// real agent would.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dart_mcp/client.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
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
    workspace = Directory.systemTemp.createTempSync('flutter3d_model_mcp_pro');
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

  test(
    'unwrap, a level of detail, a baked simulation turned into shapes, exported to GLB',
    () async {
      // A box, the same shape `agent_builds_a_table_test.dart` starts from.
      final built = await call('addPrimitive', <String, Object?>{
        'kind': 'box',
      });
      expect(built.did, isTrue, reason: built.says);
      const id = 1;

      // A box still knows it is a box; `unwrap` needs real topology.
      final converted = await call('bakeToMesh', <String, Object?>{'id': id});
      expect(converted.did, isTrue, reason: converted.says);

      // `pro-uv-06`: lay UV out for the whole mesh — nothing selected at
      // mesh level means "the whole mesh", the tool's own description.
      final selected = await call('select', <String, Object?>{
        'objects': <int>[id],
      });
      expect(selected.did, isTrue, reason: selected.says);
      final unwrapped = await call('unwrap');
      expect(unwrapped.did, isTrue, reason: unwrapped.says);

      // `pro-lod-03`: a second, cheaper level of detail for this object.
      final lod = await call('addLod', <String, Object?>{
        'id': id,
        'ratio': 0.5,
        'maxScreenFraction': 0.3,
      });
      expect(lod.did, isTrue, reason: lod.says);
      expect(session.project[id]!.lods, hasLength(1));
      expect(session.project[id]!.lods.single.ratio, 0.5);

      // `pro-sim-02`/`pro-sim-05`: a cache an agent arrived with (see the
      // library comment for why this file builds it rather than baking one
      // live), applied and turned into shape keys.
      final vertexSlots = (session.project[id]!.geometry as EditedGeometry)
          .mesh
          .vertexSlotCount;
      final cache = SimulationCache(
        vertexCount: vertexSlots,
        frames: <Float32List>[
          for (var f = 0; f < 6; f++)
            Float32List.fromList(<double>[
              for (var v = 0; v < vertexSlots; v++) ...<double>[
                f.toDouble(),
                f.toDouble(),
                f.toDouble(),
              ],
            ]),
        ],
      );
      final applied = await call('applySimulationCache', <String, Object?>{
        'objectId': id,
        'baseVersion': session.project[id]!.version,
        'cache': cache.toJson(),
      });
      expect(applied.did, isTrue, reason: applied.says);

      final baked = await call('bakeSimulationToShapes', <String, Object?>{
        'id': id,
        'maxKeys': 4,
      });
      expect(baked.did, isTrue, reason: baked.says);
      expect(session.project[id]!.shapeSet.keys, hasLength(4));

      // Export, and check the whole flow actually landed in the file an
      // agent would hand off — not just that each tool call answered true.
      final exported = await call('export', <String, Object?>{
        'to': '${workspace.path}/scene.glb',
      });
      expect(exported.did, isTrue, reason: exported.says);

      final bytes = await File('${workspace.path}/scene.glb').readAsBytes();
      final decoded = await GltfLoader().load(bytes);
      expect(decoded.surfaces, hasLength(1));
      final mesh = decoded.surfaces.single.mesh;

      // `pro-uv-06`'s own mark: the exported mesh carries texture
      // coordinates, not just position and normal.
      expect(mesh.layout.has(VertexLayout.texcoord), isTrue);

      // `pro-sim-05`'s own mark: four morph targets, one per baked shape
      // key, every new key starting at weight zero.
      expect(mesh.morphTargets, hasLength(4));
      expect(decoded.surfaces.single.morphWeights, everyElement(0.0));
    },
  );
}
