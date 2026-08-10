import 'package:flutter_test/flutter_test.dart';

import 'package:flutter3d/src/engine/render/frame_graph.dart';

/// A node that does nothing but declare what it touches.
///
/// The graph never executes anything — it decides *what* to execute and in
/// what order — so a node with no body is the honest test subject. A real pass
/// here would let a test pass for reasons that have nothing to do with
/// scheduling.
final class TestNode extends FrameGraphNode {
  const TestNode(
    this.name, {
    this.reads = const <ResourceId>[],
    this.optionalReads = const <ResourceId>[],
    this.writes = const <ResourceId>[],
    this.isActive = true,
  });

  @override
  final String name;
  @override
  final List<ResourceId> reads;
  @override
  final List<ResourceId> optionalReads;
  @override
  final List<ResourceId> writes;
  @override
  final bool isActive;
}

const ResourceId colour = ResourceId('colour');
const ResourceId depth = ResourceId('depth');
const ResourceId bloom = ResourceId('bloom');
const ResourceId final_ = ResourceId('final');

List<String> names(List<FrameGraphNode> nodes) =>
    nodes.map((n) => n.name).toList();

void main() {
  group('ordering', () {
    test('a reader runs after its writer, whatever order they registered in',
        () {
      final graph = FrameGraph()
        ..addNode(const TestNode('composite',
            reads: <ResourceId>[bloom], writes: <ResourceId>[final_]))
        ..addNode(const TestNode('bloom', writes: <ResourceId>[bloom]));

      final compiled = graph.compile(outputs: <ResourceId>[final_]);

      expect(names(compiled.order), <String>['bloom', 'composite']);
    });

    test('independent nodes keep registration order', () {
      // Reproducibility is the point: two passes with no dependency between
      // them must come out the same way every frame, or the goldens flicker.
      final graph = FrameGraph()
        ..addExternal(colour)
        ..addNode(const TestNode('a', reads: <ResourceId>[colour],
            writes: <ResourceId>[final_]))
        ..addNode(const TestNode('b', reads: <ResourceId>[colour],
            writes: <ResourceId>[final_]));

      expect(names(graph.compile(outputs: <ResourceId>[final_]).order),
          <String>['a', 'b']);
    });

    test('a chain of three resolves end to end', () {
      final graph = FrameGraph()
        ..addNode(const TestNode('third',
            reads: <ResourceId>[bloom], writes: <ResourceId>[final_]))
        ..addNode(const TestNode('second',
            reads: <ResourceId>[colour], writes: <ResourceId>[bloom]))
        ..addNode(const TestNode('first', writes: <ResourceId>[colour]));

      expect(names(graph.compile(outputs: <ResourceId>[final_]).order),
          <String>['first', 'second', 'third']);
    });

    test('a node reading and writing one resource does not depend on itself',
        () {
      // Read-modify-write is how anything accumulates into a target, and a
      // self-edge would report it as a cycle.
      final graph = FrameGraph()
        ..addExternal(colour)
        ..addNode(const TestNode('accumulate',
            reads: <ResourceId>[colour], writes: <ResourceId>[colour]));

      expect(names(graph.compile(outputs: <ResourceId>[colour]).order),
          <String>['accumulate']);
    });

    test('two writers of one resource run in registration order', () {
      // There is no dependency to derive between them, so something has to
      // decide, and the only thing an application controls is the order it
      // registered them in.
      final graph = FrameGraph()
        ..addNode(const TestNode('under', writes: <ResourceId>[colour]))
        ..addNode(const TestNode('over', writes: <ResourceId>[colour]));

      expect(names(graph.compile(outputs: <ResourceId>[colour]).order),
          <String>['under', 'over']);
    });
  });

  group('culling', () {
    test('a node nothing wants does not run', () {
      final graph = FrameGraph()
        ..addNode(const TestNode('wanted', writes: <ResourceId>[final_]))
        ..addNode(const TestNode('ignored', writes: <ResourceId>[bloom]));

      final compiled = graph.compile(outputs: <ResourceId>[final_]);

      expect(names(compiled.order), <String>['wanted']);
      expect(names(compiled.culled), <String>['ignored']);
    });

    test('culling is transitive', () {
      final graph = FrameGraph()
        ..addNode(const TestNode('wanted', writes: <ResourceId>[final_]))
        ..addNode(const TestNode('feeds nobody',
            reads: <ResourceId>[bloom], writes: <ResourceId>[depth]))
        ..addNode(const TestNode('feeds that', writes: <ResourceId>[bloom]));

      expect(names(graph.compile(outputs: <ResourceId>[final_]).order),
          <String>['wanted']);
    });

    test('an inactive node takes its consumers with it, and does not throw',
        () {
      // Switching bloom off must remove the passes that only fed it. Reporting
      // an error instead would make every optional feature a special case in
      // the caller, which is the wiring this exists to delete.
      final graph = FrameGraph()
        ..addExternal(colour)
        ..addNode(const TestNode('bloom',
            reads: <ResourceId>[colour],
            writes: <ResourceId>[bloom],
            isActive: false))
        ..addNode(const TestNode('bloom composite',
            reads: <ResourceId>[bloom], writes: <ResourceId>[final_]))
        ..addNode(const TestNode('plain composite',
            reads: <ResourceId>[colour], writes: <ResourceId>[final_]));

      final compiled = graph.compile(outputs: <ResourceId>[final_]);

      expect(names(compiled.order), <String>['plain composite']);
      expect(names(compiled.culled),
          containsAll(<String>['bloom', 'bloom composite']));
    });

    test('everything runs when everything is wanted', () {
      final graph = FrameGraph()
        ..addNode(const TestNode('a', writes: <ResourceId>[colour]))
        ..addNode(const TestNode('b', writes: <ResourceId>[depth]));

      expect(
        names(graph.compile(outputs: <ResourceId>[colour, depth]).order),
        <String>['a', 'b'],
      );
    });
  });

  group('diagnostics', () {
    test('a resource nobody writes is rejected, and the message names both',
        () {
      final graph = FrameGraph()
        ..addNode(const TestNode('composite',
            reads: <ResourceId>[bloom], writes: <ResourceId>[final_]));

      expect(
        () => graph.compile(outputs: <ResourceId>[final_]),
        throwsA(isA<FrameGraphError>().having(
          (e) => e.message,
          'message',
          allOf(contains('composite'), contains('bloom')),
        )),
      );
    });

    test('an external resource satisfies a read', () {
      final graph = FrameGraph()
        ..addExternal(depth)
        ..addNode(const TestNode('reads depth',
            reads: <ResourceId>[depth], writes: <ResourceId>[final_]));

      expect(names(graph.compile(outputs: <ResourceId>[final_]).order),
          <String>['reads depth']);
    });

    test('a cycle is reported with the passes in it', () {
      final graph = FrameGraph()
        ..addNode(const TestNode('a',
            reads: <ResourceId>[bloom], writes: <ResourceId>[colour]))
        ..addNode(const TestNode('b',
            reads: <ResourceId>[colour], writes: <ResourceId>[bloom]))
        ..addNode(const TestNode('sink',
            reads: <ResourceId>[colour], writes: <ResourceId>[final_]));

      expect(
        () => graph.compile(outputs: <ResourceId>[final_]),
        throwsA(isA<FrameGraphError>().having(
          (e) => e.message,
          'message',
          allOf(contains('loop'), contains('a'), contains('b')),
        )),
      );
    });

    test('an output nobody produces is rejected', () {
      final graph = FrameGraph()
        ..addNode(const TestNode('a', writes: <ResourceId>[colour]));

      expect(
        () => graph.compile(outputs: <ResourceId>[final_]),
        throwsA(isA<FrameGraphError>()),
      );
    });

    test('two nodes of one name are rejected at registration', () {
      final graph = FrameGraph()..addNode(const TestNode('bloom'));

      expect(() => graph.addNode(const TestNode('bloom')),
          throwsA(isA<FrameGraphError>()));
    });
  });

  group('resource lifetime', () {
    test('a resource is last used by the last node that touches it', () {
      final graph = FrameGraph()
        ..addNode(const TestNode('write', writes: <ResourceId>[bloom]))
        ..addNode(const TestNode('read',
            reads: <ResourceId>[bloom], writes: <ResourceId>[final_]));

      final compiled = graph.compile(outputs: <ResourceId>[final_]);

      expect(compiled.lastUseOf(bloom), 1);
      expect(compiled.lastUseOf(final_), 1);
    });

    test('a resource nothing touches has no lifetime', () {
      final graph = FrameGraph()
        ..addNode(const TestNode('a', writes: <ResourceId>[final_]));

      expect(graph.compile(outputs: <ResourceId>[final_]).lastUseOf(bloom),
          isNull);
    });

    test('a culled node does not extend a lifetime', () {
      // The point of computing this at all: a texture handed back as early as
      // it can be is a texture the next pass can reuse. A pass that does not
      // run must not hold one open.
      final graph = FrameGraph()
        ..addNode(const TestNode('write', writes: <ResourceId>[bloom]))
        ..addNode(const TestNode('wanted',
            reads: <ResourceId>[bloom], writes: <ResourceId>[final_]))
        ..addNode(const TestNode('ignored',
            reads: <ResourceId>[bloom], writes: <ResourceId>[depth]));

      final compiled = graph.compile(outputs: <ResourceId>[final_]);

      expect(names(compiled.order), <String>['write', 'wanted']);
      expect(compiled.lastUseOf(bloom), 1);
      expect(compiled.resources, isNot(contains(depth)));
    });

    test('the resource list is what the frame actually touches', () {
      final graph = FrameGraph()
        ..addExternal(colour)
        ..addNode(const TestNode('a',
            reads: <ResourceId>[colour], writes: <ResourceId>[final_]));

      expect(graph.compile(outputs: <ResourceId>[final_]).resources,
          unorderedEquals(<ResourceId>[colour, final_]));
    });
  });

  group('the release schedule', () {
    test('releasedAfter names what that step was the last to touch', () {
      final graph = FrameGraph()
        ..addNode(const TestNode('write', writes: <ResourceId>[bloom]))
        ..addNode(const TestNode('read',
            reads: <ResourceId>[bloom], writes: <ResourceId>[final_]));

      final compiled = graph.compile(outputs: <ResourceId>[final_]);

      expect(compiled.releasedAfter(0), isEmpty);
      expect(compiled.releasedAfter(1),
          unorderedEquals(<ResourceId>[bloom, final_]));
    });

    test('an intermediate is released before the frame ends', () {
      // The saving this exists for: the bloom target goes back to the pool
      // after the composite reads it, not at the end of the frame, so the next
      // pass can be handed the same texture.
      final graph = FrameGraph()
        ..addNode(const TestNode('bloom', writes: <ResourceId>[bloom]))
        ..addNode(const TestNode('composite',
            reads: <ResourceId>[bloom], writes: <ResourceId>[colour]))
        ..addNode(const TestNode('present',
            reads: <ResourceId>[colour], writes: <ResourceId>[final_]));

      final compiled = graph.compile(outputs: <ResourceId>[final_]);

      expect(compiled.releasedAfter(1), <ResourceId>[bloom]);
      expect(compiled.releasedAfter(2),
          unorderedEquals(<ResourceId>[colour, final_]));
    });

    test('every resource is released exactly once', () {
      final graph = FrameGraph()
        ..addExternal(depth)
        ..addNode(const TestNode('a',
            reads: <ResourceId>[depth], writes: <ResourceId>[bloom]))
        ..addNode(const TestNode('b',
            reads: <ResourceId>[bloom], writes: <ResourceId>[final_]));

      final compiled = graph.compile(outputs: <ResourceId>[final_]);
      final released = <ResourceId>[
        for (var i = 0; i < compiled.order.length; i++)
          ...compiled.releasedAfter(i),
      ];

      expect(released, unorderedEquals(compiled.resources.toList()));
      expect(released.toSet().length, released.length);
    });
  });

  group('optional reads', () {
    test('an optional read keeps its producer alive', () {
      // Without this the shadow passes are culled: nothing declares a hard
      // read on a shadow map, so nothing wants what they produce.
      final graph = FrameGraph()
        ..addNode(const TestNode('shadows', writes: <ResourceId>[depth]))
        ..addNode(const TestNode('scene',
            optionalReads: <ResourceId>[depth],
            writes: <ResourceId>[final_]));

      expect(names(graph.compile(outputs: <ResourceId>[final_]).order),
          <String>['shadows', 'scene']);
    });

    test('an absent optional read does not starve the node', () {
      // And with this the scene survives shadows being switched off, which a
      // hard read would not allow: it would take the world with it.
      final graph = FrameGraph()
        ..addNode(const TestNode('shadows',
            writes: <ResourceId>[depth], isActive: false))
        ..addNode(const TestNode('scene',
            optionalReads: <ResourceId>[depth],
            writes: <ResourceId>[final_]));

      expect(names(graph.compile(outputs: <ResourceId>[final_]).order),
          <String>['scene']);
    });

    test('an optional read of a name nothing writes is still an error', () {
      // Optional is about this frame, not about spelling.
      final graph = FrameGraph()
        ..addNode(const TestNode('scene',
            optionalReads: <ResourceId>[bloom],
            writes: <ResourceId>[final_]));

      expect(() => graph.compile(outputs: <ResourceId>[final_]),
          throwsA(isA<FrameGraphError>()));
    });

    test('an optional read counts as a read for isRead and for lifetime', () {
      final graph = FrameGraph()
        ..addNode(const TestNode('shadows', writes: <ResourceId>[depth]))
        ..addNode(const TestNode('scene',
            optionalReads: <ResourceId>[depth],
            writes: <ResourceId>[final_]));

      final compiled = graph.compile(outputs: <ResourceId>[final_]);

      expect(compiled.isRead(depth), isTrue);
      expect(compiled.lastUseOf(depth), 1);
    });
  });

  test('a chain of read-modify-write nodes is not a loop', () {
    // Two overlays compositing onto one colour each read it and write it back.
    // "Depend on every writer" makes them depend on each other; the order is
    // the registration order the write rule already imposes.
    final graph = FrameGraph()
      ..addExternal(colour)
      ..addNode(const TestNode('first',
          reads: <ResourceId>[colour], writes: <ResourceId>[colour]))
      ..addNode(const TestNode('second',
          reads: <ResourceId>[colour], writes: <ResourceId>[colour]));

    expect(names(graph.compile(outputs: <ResourceId>[colour]).order),
        <String>['first', 'second']);
  });

  test('an empty graph asking for an external resource is not an error', () {
    // The frame that draws nothing but the clear.
    final graph = FrameGraph()..addExternal(colour);

    expect(graph.compile(outputs: <ResourceId>[colour]).order, isEmpty);
  });
}
