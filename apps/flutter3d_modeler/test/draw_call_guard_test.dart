/// `view-22`: what one modeller frame costs in draw calls, written down.
///
///     flutter test test/draw_call_guard_test.dart
///
/// **A viewport gets slower one draw at a time.** Every overlay anybody adds
/// looks free on its own — a grid, a gizmo, a set of vertex handles — and the
/// frame that used to be five draws is fourteen by the time somebody notices,
/// with nothing in the history saying which commit did it. These are the
/// numbers, taken apart into what they are made of, so the commit that adds
/// one has to say so here.
///
/// **The row's own shorthand is `1 + 3 + 1 + N`, and the tree turns out to do
/// slightly better than that.** Measured rather than assumed: a frame is the
/// floor, the `N` objects, and the mesh overlay's three batches — and a batch
/// with nothing in it is not drawn at all, so the grid and the wire share one
/// line draw instead of paying for two. A new project in mesh mode with a
/// face selected is five: floor, cube, lines, solid handles, translucent
/// wash. The ceiling is what matters, and it is `1 + N + 3` whatever is
/// selected and however many elements are in it.
///
/// A guard and not a benchmark: counts on the software rasteriser, which
/// needs no GPU and gives the same answer on every machine.
///
/// **Written by breaking what it covers** (`ARCHITECTURE.md` rule 6.3). The
/// mutation: `if (batch.isEmpty) return;` in `mesh_overlay.dart` turned off,
/// so every batch is drawn whether or not anything is in it — the cheapest
/// way an extra draw gets into `MeshOverlay`. Three of the six go red,
/// *a mesh-mode frame never exceeds the floor, N and three* among them,
/// which is `view-22`'s own acceptance sentence.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_modeler/src/ground_grid.dart';
import 'package:flutter3d_modeler/src/mesh_overlay_builder.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter_test/flutter_test.dart';

const int _width = 160;
const int _height = 100;

/// The floor. It is in every viewport frame, and it is one draw.
const int kFloor = 1;

/// The most the mesh overlay can cost: lines, solid triangles, translucent
/// triangles. Fewer when a batch is empty.
const int kOverlayBatches = 3;

/// Draws one frame of [stage] and hands back what the renderer counted.
({int drawCalls, int pipelineSwitches}) _count(
  Renderer renderer,
  ModelerStage stage,
) {
  final result = renderer.render(
    width: _width,
    height: _height,
    scene: stage.scene,
    views: stage.views(),
    settings: const RenderSettings(),
  );
  return (
    drawCalls: result.drawCalls,
    pipelineSwitches: result.pipelineSwitches,
  );
}

/// The overlay a viewport builds every frame, registered and aimed.
({MeshOverlay overlay, MeshOverlayView view}) _overlayFor(
  Renderer renderer,
  ModelerStage stage,
) {
  final overlay = renderer.addContributor(
    MeshOverlay(
      vertexShader: renderer.debugLineVertexShader,
      fragmentShader: renderer.debugLineFragmentShader,
    ),
  );
  final look = stage.overlayView(_height.toDouble());
  overlay.lookFrom(
    eye: look.eye,
    right: look.right,
    up: look.up,
    pixel: look.pixel,
    perspective: look.perspective,
  );
  return (
    overlay: overlay,
    view: MeshOverlayView(
      eye: look.eye,
      right: look.right,
      up: look.up,
      pixel: look.pixel,
      perspective: look.perspective,
    ),
  );
}

void main() {
  test('object mode is the floor and the objects, and nothing else', () {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final stage = ModelerStage.build(device: it.device)..frameSubject();

    // N is one: a new project is the cube.
    expect(_count(renderer, stage).drawCalls, kFloor + 1);
  });

  test('an overlay with nothing in it is not drawn', () {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final stage = ModelerStage.build(device: it.device)..frameSubject();
    final bare = _count(renderer, stage).drawCalls;

    _overlayFor(renderer, stage);

    // **The one that makes the rest of this file mean anything.** If an empty
    // batch cost a draw, every mode would pay three whether or not it drew
    // anything, and the numbers below would stop describing the work.
    expect(_count(renderer, stage).drawCalls, bare);
  });

  test('the grid is one draw however many lines are in it', () {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final stage = ModelerStage.build(device: it.device)..frameSubject();
    final bare = _count(renderer, stage).drawCalls;

    final (:overlay, view: _) = _overlayFor(renderer, stage);
    const GroundGrid().writeInto(
      overlay,
      eye: stage.overlayView(_height.toDouble()).eye,
      fadeRadius: 1000,
    );

    // Hundreds of segments, one draw. That is the whole reason the overlay is
    // a batch rather than a node per line, and a change that made it a draw
    // per line would land here as a number in the hundreds instead of as a
    // frame that merely felt slower.
    expect(_count(renderer, stage).drawCalls, bare + 1);
  });

  test('the wire shares the grid\'s line draw rather than adding one', () {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final stage = ModelerStage.build(device: it.device)..frameSubject();
    final (:overlay, :view) = _overlayFor(renderer, stage);
    final look = stage.overlayView(_height.toDouble());

    const GroundGrid().writeInto(overlay, eye: look.eye, fadeRadius: 1000);
    final gridOnly = _count(renderer, stage).drawCalls;

    MeshOverlayBuilder(colours: MeshOverlayColours()).build(
      overlay,
      mesh: stage.editMesh!,
      selection: Selection.empty(ElementLevel.vertex),
      meshVersion: 1,
      selectionVersion: 1,
      view: view,
    );

    // The mesh's edges are lines and go into the batch the grid is already
    // in, so they cost nothing. What does cost one is the vertex handles,
    // which are solid triangles and a different batch.
    expect(_count(renderer, stage).drawCalls, gridOnly + 1);
  });

  test('a mesh-mode frame never exceeds the floor, N and three', () {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final stage = ModelerStage.build(device: it.device)..frameSubject();
    final (:overlay, :view) = _overlayFor(renderer, stage);
    final look = stage.overlayView(_height.toDouble());

    const GroundGrid().writeInto(overlay, eye: look.eye, fadeRadius: 1000);
    MeshOverlayBuilder(colours: MeshOverlayColours()).build(
      overlay,
      mesh: stage.editMesh!,
      // A selected face is the fullest the overlay gets: lines for the wire
      // and the grid, solid triangles for the handles and the ribbons of the
      // selected edges, and the translucent wash over the face itself.
      selection: Selection.of(ElementLevel.face, <int>[0]),
      meshVersion: 1,
      selectionVersion: 1,
      view: view,
    );

    const int objects = 1;
    expect(
      _count(renderer, stage).drawCalls,
      kFloor + objects + kOverlayBatches,
      reason:
          'the floor, $objects object and at most $kOverlayBatches overlay '
          'batches — an extra draw in MeshOverlay shows up right here',
    );
  });

  test('a second object is one more draw, not one more pipeline', () {
    final it = cpuTestDevice(width: _width, height: _height);
    final renderer = Renderer.create(device: it.device);
    final one = ModelerStage.build(
      device: it.device,
      stressTriangles: 64,
      stressObjects: 1,
    )..frameSubject();
    final two = ModelerStage.build(
      device: it.device,
      stressTriangles: 64,
      stressObjects: 2,
    )..frameSubject();

    final first = _count(renderer, one);
    final second = _count(renderer, two);

    expect(second.drawCalls, first.drawCalls + 1);
    // **`pipelines` doesn't grow** — `view-22`'s own words. Two objects on one
    // material are two draws under one pipeline; a change that gave each its
    // own would cost a state change per draw, and would land here long before
    // it landed on a phone.
    expect(second.pipelineSwitches, first.pipelineSwitches);
  });
}
