import 'package:flutter_test/flutter_test.dart';

import 'package:flutter3d/src/engine/render/frame_graph.dart';
import 'package:flutter3d/src/engine/render/render_node.dart';
import 'package:flutter3d/src/engine/render/render_plugin.dart';

/// A plugin that records whether it was asked to draw.
///
/// Encoding needs a render pass, so `encode` cannot run without a device — but
/// *whether the graph asks* is scheduling, and that is exactly what these
/// tests are about. The body never runs; only the decision to call it does.
final class SpyPlugin extends RenderPlugin {
  SpyPlugin({this.isActive = true});

  @override
  final bool isActive;

  @override
  RenderStage get stage => RenderStage.inScene;

  @override
  void encode(PluginFrame frame) =>
      throw StateError('a culled node must never be asked to draw');
}

const ResourceId colour = ResourceId('colour');
const ResourceId sparks = ResourceId('sparks');
const ResourceId unwanted = ResourceId('unwanted');

void main() {
  test('an adapted plugin schedules like any other node', () {
    final graph = FrameGraph()
      ..addExternal(colour)
      ..addNode(PluginNode(SpyPlugin(),
          name: 'particles',
          reads: const <ResourceId>[colour],
          writes: const <ResourceId>[sparks]));

    final compiled = graph.compile(outputs: const <ResourceId>[sparks]);

    expect(compiled.order.map((n) => n.name), <String>['particles']);
  });

  test('an inactive plugin is inactive as a node', () {
    // The old seam asked `isActive` per frame to skip pass setup. The graph
    // asks it once and then culls whatever only fed it, which is strictly more
    // than the plugin could do for itself.
    final graph = FrameGraph()
      ..addExternal(colour)
      ..addNode(PluginNode(SpyPlugin(isActive: false),
          name: 'particles',
          reads: const <ResourceId>[colour],
          writes: const <ResourceId>[sparks]))
      ..addNode(PluginNode(SpyPlugin(),
          name: 'reads sparks',
          reads: const <ResourceId>[sparks],
          writes: const <ResourceId>[unwanted]));

    final compiled = graph.compile(outputs: const <ResourceId>[colour]);

    expect(compiled.order, isEmpty);
    expect(compiled.culled.map((n) => n.name),
        containsAll(<String>['particles', 'reads sparks']));
  });

  test('a node nothing wants is never asked to draw', () {
    // SpyPlugin.encode throws if it is ever called. Nothing here can call it,
    // because the graph left the node out of the order entirely — which is the
    // assertion: culling decides *before* a pass is set up, not after one has
    // been set up and discarded.
    final graph = FrameGraph()
      ..addExternal(colour)
      ..addNode(PluginNode(SpyPlugin(),
          name: 'ignored', writes: const <ResourceId>[unwanted]));

    final compiled = graph.compile(outputs: const <ResourceId>[colour]);

    expect(compiled.order, isEmpty);
    expect(compiled.culled.map((n) => n.name), <String>['ignored']);
  });
}
