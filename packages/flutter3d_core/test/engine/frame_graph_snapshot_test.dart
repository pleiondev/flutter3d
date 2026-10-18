/// A compiled frame graph written down: the passes that ran with the
/// versions they read and wrote, the ones left out with why, as JSON that
/// reads back and as Mermaid text.
///
///     dart test test/engine/frame_graph_snapshot_test.dart
library;

import 'dart:convert';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

const ResourceId _color = ResourceId('color');
const ResourceId _glow = ResourceId('acme.glow');
const ResourceId _shadow = ResourceId('shadow');
const ResourceId _frame = ResourceId('frame');

final class _Node extends FrameGraphNode {
  const _Node(
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

CompiledFrameGraph _compiled() {
  final graph = FrameGraph()
    ..addNode(const _Node('shadows', writes: <ResourceId>[_shadow]))
    ..addNode(
      const _Node(
        'scene',
        optionalReads: <ResourceId>[_shadow],
        writes: <ResourceId>[_color],
      ),
    )
    // Off by its own setting, so the shadow-free glow is skipped.
    ..addNode(
      const _Node(
        'glow',
        reads: <ResourceId>[_color],
        writes: <ResourceId>[_glow],
        isActive: false,
      ),
    )
    // Reads what the glow would have drawn: starved.
    ..addNode(
      const _Node(
        'glow_blur',
        reads: <ResourceId>[_glow],
        writes: <ResourceId>[_color],
      ),
    )
    ..addNode(
      const _Node(
        'composite',
        reads: <ResourceId>[_color],
        writes: <ResourceId>[_frame],
      ),
    );
  return graph.compile(outputs: const <ResourceId>[_frame]);
}

void main() {
  test('the passes that ran carry the versions they read and wrote', () {
    // Mutation: write the names without their versions. The composite's
    // read of color@1 cannot be told from the scene's write.
    final snapshot = _compiled().snapshot();
    expect(snapshot.passes.map((p) => p.name), <String>[
      'shadows',
      'scene',
      'composite',
    ]);
    expect(snapshot.passes[1].reads, <String, int>{'shadow': 1});
    expect(snapshot.passes[1].writes, <String, int>{'color': 1});
    expect(snapshot.passes[2].reads, <String, int>{'color': 1});
    expect(snapshot.outputs, <String>['frame']);
  });

  test('skipped passes are listed with why and what they declared', () {
    // Mutation: snapshot only `order`. The glow and its blur vanish, which
    // is the question a picture of the graph is asked.
    final skipped = _compiled().snapshot().skipped;
    expect(skipped.map((s) => (s.name, s.reason)), <(String, PassSkip)>[
      ('glow', PassSkip.settings),
      ('glow_blur', PassSkip.starved),
    ]);
    expect(skipped.first.reads, <String>['color']);
    expect(skipped.first.writes, <String>['acme.glow']);
  });

  test('the JSON reads back to the same snapshot', () {
    final snapshot = _compiled().snapshot();
    final text = jsonEncode(snapshot.toJson());
    final back = FrameGraphSnapshot.fromJson(
      (jsonDecode(text) as Map).cast<String, Object?>(),
    );
    expect(jsonEncode(back.toJson()), text);
    expect(back.skipped.last.reason, PassSkip.starved);
  });

  test('a document of another format or a newer version is refused', () {
    expect(
      () => FrameGraphSnapshot.fromJson(const <String, Object?>{
        'format': 'f3d.pipeline',
        'version': 1,
      }),
      throwsFormatException,
    );
    expect(
      () => FrameGraphSnapshot.fromJson(const <String, Object?>{
        'format': FrameGraphSnapshot.format,
        'version': FrameGraphSnapshot.version + 1,
      }),
      throwsFormatException,
    );
  });

  test('the Mermaid text draws versions, edges and dashed skipped passes', () {
    final mermaid = _compiled().snapshot().toMermaid();
    expect(mermaid, startsWith('flowchart LR\n'));
    expect(mermaid, contains('["scene"]'));
    expect(mermaid, contains('(["color@1"])'));
    expect(mermaid, contains('["glow (settings)"]:::skipped'));
    expect(mermaid, contains('["glow_blur (starved)"]:::skipped'));
    expect(mermaid, contains(' -.-> '));
    expect(mermaid, contains('classDef skipped'));
    // Every edge joins two nodes the text declared.
    final declared = RegExp(
      r'^  (n\d+)[\[(]',
      multiLine: true,
    ).allMatches(mermaid).map((m) => m.group(1)).toSet();
    for (final edge in RegExp(
      r'^  (n\d+) [-=.]+> (n\d+)$',
      multiLine: true,
    ).allMatches(mermaid)) {
      expect(declared, containsAll(<String?>[edge.group(1), edge.group(2)]));
    }
  });

  test('the renderer keeps the last drawn frame\'s graph', () {
    // Mutation: drop `_lastFrameGraph = frameGraph`. The editor's
    // `render_graph` answers that nothing was drawn.
    final device = FakeBackend();
    final camera = CameraNode();
    final scene = Scene()
      ..add(
        MeshNode(
          DeviceMesh.upload(device, CuboidShape().build()),
          RenderMaterial(),
        )..setPosition(0.0, 0.0, -5.0),
      )
      ..add(camera);
    final renderer = Renderer.create(device: device);
    expect(renderer.lastFrameGraph, isNull);
    final result = renderer.render(
      width: 64,
      height: 48,
      scene: scene,
      views: <CameraView>[CameraView(camera: camera)],
    );
    final snapshot = renderer.lastFrameGraph!.snapshot();
    expect(snapshot.passes.map((p) => p.name), <String>[
      for (final pass in result.passes) pass.name,
    ]);
    expect(
      snapshot.skipped.map((s) => s.name),
      containsAll(<String>[
        for (final s in result.skipped)
          if (renderer.lastFrameGraph!.culled.any((n) => n.name == s.name))
            s.name,
      ]),
    );
    expect(snapshot.skipped, isNotEmpty);
  });
}
