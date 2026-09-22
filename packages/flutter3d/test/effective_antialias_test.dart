/// `gfx-20n`: what smoothed the edges, as opposed to what was asked for.
///
///     flutter test test/effective_antialias_test.dart
///
/// **One setting, two mechanisms, and one of them turns itself off.**
/// Multisampling belongs to the scene pass's attachments and the post-process
/// pass is a node in the graph. Attachments in one target must agree on
/// sample count, so the moment anything consumes the surface buffer the scene
/// pass stops multisampling. Switch ambient occlusion on and the edges get
/// worse — a real, reproducible surprise with nothing anywhere saying why.
///
/// `FrameResult.skipped` is the general form of "asked for X, got Y" and it
/// cannot answer this one, because multisampling is not a pass and has no node
/// to report. That is the whole argument for a field beside it.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

FrameResult _frame(
  RenderSettings settings, {
  bool offscreenMsaa = true,
  int attachments = 2,
}) {
  final device = FakeBackend(maxColorAttachments: attachments)
    ..supportsOffscreenMsaa = offscreenMsaa;
  final renderer = Renderer.create(device: device);
  final scene = Scene()
    ..add(
      LightNode(intensity: 4.0)
        ..setPosition(2.0, 3.0, 4.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(CameraNode()..setPosition(0.0, 0.0, 4.0));
  return renderer.render(
    width: 64,
    height: 64,
    scene: scene,
    views: <RenderView>[RenderView(camera: scene.cameras.single)],
    settings: settings,
  );
}

void main() {
  test('a plain frame multisamples, and says so', () {
    final aa = _frame(const RenderSettings()).antiAliasing;

    expect(aa.msaaSamples, greaterThan(1));
    expect(aa.msaaDeclined, isNull);
    expect(aa.none, isFalse);
  });

  test('occlusion switched on takes the multisampling with it', () {
    // **The surprise this row exists for.** Nobody asked for less
    // anti-aliasing; they asked for occlusion, and the attachment rule did the
    // rest. Before this field the only evidence was that the edges looked
    // worse.
    final aa = _frame(
      const RenderSettings(
        ambientOcclusion: AmbientOcclusionSettings(enabled: true),
      ),
    ).antiAliasing;

    expect(aa.msaaSamples, 1);
    expect(
      aa.msaaDeclined,
      contains('surface buffer'),
      reason: 'the reason has to name the thing the caller can act on',
    );
  });

  test('the post-process pass is reported when it runs', () {
    final aa = _frame(
      const RenderSettings(antiAlias: AntiAliasSettings(enabled: true)),
    ).antiAliasing;

    expect(aa.fxaa, isTrue);
    expect(aa.none, isFalse);
  });

  test('and is not reported when it is switched off by name', () {
    // Through `disabledPasses` rather than through its own setting, because
    // the readback has to describe the frame rather than the settings — those
    // are two different things and telling them apart is the point.
    final aa = _frame(
      const RenderSettings(
        antiAlias: AntiAliasSettings(enabled: true),
        disabledPasses: <String>{'antialias'},
      ),
    ).antiAliasing;

    expect(aa.fxaa, isFalse);
  });

  test('a device with no offscreen multisampling says that instead', () {
    // The other of the two reasons, and a different thing to act on: this one
    // is the device, so no amount of changing settings will bring it back.
    final aa = _frame(
      const RenderSettings(),
      offscreenMsaa: false,
    ).antiAliasing;

    expect(aa.msaaSamples, 1);
    expect(aa.msaaDeclined, contains('device'));
  });

  test('the frame can report no anti-aliasing at all', () {
    final aa = _frame(
      const RenderSettings(),
      offscreenMsaa: false,
    ).antiAliasing;

    expect(aa.none, isTrue);
    expect(
      aa.toString(),
      contains('msaa declined'),
      reason: 'a HUD prints this, so it has to read as a sentence',
    );
  });

  test('a lens takes the multisampling too, for the same reason', () {
    // Not a special case in the code and not one here either: the rule is
    // about the buffer, so every reader of it has the same effect. This is
    // the check that the newest reader was not handled by a list somebody has
    // to remember to join.
    final aa = _frame(
      const RenderSettings(depthOfField: DepthOfFieldSettings(enabled: true)),
    ).antiAliasing;

    expect(aa.msaaSamples, 1);
    expect(aa.msaaDeclined, contains('surface buffer'));
  });

  test('on a device with one attachment the buffer is never read, so the '
      'multisampling stays', () {
    // `gfx-50n` and this row meeting: a device that cannot attach the buffer
    // culls every reader of it, so nothing consumes it and the scene pass
    // keeps multisampling. The degrade is in one direction only.
    final frame = _frame(
      const RenderSettings(
        ambientOcclusion: AmbientOcclusionSettings(enabled: true),
      ),
      attachments: 1,
    );

    expect(frame.antiAliasing.msaaSamples, greaterThan(1));
    expect(frame.antiAliasing.msaaDeclined, isNull);
    expect(frame.skipReasonOf('ssao'), PassSkip.unsupported);
  });
}
