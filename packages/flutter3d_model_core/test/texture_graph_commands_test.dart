/// `AddNode`/`Link`/`Unlink`/`SetNodeField`/`MoveNode`/`RemoveNode` —
/// `mat-13`'s own six verbs over a material's `TextureGraph`, node by node.
///
///     dart test test/texture_graph_commands_test.dart
library;

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// One material, unpainted, no objects.
ModelHistory painted() => ModelHistory(
  ModelProject(
    materials: <ProjectMaterial>[ProjectMaterial(surface: SurfaceMaterial())],
  ),
);

/// [painted] with a two-node graph already on its one material: a red colour
/// feeding `albedo`, and a lone `Levels` node nothing points at yet.
ModelHistory wired() {
  final history = ModelHistory(
    ModelProject(
      materials: <ProjectMaterial>[ProjectMaterial(surface: SurfaceMaterial())],
      // Higher than any id the fixture's own graph hands out below, so
      // `AddNode`'s own `project.nextId` allocation cannot collide with a
      // node this fixture built by hand rather than through a command.
      nextId: 4,
    ),
  );
  history.run(
    SetMaterialGraph(
      materialIndex: 0,
      graph: TextureGraph(
        nodes: <TextureNode>[
          ColorTextureNode(id: 1, value: Vector4(1, 0, 0, 1)),
          OutputTextureNode(id: 2, result: 1, slot: 'albedo'),
          const ChannelsTextureNode(id: 3),
        ],
      ),
    ),
  );
  return history;
}

void main() {
  group('AddNode', () {
    test('appends a node, at the id project.nextId handed out', () {
      final history = wired();
      final before = history.project.nextId;

      expect(
        history.run(
          AddNode(
            materialIndex: 0,
            kind: 'color',
            fields: <String, Object?>{
              'value': <double>[1, 1, 1, 1],
            },
            position: (12, 34),
          ),
        ),
        isNull,
      );

      final graph = history.project.materials.single.graph!;
      expect(graph.nodes, hasLength(4));
      final added = graph.nodeById(before)! as ColorTextureNode;
      expect(added.value, Vector4(1, 1, 1, 1));
      expect(graph.positions[before], (12.0, 34.0));
      expect(history.project.nextId, before + 1);
    });

    test('builds a graph from scratch when the material had none', () {
      final history = painted();
      expect(
        history.run(
          const AddNode(
            materialIndex: 0,
            kind: 'color',
            fields: <String, Object?>{
              'value': <double>[0, 0, 0, 1],
            },
          ),
        ),
        isNull,
      );
      expect(history.project.materials.single.graph!.nodes, hasLength(1));
    });

    test('refuses a kind missing a required field', () {
      final history = painted();
      expect(
        history.run(const AddNode(materialIndex: 0, kind: 'image')),
        contains('imageId'),
      );
    });

    test('refuses an unknown kind', () {
      final history = painted();
      expect(
        history.run(const AddNode(materialIndex: 0, kind: 'nonsense')),
        isNotNull,
      );
    });

    test('refuses a material that is not there', () {
      final history = painted();
      expect(
        history.run(const AddNode(materialIndex: 4, kind: 'color')),
        contains('4'),
      );
    });
  });

  group('Link', () {
    test('wires a compatible output into an input', () {
      final history = wired();
      expect(
        history.run(
          const Link(materialIndex: 0, nodeId: 3, input: 'source', from: 1),
        ),
        isNull,
      );
      final node =
          history.project.materials.single.graph!.nodeById(3)!
              as ChannelsTextureNode;
      expect(node.source, 1);
    });

    test('a colour into a scalar-only input is refused, not applied', () {
      final history = wired();
      // Node 2 is the Output feeding `albedo`, a colour input; node 3 is a
      // Channels node, whose own output is a scalar — feeding one into the
      // other is exactly the mismatch `TextureGraph.validate` exists for.
      expect(
        history.run(
          const Link(materialIndex: 0, nodeId: 2, input: 'result', from: 3),
        ),
        isNotNull,
      );
      final output =
          history.project.materials.single.graph!.nodeById(2)!
              as OutputTextureNode;
      expect(output.result, 1); // unchanged
    });

    test('refuses a link naming an input the node does not have', () {
      final history = wired();
      expect(
        history.run(
          const Link(materialIndex: 0, nodeId: 1, input: 'nope', from: 3),
        ),
        isNotNull,
      );
    });

    test('refuses a source node that is not in the graph', () {
      final history = wired();
      expect(
        history.run(
          const Link(materialIndex: 0, nodeId: 3, input: 'source', from: 99),
        ),
        isNotNull,
      );
    });
  });

  group('Unlink', () {
    test('clears a wired input back to null', () {
      final history = wired();
      history.run(
        const Link(materialIndex: 0, nodeId: 3, input: 'source', from: 1),
      );
      expect(
        history.run(const Unlink(materialIndex: 0, nodeId: 3, input: 'source')),
        isNull,
      );
      final node =
          history.project.materials.single.graph!.nodeById(3)!
              as ChannelsTextureNode;
      expect(node.source, isNull);
    });
  });

  group('SetNodeField', () {
    test('sets a plain field', () {
      final history = wired();
      expect(
        history.run(
          const SetNodeField(
            materialIndex: 0,
            nodeId: 3,
            field: 'channel',
            value: 'g',
          ),
        ),
        isNull,
      );
      final node =
          history.project.materials.single.graph!.nodeById(3)!
              as ChannelsTextureNode;
      expect(node.channel, TextureChannel.g);
    });

    test('refuses a link field; that is Link/Unlink\'s job', () {
      final history = wired();
      expect(
        history.run(
          const SetNodeField(
            materialIndex: 0,
            nodeId: 3,
            field: 'source',
            value: 1,
          ),
        ),
        isNotNull,
      );
    });

    test('refuses a value the wrong shape for the field', () {
      final history = wired();
      expect(
        history.run(
          const SetNodeField(
            materialIndex: 0,
            nodeId: 3,
            field: 'channel',
            value: 'not a channel',
          ),
        ),
        isNotNull,
      );
    });
  });

  group('MoveNode', () {
    test('sets a position without bumping the material version', () {
      final history = wired();
      history.run(const BakeTextureGraph(materialIndex: 0));
      final before = history.project.materials.single.version;

      expect(
        history.run(const MoveNode(materialIndex: 0, nodeId: 1, x: 5, y: 6)),
        isNull,
      );

      final material = history.project.materials.single;
      expect(material.graph!.positions[1], (5.0, 6.0));
      expect(material.version, before); // a drag is not an edit to bake over
      expect(material.isGraphStale, isFalse);
    });

    test('refuses a node that is not in the graph', () {
      final history = wired();
      expect(
        history.run(const MoveNode(materialIndex: 0, nodeId: 99, x: 0, y: 0)),
        isNotNull,
      );
    });
  });

  group('RemoveNode', () {
    test('drops the node from both nodes and positions', () {
      final history = wired();
      history.run(const MoveNode(materialIndex: 0, nodeId: 1, x: 7, y: 8));

      expect(
        history.run(const RemoveNode(materialIndex: 0, nodeId: 1)),
        isNull,
      );

      final graph = history.project.materials.single.graph!;
      expect(graph.nodes, hasLength(2));
      expect(graph.nodeById(1), isNull);
      expect(graph.positions.containsKey(1), isFalse);
    });

    test('unlinks every dangling reference to the removed node elsewhere '
        'in the graph', () {
      final history = wired();
      history.run(
        const Link(materialIndex: 0, nodeId: 3, input: 'source', from: 1),
      );
      // Node 2 (Output) already reads node 1 through `result` from `wired`'s
      // own fixture, and node 3 (Channels) now reads it through `source` —
      // removing node 1 should clear both, not just one.

      expect(
        history.run(const RemoveNode(materialIndex: 0, nodeId: 1)),
        isNull,
      );

      final graph = history.project.materials.single.graph!;
      final output = graph.nodeById(2)! as OutputTextureNode;
      final channels = graph.nodeById(3)! as ChannelsTextureNode;
      expect(output.result, isNull);
      expect(channels.source, isNull);
      expect(graph.validate(), isEmpty);
    });

    test('refuses a node that is not in the graph', () {
      final history = wired();
      expect(
        history.run(const RemoveNode(materialIndex: 0, nodeId: 99)),
        isNotNull,
      );
    });

    test('refuses a material that is not there', () {
      final history = wired();
      expect(
        history.run(const RemoveNode(materialIndex: 4, nodeId: 1)),
        contains('4'),
      );
    });

    test('an output node is not protected — this codebase has no invariant '
        'requiring a graph to keep one; BakeTextureGraph refuses on its own '
        'terms instead, at bake time', () {
      final history = wired();
      expect(
        history.run(const RemoveNode(materialIndex: 0, nodeId: 2)),
        isNull,
      );
      final graph = history.project.materials.single.graph!;
      expect(graph.nodeById(2), isNull);
      expect(graph.nodes.whereType<OutputTextureNode>(), isEmpty);
    });

    test('is one undo step, restoring the node and its dangling links', () {
      final history = wired();
      history.run(
        const Link(materialIndex: 0, nodeId: 3, input: 'source', from: 1),
      );
      final before = history.project;

      history.run(const RemoveNode(materialIndex: 0, nodeId: 1));
      expect(history.canUndo, isTrue);

      expect(history.undo(), isTrue);
      final graph = history.project.materials.single.graph!;
      expect(graph.nodeById(1), isNotNull);
      final output = graph.nodeById(2)! as OutputTextureNode;
      final channels = graph.nodeById(3)! as ChannelsTextureNode;
      expect(output.result, 1);
      expect(channels.source, 1);
      expect(history.project, same(before));
    });
  });

  group('journal round trip', () {
    test('every one of the six reads back from modelCommandFromJson', () {
      const commands = <ModelCommand>[
        AddNode(materialIndex: 0, kind: 'color'),
        Link(materialIndex: 0, nodeId: 3, input: 'source', from: 1),
        Unlink(materialIndex: 0, nodeId: 3, input: 'source'),
        SetNodeField(materialIndex: 0, nodeId: 3, field: 'channel', value: 'g'),
        MoveNode(materialIndex: 0, nodeId: 1, x: 5, y: 6),
        RemoveNode(materialIndex: 0, nodeId: 1),
      ];
      for (final command in commands) {
        final back = modelCommandFromJson(command.toJson());
        expect(back, isNotNull, reason: command.name);
        expect(back!.toJson(), command.toJson());
      }
    });
  });
}
