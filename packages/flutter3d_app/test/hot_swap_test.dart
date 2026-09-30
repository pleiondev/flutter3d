/// What a hot reload does to a running world: relink every renderer, refresh
/// the bundles an application loaded itself, and keep the last bundle that
/// loaded when a new one does not.
///
///     flutter test test/hot_swap_test.dart
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

/// A renderer in software with one cube in front of it, so a frame links a
/// material pipeline a reload has to drop.
({Renderer renderer, Scene scene, RenderView view}) _stage() {
  final device = CpuDevice(
    width: 16,
    height: 9,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()..setPosition(0.0, 0.0, 4.0);
  final scene = Scene()
    ..add(camera)
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: Vector3.all(1.0)).build()),
        engine.Material(name: 'cube'),
      ),
    );
  return (
    renderer: Renderer.create(device: device),
    scene: scene,
    view: RenderView(camera: camera),
  );
}

void _draw(({Renderer renderer, Scene scene, RenderView view}) it) =>
    it.renderer.render(
      width: 16,
      height: 9,
      scene: it.scene,
      views: <RenderView>[it.view],
    );

/// Counts the times a renderer asked it to drop what it linked.
final class _Contributor extends PassContributor {
  int relinks = 0;

  @override
  bool get isActive => false;

  @override
  void encode(ContributorFrame frame) {}

  @override
  void relinkShaders() => relinks++;
}

/// A bundle an application loaded from bytes, refreshed from what [bytes]
/// says now; refuses whatever starts with a zero byte.
final class _Library implements LoadedShaderLibrary {
  final List<ByteData> refreshes = <ByteData>[];

  @override
  String get name => 'game';

  @override
  ShaderHandle? operator [](String name) => null;

  @override
  void refresh(ByteData bytes) {
    if (bytes.getUint8(0) == 0) {
      throw const ShaderBundleRefused(name: 'game', reason: 'not a bundle');
    }
    refreshes.add(bytes);
  }
}

ByteData _bytes(List<int> values) =>
    ByteData.sublistView(Uint8List.fromList(values));

void main() {
  test('a reload drops every pipeline the renderer and its contributors '
      'linked', () async {
    final it = _stage();
    final contributor = it.renderer.addContributor(_Contributor());
    final swap = HotSwap(enabled: true)
      ..registerRenderer(it.renderer);
    _draw(it);
    expect(it.renderer.pipelineCount, greaterThan(0));

    final report = await swap.swap();

    expect(report.renderers, 1);
    expect(it.renderer.pipelineCount, 0);
    expect(contributor.relinks, 1);
    // And the next frame links them again: the reload costs one frame's
    // links, not the picture.
    _draw(it);
    expect(it.renderer.pipelineCount, greaterThan(0));
  });

  test('a bundle is refreshed when its bytes change, and only then', () async {
    final library = _Library();
    var current = _bytes(<int>[1, 2, 3]);
    final swap = HotSwap(
      enabled: true,
    )..registerLibrary(library, read: () async => current, loadedFrom: current);

    expect((await swap.swap()).refreshed, isEmpty);
    expect(library.refreshes, isEmpty);

    current = _bytes(<int>[1, 2, 4]);
    expect((await swap.swap()).refreshed, <String>['game']);
    expect(library.refreshes, hasLength(1));

    expect((await swap.swap()).refreshed, isEmpty);
    expect(library.refreshes, hasLength(1));
  });

  test('a bundle that does not load keeps the last one that did, and is '
      'not tried again until it changes', () async {
    final library = _Library();
    var current = _bytes(<int>[1, 2, 3]);
    final swap = HotSwap(
      enabled: true,
    )..registerLibrary(library, read: () async => current, loadedFrom: current);

    current = _bytes(<int>[0, 9]);
    final refused = await swap.swap();
    expect(refused.refused, hasLength(1));
    expect(refused.refused.single, contains('not a bundle'));
    expect(library.refreshes, isEmpty);

    expect((await swap.swap()).refused, isEmpty);

    current = _bytes(<int>[1, 9]);
    expect((await swap.swap()).refreshed, <String>['game']);
  });

  test('two surfaces reassembling in one hot reload share one run', () async {
    final it = _stage();
    final contributor = it.renderer.addContributor(_Contributor());
    final swap = HotSwap(enabled: true)
      ..registerRenderer(it.renderer)
      ..registerRenderer(it.renderer);

    await Future.wait(<Future<HotSwapReport>>[swap.swap(), swap.swap()]);

    expect(contributor.relinks, 1);
  });

  test('outside a debug build nothing is held and nothing reloads', () async {
    final it = _stage();
    final contributor = it.renderer.addContributor(_Contributor());
    final swap = HotSwap(enabled: false)
      ..registerRenderer(it.renderer);

    final report = await swap.swap();

    expect(report.renderers, 0);
    expect(contributor.relinks, 0);
  });

  testWidgets('a hot reload of the app relinks the renderer a surface draws '
      'with', (WidgetTester tester) async {
    final it = _stage();
    final contributor = it.renderer.addContributor(_Contributor());
    await tester.pumpWidget(
      MaterialApp(
        home: SceneSurface(
          renderer: it.renderer,
          scene: it.scene,
          view: it.view,
          onBeforeFrame: () {},
          settings: () => const RenderSettings(),
          presentFrame:
              (
                GraphicsDevice device,
                TextureHandle frame, {
                BoxFit fit = BoxFit.fill,
                FilterQuality quality = FilterQuality.none,
              }) => const SizedBox.shrink(),
        ),
      ),
    );
    final before = HotSwap.instance.swaps.value;

    // Not awaited: it completes at the end of a frame, and a widget test has
    // frames only when it pumps them.
    unawaited(tester.binding.reassembleApplication());
    await tester.pump();
    await tester.pump();

    expect(contributor.relinks, 1);
    expect(HotSwap.instance.swaps.value, before + 1);
  });
}
