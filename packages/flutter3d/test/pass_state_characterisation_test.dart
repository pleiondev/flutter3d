/// What state each pass sets, in order, before anything factors it out.
///
/// The twelve places that configure a pass — viewport, scissor, primitive
/// type, polygon mode, cull mode, winding order, depth write, depth compare,
/// blend — are about to become named constants. This file is the acceptance
/// criterion for that: it snapshots the sequence each pass emits today, so the
/// refactor has to be a literal transcription rather than a hopeful one.
///
/// **Why not just the goldens.** They would catch a changed picture, in fifteen
/// minutes. They would not catch a state call added or dropped where the
/// picture happens not to change — and "happens not to change" is exactly the
/// condition under which the same edit breaks a *different* backend. The three
/// disagree here in three directions: on Impeller and the CPU backend any
/// `setDepthWrite` call turns writes on, mirroring a `flutter_gpu` bug, so an
/// added redundant call flips behaviour; on WebGL the setters are immediate
/// global GL calls and `beginRenderPass` resets only depth test and scissor,
/// so a *removed* call leaks the previous pass's value. The omissions in these
/// sequences are load-bearing, and this is what pins them.
///
/// The snapshots are written out in full rather than summarised. A test that
/// asserts "eight state calls" tells the next reader nothing about which eight.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/render/renderer.dart';
import 'package:flutter3d/src/engine/scene/camera_node.dart';
import 'package:flutter3d/src/engine/scene/scene.dart';
import 'package:flutter3d/src/engine/render/render_view.dart';
import 'package:flutter3d_graphics/flutter3d_graphics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_backend.dart';

/// One state call, as a short string, so a snapshot reads as a sequence.
String? _describe(Recorded command) => switch (command) {
      RecordedViewport(:final rect) =>
        'viewport ${rect.width}x${rect.height}@${rect.x},${rect.y}',
      RecordedScissor(:final rect) =>
        'scissor ${rect.width}x${rect.height}@${rect.x},${rect.y}',
      RecordedPrimitiveType(:final type) => 'primitive ${type.name}',
      RecordedPolygonMode(:final mode) => 'polygon ${mode.name}',
      RecordedCullMode(:final mode) => 'cull ${mode.name}',
      RecordedWindingOrder(:final order) => 'winding ${order.name}',
      RecordedDepthWrite(:final enabled) => 'depthWrite $enabled',
      RecordedDepthCompare(:final compare) => 'depthCompare ${compare.name}',
      RecordedBlend(:final state) =>
        'blend ${state == null ? 'off' : '${state.sourceColorFactor.name}/'
            '${state.destinationColorFactor.name}'}',
      RecordedDraw() => 'draw',
      _ => null,
    };

/// Every state call and draw a pass made, in order.
List<String> _sequence(FakePass pass) =>
    pass.commands.map(_describe).whereType<String>().toList();

void main() {
  late FakeBackend device;
  late Renderer renderer;

  setUp(() {
    device = FakeBackend();
    final texel = device.createTextureFromPixels(
      width: 1,
      height: 1,
      format: TextureFormat.r8g8b8a8UNormInt,
      pixels: ByteData(4),
    )!;
    renderer = Renderer.create(
      device: device,
      fallbackAlbedo: texel,
      fallbackNormal: texel,
    );
  });

  /// One frame of an empty scene, which is enough: the state a pass sets is
  /// established before anything is drawn into it, and an empty scene keeps the
  /// sequences short enough to read.
  List<List<String>> renderFrame({RenderSettings? settings}) {
    final scene = Scene(name: 'characterisation');
    final camera = CameraNode(name: 'eye');
    scene.root.add(camera);
    renderer.render(
      width: 64,
      height: 48,
      scene: scene,
      views: <RenderView>[RenderView(camera: camera)],
      settings: settings ??
          const RenderSettings(
            bloom: BloomSettings(enabled: false),
            shadows: ShadowSettings(enabled: false),
          ),
    );
    return device.passes.map(_sequence).toList();
  }

  test('the scene and composite passes set what they set, in order', () {
    final passes = renderFrame();

    // Printed as well as asserted. When this test fails after a refactor, the
    // useful output is both sequences side by side, and a reader should not
    // have to re-run it with a print added.
    // ignore: avoid_print
    print('passes: ${passes.length}');
    for (var i = 0; i < passes.length; i++) {
      // ignore: avoid_print
      print('  [$i] ${passes[i].join(' | ')}');
    }

    expect(passes, hasLength(2),
        reason: 'an empty scene with bloom and shadows off is the scene pass '
            'and the composite, and nothing else');

    expect(
      passes[0],
      <String>[
        'depthWrite true',
        'depthCompare less',
        'primitive triangle',
        'polygon fill',
        'viewport 64x48@0,0',
        'scissor 64x48@0,0',
      ],
      reason: 'the scene pass establishes depth and topology, then the view — '
          'and the view part repeats per view, because the debug overlay '
          'leaves the pass drawing lines',
    );

    expect(
      passes[1],
      <String>[
        'viewport 64x48@0,0',
        'scissor 64x48@0,0',
        'primitive triangle',
        'cull none',
        'blend off',
        'depthWrite false',
        'depthCompare always',
        'draw',
      ],
      reason: 'the composite is a full-screen draw with depth out of the way. '
          'Note what is *absent*: no polygon mode, where the scene pass sets '
          'one. Omissions are load-bearing — see the header',
    );
  });

  test('bloom adds passes that all set the same full-screen state', () {
    final passes = renderFrame(
      settings: const RenderSettings(
        bloom: BloomSettings(intensity: 1.0),
        shadows: ShadowSettings(enabled: false),
      ),
    );

    // ignore: avoid_print
    print('with bloom, passes: ${passes.length}');
    for (var i = 0; i < passes.length; i++) {
      // ignore: avoid_print
      print('  [$i] ${passes[i].join(' | ')}');
    }

    // **The two full-screen paths are not the same sequence, and finding that
    // out is what this file was written for.**
    //
    // `_drawFullscreen` and `_drawFullscreenAdditive` were described as
    // differing only in blend state and load action. They also differ in the
    // *order* they set state: the plain one sets blend before depth, the
    // additive one after. Nothing depends on it — these are independent pieces
    // of pass state — but it means the two cannot collapse into one call with
    // a different blend argument without changing one of the sequences, and a
    // refactor that did so quietly would have had nothing to notice it.
    //
    // Recorded rather than fixed. Fixing it is R3's business, and doing it here
    // would leave this file asserting what it had just changed.
    const plain = <String>[
      'primitive triangle',
      'cull none',
      'blend off',
      'depthWrite false',
      'depthCompare always',
    ];
    const additive = <String>[
      'primitive triangle',
      'cull none',
      'depthWrite false',
      'depthCompare always',
      'blend one/one',
    ];

    // Downsample and threshold: five passes, the plain order.
    for (var i = 1; i <= 5; i++) {
      expect(passes[i].where((c) => c != 'draw' && !c.startsWith('viewport') &&
              !c.startsWith('scissor')).toList(), plain,
          reason: 'pass \$i is a plain full-screen draw');
    }
    // Upsample: four passes, the additive order.
    for (var i = 6; i <= 9; i++) {
      expect(passes[i].where((c) => c != 'draw' && !c.startsWith('viewport') &&
              !c.startsWith('scissor')).toList(), additive,
          reason: 'pass \$i is an additive full-screen draw');
    }
    // And the composite is plain again.
    expect(passes[10].where((c) => c != 'draw' && !c.startsWith('viewport') &&
            !c.startsWith('scissor')).toList(), plain);
  });
}
