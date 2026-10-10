/// A contributor's render bundle, recorded for a pass whose depth runs
/// reversed — `A2.8`, readiness review §2.1.15.
///
/// The pass turns every depth test it is given, but a bundle keeps the state
/// it was recorded with and is replayed past that turning. So the bundle has
/// to be turned while it is recorded, which is what
/// `ContributorFrame.createRenderBundleEncoder` does.
///
///     dart test test/engine/reversed_bundle_test.dart
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _descriptor = RenderBundleDescriptor(
  colorFormats: <TextureFormat>[TextureFormat.r8g8b8a8UNormInt],
  depthStencilFormat: TextureFormat.d24UnormS8Uint,
);

ContributorFrame _frame(GraphicsDevice device, {required bool reversed}) =>
    ContributorFrame(
      encoder: FakePass(const RenderPassDescriptor(colors: <ColorTarget>[])),
      device: device,
      services: _NoServices(),
      settings: const RenderSettings(),
      width: 64,
      height: 48,
      reversedDepth: reversed,
    );

void main() {
  final device = FakeBackend(
    extraFeatures: const <DeviceFeature>[DeviceFeature.renderBundles],
  );

  test('a bundle recorded for a reversed pass has its depth tests turned', () {
    // Mutation: hand out the device's own encoder whatever the frame's
    // convention, as a contributor calling the device directly gets — the
    // bundle keeps `less` and, replayed into the reversed pass, draws only
    // what lies behind everything already there.
    final encoder = _frame(device, reversed: true).createRenderBundleEncoder(
      _descriptor,
    )..setDepthCompare(CompareFunction.less);
    final bundle = encoder.finish();

    expect((bundle.backend as FakePass).depthCompare, CompareFunction.greater);
  });

  test('and an ordinary pass gets the device\'s own encoder', () {
    // Mutation: turn whatever the frame — `less` comes back as `greater` for
    // a pass whose depth runs the ordinary way.
    final bundle = (_frame(device, reversed: false).createRenderBundleEncoder(
      _descriptor,
    )..setDepthCompare(CompareFunction.less)).finish();

    expect((bundle.backend as FakePass).depthCompare, CompareFunction.less);
  });
}

final class _NoServices with RenderServices {
  @override
  void encodeScene({
    required RenderFrame frame,
    required PassEncoder encoder,
    required Scene scene,
    required vm.Matrix4 viewProjection,
    required vm.Vector3 cameraPosition,
    int casterIndex = -1,
  }) => throw UnimplementedError();

  @override
  void drawFullscreen(FullscreenDraw draw) => throw UnimplementedError();
}
