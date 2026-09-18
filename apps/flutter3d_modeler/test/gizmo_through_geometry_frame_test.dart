/// `ux-03`: the gizmo reaches a pixel even when the model is in front of it.
///
///     flutter test test/gizmo_through_geometry_frame_test.dart
///
/// **The one thing the arithmetic could not answer.** `gizmo_handles_test`
/// holds every colour and every corner the drawing puts in a batch, and every
/// one of those passed against a build where, in the ordinary display mode,
/// the arrows simply were not on screen: they were written into a depth-tested
/// pass and drawn inside an opaque cube. What decides that is the depth
/// state, and the only thing that can be asked about a depth state is a
/// rendered pixel.
// Draws real pixels: a scene through the software rasteriser, a reference
// picture, or both. Tagged so a run that only wants the logic skips the whole
// slow class at once:
//
//     very_good test -x golden
//
// Not optional in CI, which runs the suite without the flag.
@Tags(<String>['golden'])
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_modeler/src/gizmo_handles.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter3d_modeler/src/transform_gizmo.dart';
import 'package:flutter3d_modeler/src/transform_modal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 160;
const int _height = 100;

/// How many pixels differ between two frames by more than [tolerance] on any
/// channel.
int _differing(Uint8List a, Uint8List b, {int tolerance = 8}) {
  var count = 0;
  for (var i = 0; i < a.length; i += 4) {
    if ((a[i] - b[i]).abs() > tolerance ||
        (a[i + 1] - b[i + 1]).abs() > tolerance ||
        (a[i + 2] - b[i + 2]).abs() > tolerance) {
      count++;
    }
  }
  return count;
}

/// How far a frame leans towards red over its own green and blue, summed.
///
/// The X arm is `#FF6B8A` and nothing else in this scene is warm, so a ghost
/// of the gizmo laid over a grey body moves this up and only this. A blended
/// pixel cannot be compared against a hex the way an opaque one can — that is
/// what `throughOpacity` does to it — so the measure has to be a direction
/// rather than a colour.
int _redLean(Uint8List rgba) {
  var total = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    final int lean = rgba[i] - (rgba[i + 1] + rgba[i + 2]) ~/ 2;
    if (lean > 0) total += lean;
  }
  return total;
}

({GraphicsDevice device, Renderer renderer, ModelerStage stage, MeshOverlay o})
_rig() {
  final it = cpuTestDevice(width: _width, height: _height);
  final renderer = Renderer.create(device: it.device);
  // `build` puts one cube at the origin and frames it — an opaque body with
  // the gizmo's own pivot inside it, which is exactly the case the live run
  // found the arrows missing in.
  final stage = ModelerStage.build(device: it.device);
  stage.frameSubject();
  // Close in, so the cube really does cover the gizmo. The arms are ninety-six
  // *pixels* long whatever the camera does (`kGizmoPixels`), and the body
  // grows as the camera approaches: framed from a comfortable distance the
  // arrows stick out past the silhouette and are visible with or without a
  // through pass, which would make this whole file prove nothing.
  stage.orbit
    ..distance = 0.9
    ..apply();
  final overlay = renderer.addContributor(
    MeshOverlay(
      vertexShader: renderer.debugLineVertexShader,
      fragmentShader: renderer.debugLineFragmentShader,
    ),
  );
  return (device: it.device, renderer: renderer, stage: stage, o: overlay);
}

Future<Uint8List> _draw(
  GraphicsDevice device,
  Renderer renderer,
  ModelerStage stage,
) async {
  final result = renderer.render(
    width: _width,
    height: _height,
    scene: stage.scene,
    views: stage.views(),
    settings: const RenderSettings(tonemap: false, exposure: 1.0),
  );
  final pixels = await device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels!.buffer.asUint8List();
}

/// Writes the move gizmo at the origin into [overlay], through geometry and
/// then over it — what `ModelerViewport._buildGizmo` does every frame.
void _writeGizmo(MeshOverlay overlay, ModelerStage stage, {bool ghost = true}) {
  final look = stage.overlayView(_height.toDouble());
  overlay
    ..clear()
    ..lookFrom(
      eye: look.eye,
      right: look.right,
      up: look.up,
      pixel: look.pixel,
      perspective: look.perspective,
    );
  final handles = gizmoHandles(
    Vector3.zero(),
    GizmoView(eye: look.eye, pixel: look.pixel, perspective: look.perspective),
  );
  const drawing = GizmoDrawing();
  void write() => drawing.writeInto(
    overlay,
    pivot: Vector3.zero(),
    handles: handles,
    kind: TransformKind.move,
  );
  if (ghost) overlay.throughGeometry(write);
  write();
}

void main() {
  test('an arrow inside an opaque cube still reaches the screen', () async {
    final withGhost = _rig();
    _writeGizmo(withGhost.o, withGhost.stage);
    final ghosted = await _draw(
      withGhost.device,
      withGhost.renderer,
      withGhost.stage,
    );

    final without = _rig();
    _writeGizmo(without.o, without.stage, ghost: false);
    final plain = await _draw(without.device, without.renderer, without.stage);

    // Mutation: drop the through pass and keep only the depth-tested copy,
    // which is what this was. The two frames are then the same frame: every
    // pixel of every arm is inside the body and loses the depth test, so the
    // gizmo is invisible in the display mode the editor opens in.
    expect(
      _differing(ghosted, plain),
      greaterThan(100),
      reason: 'the ghost pass changed nothing on screen',
    );

    // And what changed is the gizmo rather than some incidental shift: the
    // arms are warm against a grey body, so the frame leans redder.
    expect(_redLean(ghosted), greaterThan(_redLean(plain)));
  });

  test('a ghost is a ghost, not a second gizmo', () async {
    final rig = _rig();
    rig.o.throughOpacity = 0.35;
    _writeGizmo(rig.o, rig.stage);
    final ghosted = await _draw(rig.device, rig.renderer, rig.stage);

    final solid = _rig();
    solid.o.throughOpacity = 1.0;
    _writeGizmo(solid.o, solid.stage);
    final opaque = await _draw(solid.device, solid.renderer, solid.stage);

    // Mutation: ignore `throughOpacity` and write the handle's own alpha. The
    // hidden half of the gizmo is then as strong as the visible half, and
    // nobody can tell which part of it is in front of the model — the one
    // thing dimming the occluded pass is there to say.
    expect(_redLean(ghosted), lessThan(_redLean(opaque)));
  });
}
