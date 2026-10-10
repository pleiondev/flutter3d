// A frame graph whose inputs did not change is not compiled again: the
// renderer builds the same graph every frame, and the compile is a search
// over every declaration the nodes make.
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:test/test.dart';

final class _Node extends FrameGraphNode {
  _Node(
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
}

const _color = ResourceId('color');
const _frame = ResourceId('frame');

List<FrameGraphNode> _nodes({bool blurOn = true}) => <FrameGraphNode>[
  _Node('scene', writes: const <ResourceId>[_color]),
  _Node(
    'blur',
    reads: const <ResourceId>[_color],
    writes: const <ResourceId>[_color],
    isActive: blurOn,
  ),
  _Node(
    'composite',
    reads: const <ResourceId>[_color],
    writes: const <ResourceId>[_frame],
  ),
];

CompiledFrameGraph _compile(FrameGraph graph, List<FrameGraphNode> nodes) {
  graph.clear();
  nodes.forEach(graph.addNode);
  return graph.compile(outputs: const <ResourceId>[_frame]);
}

void main() {
  test('the same nodes and inputs give back the same compiled graph', () {
    final graph = FrameGraph();
    final nodes = _nodes();
    final first = _compile(graph, nodes);
    // Mutation: compile afresh every time, and this is an equal graph but
    // another object.
    expect(identical(_compile(graph, nodes), first), isTrue);
  });

  test("a new frame's nodes with the same declarations run in its order", () {
    final graph = FrameGraph();
    final before = _compile(graph, _nodes());
    final now = _nodes();
    final after = _compile(graph, now);
    // The renderer makes its nodes again every frame: the cached order has
    // to hand back this frame's, or a pass runs with last frame's state.
    expect(after.order, <FrameGraphNode>[now[0], now[1], now[2]]);
    expect(after.order.map((n) => n.name), before.order.map((n) => n.name));
    expect(after.lastUseOf(_color), before.lastUseOf(_color));
  });

  test('a node switched off compiles again', () {
    final graph = FrameGraph();
    _compile(graph, _nodes());
    final off = _compile(graph, _nodes(blurOn: false));
    expect(off.order.map((n) => n.name), <String>['scene', 'composite']);
    expect(off.skipReason('blur'), PassSkip.settings);
    final on = _compile(graph, _nodes());
    expect(on.order.map((n) => n.name), <String>['scene', 'blur', 'composite']);
  });

  test('another output compiles again', () {
    final graph = FrameGraph();
    _compile(graph, _nodes());
    graph.clear();
    _nodes().forEach(graph.addNode);
    final colorOnly = graph.compile(outputs: const <ResourceId>[_color]);
    expect(colorOnly.order.map((n) => n.name), <String>['scene', 'blur']);
  });
}
