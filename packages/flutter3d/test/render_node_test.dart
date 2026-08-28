import 'package:flutter3d/src/engine/render/frame_graph.dart';
import 'package:flutter3d/src/engine/render/render_node.dart';
import 'package:flutter_test/flutter_test.dart';

/// A node that throws if it is ever asked to draw.
///
/// Drawing needs a device, so the body cannot run here — but *whether the graph
/// asks* is scheduling, which is the whole subject. A node that throws makes
/// "it was not asked" an assertion rather than an assumption.
final class ThrowingNode extends RenderNode {
  const ThrowingNode(
    this.name, {
    this.reads = const <ResourceId>[],
    this.writes = const <ResourceId>[],
    this.isActive = true,
  });

  @override
  final String name;
  @override
  final List<ResourceId> reads;
  @override
  final List<ResourceId> writes;
  @override
  final bool isActive;

  @override
  void execute(NodeFrame frame) =>
      throw StateError('a culled node must never be asked to draw');
}

const ResourceId colour = ResourceId('colour');
const ResourceId overlay = ResourceId('overlay');
const ResourceId unwanted = ResourceId('unwanted');

void main() {
  test('a node that reads and writes the colour is a link in the chain', () {
    // Which is what every overlay is: it reads the finished scene and draws
    // over it. Two of them must not come out as depending on each other.
    final graph = FrameGraph()
      ..addExternal(colour)
      ..addNode(
        const ThrowingNode(
          'first',
          reads: <ResourceId>[colour],
          writes: <ResourceId>[colour],
        ),
      )
      ..addNode(
        const ThrowingNode(
          'second',
          reads: <ResourceId>[colour],
          writes: <ResourceId>[colour],
        ),
      );

    final compiled = graph.compile(outputs: const <ResourceId>[colour]);

    expect(compiled.order.map((n) => n.name), <String>['first', 'second']);
  });

  test('an inactive node takes its consumers with it', () {
    final graph = FrameGraph()
      ..addExternal(colour)
      ..addNode(
        const ThrowingNode(
          'off',
          reads: <ResourceId>[colour],
          writes: <ResourceId>[overlay],
          isActive: false,
        ),
      )
      ..addNode(
        const ThrowingNode(
          'reads it',
          reads: <ResourceId>[overlay],
          writes: <ResourceId>[unwanted],
        ),
      );

    final compiled = graph.compile(outputs: const <ResourceId>[colour]);

    expect(compiled.order, isEmpty);
    expect(
      compiled.culled.map((n) => n.name),
      containsAll(<String>['off', 'reads it']),
    );
  });

  test('a node nothing wants is never asked to draw', () {
    // ThrowingNode.execute throws. Nothing can call it, because the graph left
    // it out of the order — culling decides before a pass is set up, not after
    // one has been set up and discarded.
    final graph = FrameGraph()
      ..addExternal(colour)
      ..addNode(const ThrowingNode('ignored', writes: <ResourceId>[unwanted]));

    final compiled = graph.compile(outputs: const <ResourceId>[colour]);

    expect(compiled.order, isEmpty);
    expect(compiled.culled.map((n) => n.name), <String>['ignored']);
  });
}
