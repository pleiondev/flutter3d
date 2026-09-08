/// The blit that presents a frame must cover the canvas, not a corner of it.
///
///     flutter test --platform chrome test/present_scissor_test.dart
///
/// **This bug was live on the public demo pages and looked like a layout
/// mistake.** `blitFramebuffer` is one of the operations the scissor test
/// clips, and a render pass here enables `SCISSOR_TEST` with its own rectangle
/// and has no reason to put it back. So the presenting blit was clipped to
/// whatever the last pass had been drawing into: the frame appeared in the
/// bottom-left corner of the canvas — bottom left, because that is where GL
/// puts its origin — and the rest stayed black.
///
/// **Why nobody saw it for so long.** It only shows when the frame is *smaller*
/// than the canvas. On a 2x display the requested frame is larger, the scissor
/// covers the whole canvas, and the picture is perfect; on a 1x display in a
/// small embedded frame it is smaller, and three quarters of the canvas is
/// black. The person who found it was on a laptop looking at an embedded demo.
/// The one who could not reproduce it was on a retina screen.
///
/// And `debugCanvasState` reads the *middle* of the canvas, which is the last
/// place a shrinking blit stops reaching. Every diagnostic said the frame was
/// fine.
@TestOn('browser')
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_webgl/engine_shaders.dart';
import 'package:flutter3d_webgl/flutter3d_webgl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The canvas is deliberately larger than the frame drawn into it, which is the
/// whole of the case being tested: a browser window smaller than the size the
/// application opened its device at.
const int _canvas = 64;
const int _frame = 16;

void main() {
  test('presenting covers the canvas even when the frame is smaller', () {
    final device = WebGlDevice.create(
      width: _canvas,
      height: _canvas,
      sources: engineShaders,
    );
    if (device == null) fail('no WebGL2 context in this browser');
    addTearDown(device.dispose);

    final target = device.createTexture(
      const RenderTargetSpec(
        width: _frame,
        height: _frame,
        format: TextureFormat.r8g8b8a8UNormInt,
      ),
    );
    // A pass over the small target, which is what leaves the scissor set to
    // sixteen by sixteen. Clearing is enough — what is being tested is the
    // state the pass leaves behind, not what it drew.
    device
        .beginRenderPass(
          RenderPassDescriptor(
            colors: <ColorTarget>[
              ColorTarget(
                texture: target,
                clearValue: Vector4(0.0, 1.0, 0.0, 1.0),
              ),
            ],
          ),
        )
        .submit();

    device.present(target);

    // The far corner from GL's origin, and the one the clipped blit missed.
    final List<int> farCorner = device.debugCanvasPixelAt(
      _canvas - 1,
      _canvas - 1,
    );
    final List<int> nearCorner = device.debugCanvasPixelAt(0, 0);

    expect(
      nearCorner[1],
      greaterThan(200),
      reason: 'the blit did not happen at all',
    );
    expect(
      farCorner[1],
      greaterThan(200),
      reason:
          'the far corner of the canvas is black: the presenting blit was '
          'clipped by the scissor the last pass left enabled',
    );
  });
}
