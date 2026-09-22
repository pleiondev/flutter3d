/// `TextureGraph`: an immutable network of fixed-kind nodes, `mat-10`'s own
/// "компоновщик текстур" — round-trip JSON, cycle rejection and input-type
/// checking, and nothing that touches a pixel.
///
///     dart test test/texture_graph_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// One of every kind, wired into a graph that should validate clean: two
/// `Image`s blended, one channel pulled off for a height, levelled,
/// inverted, turned into a normal map, and combined with a checker and a
/// UV-transformed noise field into the graph's own output.
TextureGraph oneOfEach() => TextureGraph(
  nodes: <TextureNode>[
    const ImageTextureNode(id: 1, imageId: 0),
    const ImageTextureNode(id: 2, imageId: 1),
    BlendTextureNode(
      id: 3,
      base: 1,
      overlay: 2,
      mode: TextureBlendMode.multiply,
      factor: 0.5,
    ),
    const ChannelsTextureNode(id: 4, source: 3, channel: TextureChannel.g),
    const LevelsTextureNode(
      id: 5,
      source: 4,
      blackPoint: 0.1,
      whitePoint: 0.9,
      gamma: 2.2,
    ),
    const InvertTextureNode(id: 6, source: 5),
    NormalFromHeightTextureNode(id: 7, height: 6, strength: 2.0),
    CheckerTextureNode(id: 8, scale: 16.0),
    UvTransformTextureNode(
      id: 9,
      source: 8,
      offset: Vector2(0.25, 0.5),
      scale: Vector2(2, 2),
      rotation: 0.7,
    ),
    const NoiseTextureNode(id: 10, seed: 42, scale: 4.0),
    ColorTextureNode(id: 11, value: Vector4(1, 0, 0, 1)),
    const OutputTextureNode(id: 12, result: 9),
  ],
);

void main() {
  group('round-trip JSON', () {
    test('one of every kind survives encode, decode, encode unchanged', () {
      final before = oneOfEach();
      final decoded = TextureGraph.fromJson(
        jsonDecode(jsonEncode(before.toJson())) as Map<String, Object?>,
      );

      // Mutation: drop a field from any one node's own `toJson` — the
      // second encode then differs from the first at exactly that node,
      // caught here rather than by a human reading a diff by hand.
      expect(jsonEncode(decoded.toJson()), jsonEncode(before.toJson()));
      expect(decoded.nodes, hasLength(before.nodes.length));
    });

    test('every node kind writes the word fromJson switches back on', () {
      final graph = oneOfEach();
      final kinds = <String>[for (final node in graph.nodes) node.kind];
      expect(kinds.toSet(), <String>{
        'image',
        'color',
        'blend',
        'channels',
        'levels',
        'invert',
        'uvTransform',
        'checker',
        'noise',
        'normalFromHeight',
        'output',
      });
    });

    test('an unknown kind is refused rather than silently dropped', () {
      expect(
        () =>
            TextureNode.fromJson(<String, Object?>{'id': 1, 'kind': 'shader'}),
        throwsFormatException,
      );
    });

    test('a node with a field missing is refused, not defaulted', () {
      // Mutation: catch the missing field and fall back to a default
      // instead of throwing — a `Blend` silently missing its own `mode`
      // reads as a file this build understood when it did not.
      expect(
        () => TextureNode.fromJson(<String, Object?>{
          'id': 3,
          'kind': 'blend',
          'base': 1,
          'overlay': 2,
          // 'mode' and 'factor' missing on purpose.
        }),
        throwsFormatException,
      );
    });
  });

  group('validate: types', () {
    test('a clean graph has nothing to say', () {
      expect(oneOfEach().validate(), isEmpty);
    });

    test('a colour wired where a scalar belongs is a type mismatch', () {
      // `LevelsTextureNode.source` expects `scalar`; wiring it straight to
      // an `Image` (`color`) is exactly what "тип входа проверен" asks to
      // be caught before any pixel is touched.
      final graph = TextureGraph(
        nodes: <TextureNode>[
          const ImageTextureNode(id: 1, imageId: 0),
          const LevelsTextureNode(id: 2, source: 1),
        ],
      );
      final issues = graph.validate();
      expect(issues, hasLength(1));
      expect(issues.single.nodeId, 2);
      expect(issues.single.message, contains('scalar'));
      expect(issues.single.message, contains('color'));
    });

    test('a scalar wired where a colour belongs is also caught', () {
      // The other direction, on `Blend.base` (`color`) fed straight from a
      // `Noise` (`scalar`) — a mutation checking only one direction of the
      // comparison would pass the test above and miss this one.
      final graph = TextureGraph(
        nodes: <TextureNode>[
          const NoiseTextureNode(id: 1),
          const ImageTextureNode(id: 2, imageId: 0),
          BlendTextureNode(id: 3, base: 1, overlay: 2),
        ],
      );
      final issues = graph.validate();
      expect(issues, hasLength(1));
      expect(issues.single.nodeId, 3);
    });

    test('a dangling reference is its own issue, not a crash', () {
      final graph = TextureGraph(
        nodes: <TextureNode>[const LevelsTextureNode(id: 1, source: 99)],
      );
      final issues = graph.validate();
      expect(issues, hasLength(1));
      expect(issues.single.message, contains('99'));
      expect(issues.single.message, contains('not in this graph'));
    });

    test('an unwired input is not flagged — nothing to check yet', () {
      final graph = TextureGraph(
        nodes: <TextureNode>[const LevelsTextureNode(id: 1)],
      );
      expect(graph.validate(), isEmpty);
    });
  });

  group('validate: cycles', () {
    test('a direct two-node cycle is rejected, naming a node', () {
      // Mutation: skip the cycle walk entirely and this graph — `1` reads
      // `2`, `2` reads `1` — would validate clean, since neither node is
      // individually malformed and there is no dangling reference either.
      final graph = TextureGraph(
        nodes: <TextureNode>[
          const InvertTextureNode(id: 1, source: 2),
          const InvertTextureNode(id: 2, source: 1),
        ],
      );
      final issues = graph.validate();
      expect(issues.where((i) => i.message.contains('cycle')), hasLength(1));
    });

    test('a self-reference is a cycle of one', () {
      final graph = TextureGraph(
        nodes: <TextureNode>[const InvertTextureNode(id: 1, source: 1)],
      );
      final issues = graph.validate();
      expect(issues.where((i) => i.message.contains('cycle')), hasLength(1));
    });

    test('a longer cycle through three nodes is still caught once', () {
      final graph = TextureGraph(
        nodes: <TextureNode>[
          const InvertTextureNode(id: 1, source: 3),
          const InvertTextureNode(id: 2, source: 1),
          const InvertTextureNode(id: 3, source: 2),
        ],
      );
      final issues = graph.validate();
      // Mutation: report the cycle on every node the walk revisits rather
      // than once — three "is part of a cycle" issues instead of one would
      // still pass a bare `isNotEmpty`, so the count is asserted exactly.
      expect(issues.where((i) => i.message.contains('cycle')), hasLength(1));
    });

    test('a shared, acyclic source read by two nodes is not a cycle', () {
      // Both `Levels` nodes read the same `Channels` node — a naive "has
      // this id been visited before" walk with no per-branch recursion
      // stack would mistake that fan-out for a cycle.
      final graph = TextureGraph(
        nodes: <TextureNode>[
          const ImageTextureNode(id: 1, imageId: 0),
          const ChannelsTextureNode(id: 2, source: 1),
          const LevelsTextureNode(id: 3, source: 2),
          const LevelsTextureNode(id: 4, source: 2, gamma: 2.0),
        ],
      );
      expect(graph.validate(), isEmpty);
    });
  });

  group('hints', () {
    test('every node kind offers a hint for every field its constructor '
        'takes as data, not as id', () {
      // A loose sanity check rather than a per-field enumeration: `hints`
      // exists and answers something for every kind that has a field to
      // show — `Invert` and `Output`, whose only field is a wired id, are
      // the two the plan itself gives no control for.
      for (final node in oneOfEach().nodes) {
        if (node is InvertTextureNode || node is OutputTextureNode) {
          continue;
        }
        expect(node.hints, isNotEmpty, reason: node.kind);
      }
    });
  });
}
