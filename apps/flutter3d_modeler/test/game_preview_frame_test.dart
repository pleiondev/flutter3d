/// `S9`'s own golden: `game-preview.png`, the stage's default cube drawn
/// through `GamePreviewSettings` — `anim-24`'s own acceptance,
/// `triangles == 12`, the sky excluded from that count.
///
///     flutter test test/game_preview_frame_test.dart
///     flutter test test/game_preview_frame_test.dart --update-goldens
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;
import 'package:flutter3d_modeler/src/game_preview_settings.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_testing/flutter3d_testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the default cube previewed draws exactly twelve triangles — the sky '
      'excluded — and matches its reference frame', () async {
    final it = cpuTestDevice(width: 240, height: 160);
    final renderer = Renderer.create(
      device: it.device,
      fallbackAlbedo: it.albedo,
      fallbackNormal: it.normal,
    );
    final stage = ModelerStage.build(device: it.device);
    stage.frameSubject();

    final GamePreviewSettings preview = GamePreviewSettings.forProfile(
      const ProjectProfile(),
    );
    final RenderSettings settings = preview.applyTo(const RenderSettings());
    expect(
      settings.sky.enabled,
      isTrue,
      reason: 'a preview with no sky would not be exercising this row',
    );

    final withSky = renderer.render(
      width: 240,
      height: 160,
      scene: stage.scene,
      views: stage.views(),
      settings: settings,
    );

    // The stage's own default subject — a cuboid, six faces of two
    // triangles each — and nothing else: `ModelerStage.build` adds no
    // floor of its own (`material_studio_dialog.dart`'s own `_buildGround`
    // is a caller's addition, not the stage's).
    expect(
      withSky.triangles,
      12,
      reason: "the stage's own default cube is twelve triangles",
    );

    // The row this golden is *for*: verified, not assumed, that turning
    // the sky off changes nothing about the triangle count — a sky pass
    // that ever started padding this number would still leave the count
    // at 12 with `sky.enabled: false` and only 12 would move.
    final withoutSky = renderer.render(
      width: 240,
      height: 160,
      scene: stage.scene,
      views: stage.views(),
      settings: settings.copyWith(sky: const SkySettings(enabled: false)),
    );
    expect(
      withoutSky.triangles,
      withSky.triangles,
      reason: 'the sky must not be counted among the scene\'s own triangles',
    );

    final pixels = await it.device.readPixels(withSky.frame);
    expect(pixels, isNotNull, reason: 'the frame could not be read back');
    final RenderedFrame frame = (
      pixels: pixels!.buffer.asUint8List(),
      width: 240,
      height: 160,
      drawCalls: withSky.drawCalls,
    );

    await expectMatchesGolden(frame, 'test/goldens/game-preview.png');
  });
}
