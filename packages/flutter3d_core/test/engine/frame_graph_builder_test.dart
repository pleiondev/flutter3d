/// A node declares itself into a builder, and the frame is compiled from
/// what it declared: reads, writes and keeps, the resources it makes, and
/// where it asked to run.
///
///     dart test test/engine/frame_graph_builder_test.dart
///
/// Mutation: drop the `created` map from `_compileAfresh` and the second
/// test finds no descriptor; take the placement check out and the third
/// runs a node nobody placed.
library;

import 'package:flutter3d_core/src/engine/render/frame_graph.dart';
import 'package:flutter3d_core/src/engine/render/frame_resources.dart';
import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

const ResourceId _color = ResourceId('color');
const ResourceId _frame = ResourceId('frame');
const ResourceId _glow = ResourceId('acme.glow');
const ResourceId _mask = ResourceId('acme.mask');

/// A node that declares everything through `setup`, nothing through the
/// getters.
final class _Declaring extends FrameGraphNode {
  const _Declaring(this.name, this.declare, {this.isActive = true});

  @override
  final String name;

  final void Function(FrameGraphBuilder builder) declare;

  @override
  final bool isActive;

  @override
  void setup(FrameGraphBuilder builder) => declare(builder);
}

/// A node that declares through the getters, as every node before `setup`.
final class _Named extends FrameGraphNode {
  const _Named(this.name, {this.writes = const <ResourceId>[]});

  @override
  final String name;
  @override
  final List<ResourceId> writes;
}

final class _Compute extends PlacementRequest {
  const _Compute();

  @override
  String get name => 'compute';
}

final class _Placer extends FramePlacer {
  const _Placer(this.answer);

  final String? answer;

  @override
  Object? place(FramePlacementContext context) => answer;
}

final class _Source with FrameTextureSource {
  final List<RenderTargetDescriptor> asked = <RenderTargetDescriptor>[];

  @override
  TextureHandle acquire(RenderTargetDescriptor spec) {
    asked.add(spec);
    return wrapTexture(
      backend: 'acquired ${asked.length}',
      width: spec.width,
      height: spec.height,
      format: spec.format,
    );
  }

  @override
  void release(TextureHandle texture) {}
}

const ResourceDesc _glowDesc = ResourceDesc(
  id: _glow,
  format: TextureFormat.r16g16b16a16Float,
  size: FrameFraction(4),
);

const ResourceDesc _maskDesc = ResourceDesc(
  id: _mask,
  format: TextureFormat.r8g8b8a8UNormInt,
);

FrameGraph _graph(List<FrameGraphNode> nodes) {
  final graph = FrameGraph();
  nodes.forEach(graph.addNode);
  return graph;
}

void main() {
  test('a node declared through setup is ordered like one with getters', () {
    final compiled = _graph(<FrameGraphNode>[
      _Declaring('composite', (b) {
        b
          ..read(_color)
          ..readIfProduced(_glow)
          ..write(_frame);
      }),
      _Declaring('glow', (b) {
        b
          ..read(_color)
          ..create(_glowDesc);
      }),
      const _Named('scene', writes: <ResourceId>[_color]),
    ]).compile(outputs: const <ResourceId>[_frame]);

    expect(compiled.order.map((n) => n.name), <String>[
      'scene',
      'glow',
      'composite',
    ]);
  });

  test('a created resource is described, and only while its maker runs', () {
    final nodes = <FrameGraphNode>[
      const _Named('scene', writes: <ResourceId>[_color]),
      _Declaring('two outputs', (b) {
        b
          ..read(_color)
          ..create(_glowDesc)
          ..create(_maskDesc);
      }),
      _Declaring('composite', (b) {
        b
          ..read(_color)
          ..read(_glow)
          ..read(_mask)
          ..write(_frame);
      }),
    ];
    final compiled = _graph(nodes).compile(outputs: const <ResourceId>[_frame]);
    expect(compiled.descriptorOf(_glow), same(_glowDesc));
    expect(compiled.descriptorOf(_mask), same(_maskDesc));
    expect(compiled.created, hasLength(2));

    // The maker switched off: nothing is described, and the composite that
    // needed its outputs starves.
    final off = _graph(<FrameGraphNode>[
      nodes[0],
      _Declaring('two outputs', (b) => b.create(_glowDesc), isActive: false),
      nodes[2],
    ]).compile(outputs: const <ResourceId>[_frame]);
    expect(off.created, isEmpty);
    expect(off.descriptorOf(_glow), isNull);
  });

  test('the frame makes a created resource at its declared size', () {
    final compiled = _graph(<FrameGraphNode>[
      _Declaring('glow', (b) => b.create(_glowDesc)),
    ]).compile(outputs: const <ResourceId>[_glow]);
    final source = _Source();
    final resources = FrameResources(
      source: source,
      graph: compiled,
      frameWidth: 640,
      frameHeight: 480,
    )..beginNode(0);
    final texture = resources.texture(_glow);
    expect((texture.width, texture.height), (160, 120));
    expect(source.asked.single.format, TextureFormat.r16g16b16a16Float);
  });

  test('a node that asks where it runs is placed, or does not run', () {
    FrameGraph graph() => _graph(<FrameGraphNode>[
      _Declaring('particles', (b) {
        b
          ..place(const _Compute())
          ..write(_color);
      }),
    ]);

    final nowhere = graph().compile(outputs: const <ResourceId>[_color]);
    expect(nowhere.order, isEmpty);
    expect(nowhere.skipReason('particles'), PassSkip.unsupported);

    final refused = graph().compile(
      outputs: const <ResourceId>[_color],
      placer: const _Placer(null),
    );
    expect(refused.skipReason('particles'), PassSkip.unsupported);

    final placed = graph().compile(
      outputs: const <ResourceId>[_color],
      placer: const _Placer('sidecar'),
    );
    expect(placed.order.map((n) => n.name), <String>['particles']);
    expect(placed.placementOf<String>('particles'), 'sidecar');
    expect(placed.placementOf<int>('particles'), isNull);
  });

  test('the declarations a node made are readable without a compile', () {
    final declared = NodeDeclarations.of(
      _Declaring('glow', (b) {
        b
          ..read(_color)
          ..keep(const ResourceId('acme.history'))
          ..create(_glowDesc);
      }),
    );
    expect(declared.reads, <ResourceId>[_color]);
    expect(declared.writes, <ResourceId>[_glow]);
    expect(declared.keeps.single.name, 'acme.history');
    expect(declared.created.single, same(_glowDesc));
    expect(declared.placement, isNull);
  });
}
