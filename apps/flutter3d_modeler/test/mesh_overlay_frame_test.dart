/// The mesh-editing overlay, drawn — not the batches `MeshOverlayBuilder`
/// fills, the pixels a person actually sees.
///
///     flutter test test/mesh_overlay_frame_test.dart
///
/// `mesh_overlay_builder_test.dart` counts vertices, ribbons and triangles the
/// builder hands to `MeshOverlay`; nothing there sends one through a pipeline.
/// A colour written into the wrong batch, or a batch built and never given to
/// a renderer the way `element_picking_test.dart`'s own subject once was not,
/// reads as a passing count and an empty frame. This draws through
/// `staging.dart`, the same stage the viewport builds, and asks the software
/// rasteriser what actually reached a pixel.
library;

import 'dart:typed_data';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_modeler/src/mesh_overlay_builder.dart';
import 'package:flutter3d_modeler/src/staging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 160;
const int _height = 100;

/// How many pixels of [rgba] land within [tolerance] of [colour] on every
/// channel, [colour] given as three 0..255 bytes.
///
/// A wider tolerance than `frame_test.dart`'s own wire-colour check needs:
/// that one reads a thousand-pixel floor and a whole wireframe, where most of
/// what is asked about is a line's own interior; a seven-pixel vertex handle
/// is mostly edge, and the rasteriser's own coverage antialiasing blends
/// those with whatever the lit surface under them already was. `40` still
/// sits nowhere near this file's three colours — the closest pair of them is
/// well over a hundred apart on some channel — so it cannot mistake one for
/// another; it only forgives what the handle's own edge costs it.
int _countNear(Uint8List rgba, List<int> colour, {int tolerance = 40}) {
  var count = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if ((rgba[i] - colour[0]).abs() <= tolerance &&
        (rgba[i + 1] - colour[1]).abs() <= tolerance &&
        (rgba[i + 2] - colour[2]).abs() <= tolerance) {
      count++;
    }
  }
  return count;
}

/// [colour] as the bytes it round-trips to with the composite's transfer
/// function turned off — the same trick `frame_test.dart`'s own wire-colour
/// assertion uses, and for the same reason: `MeshOverlay.asDrawn` treats every
/// colour handed to it as light, so comparing bytes only works with the tone
/// curve and the exposure both out of the way.
List<int> _bytesOf(Vector4 colour) => <int>[
  (colour.x * 255).round(),
  (colour.y * 255).round(),
  (colour.z * 255).round(),
];

/// A stage, a renderer and the overlay the viewport would build over it — the
/// three things every test here draws through.
({
  GraphicsDevice device,
  Renderer renderer,
  ModelerStage stage,
  MeshOverlay overlay,
})
_rig() {
  final it = cpuTestDevice(width: _width, height: _height);
  final renderer = Renderer.create(device: it.device);
  final stage = ModelerStage.build(device: it.device);
  stage.frameSubject();
  final overlay = renderer.addContributor(
    MeshOverlay(
      vertexShader: renderer.debugLineVertexShader,
      fragmentShader: renderer.debugLineFragmentShader,
    ),
  );
  return (
    device: it.device,
    renderer: renderer,
    stage: stage,
    overlay: overlay,
  );
}

/// The live vertex closest to [eye] — the one this stage's camera is looking
/// almost straight at, and so the one guaranteed not to be on the cube's far
/// side, where the depth test would refuse its handle and any colour picked
/// for it would never reach a pixel.
int _nearestVertex(EditMesh mesh, Vector3 eye) {
  var best = -1;
  var bestDistance = double.infinity;
  final at = Vector3.zero();
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
    if (!mesh.isVertexAlive(vertex)) continue;
    mesh.positionOf(vertex, at);
    final distance = (at - eye).length2;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = vertex;
    }
  }
  return best;
}

/// Where [world] lands in the rendered frame, in pixels — top-left origin, to
/// match how [Uint8List] rows come back from [GraphicsDevice.readPixels].
(int x, int y) _screenOf(ModelerStage stage, Vector3 world) {
  final ndc = stage.camera
      .viewProjection(_width / _height)
      .perspectiveTransform(Vector3.copy(world));
  return (
    ((ndc.x + 1) * 0.5 * _width).round(),
    ((1 - ndc.y) * 0.5 * _height).round(),
  );
}

/// Whether some pixel within [radius] of ([x],[y]) is near [colour].
bool _nearAt(
  Uint8List rgba,
  int x,
  int y,
  List<int> colour, {
  int radius = 6,
  int tolerance = 40,
}) {
  for (var dy = -radius; dy <= radius; dy++) {
    final row = y + dy;
    if (row < 0 || row >= _height) continue;
    for (var dx = -radius; dx <= radius; dx++) {
      final col = x + dx;
      if (col < 0 || col >= _width) continue;
      final i = (row * _width + col) * 4;
      if ((rgba[i] - colour[0]).abs() <= tolerance &&
          (rgba[i + 1] - colour[1]).abs() <= tolerance &&
          (rgba[i + 2] - colour[2]).abs() <= tolerance) {
        return true;
      }
    }
  }
  return false;
}

MeshOverlayView _viewOf(ModelerStage stage) {
  final look = stage.overlayView(_height.toDouble());
  return MeshOverlayView(
    eye: look.eye,
    right: look.right,
    up: look.up,
    pixel: look.pixel,
    perspective: look.perspective,
  );
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
    // Neutral composite, for the reason `frame_test.dart` turns it off for
    // its own wire-colour assertion: a design colour is not a light value,
    // and the tone curve would move every byte away from the hex it names.
    settings: const RenderSettings(tonemap: false, exposure: 1.0),
  );
  final pixels = await device.readPixels(result.frame);
  expect(pixels, isNotNull, reason: 'the frame could not be read back');
  return pixels!.buffer.asUint8List();
}

void main() {
  test(
    'a selected vertex is a handle in the selected colour, and the rest stay '
    'ordinary',
    () async {
      final rig = _rig();
      final edit = rig.stage.editMesh!;
      final colours = MeshOverlayColours();
      final view = _viewOf(rig.stage);
      final vertex = _nearestVertex(edit, view.eye);
      final at = Vector3.zero();
      edit.positionOf(vertex, at);
      final screen = _screenOf(rig.stage, at);

      MeshOverlayBuilder(colours: colours).build(
        rig.overlay,
        mesh: edit,
        selection: Selection.of(ElementLevel.vertex, <int>[vertex]),
        meshVersion: 1,
        selectionVersion: 1,
        view: view,
      );

      final rgba = await _draw(rig.device, rig.renderer, rig.stage);
      final ordinary = _countNear(rgba, _bytesOf(colours.vertex));

      // Mutation: swap `picked ? colours.selected : colours.vertex` in
      // `_emitHandles` for its own reverse. Every handle still gets drawn, in
      // one colour or the other — a check that only asked "does the selected
      // colour appear somewhere" would still pass, since it would just be
      // sitting on a different vertex. Reading the exact pixel the selected
      // vertex projects to is what tells the two apart.
      expect(
        _nearAt(rgba, screen.$1, screen.$2, _bytesOf(colours.selected)),
        isTrue,
        reason: 'the selected vertex has no handle in the selected colour',
      );
      expect(
        ordinary,
        greaterThan(0),
        reason: 'an unselected vertex has no handle at all',
      );
    },
  );

  test('a selected edge is a ribbon in the selected colour, not left as plain '
      'wire', () async {
    final rig = _rig();
    final edit = rig.stage.editMesh!;
    final colours = MeshOverlayColours();
    final edge = Selection.all(edit, ElementLevel.edge).ids.first;

    MeshOverlayBuilder(colours: colours).build(
      rig.overlay,
      mesh: edit,
      selection: Selection.of(ElementLevel.edge, <int>[edge]),
      meshVersion: 1,
      selectionVersion: 1,
      view: _viewOf(rig.stage),
    );

    final rgba = await _draw(rig.device, rig.renderer, rig.stage);
    final ribbon = _countNear(rgba, _bytesOf(colours.selected));

    // Mutation: build the overlay from an empty selection at the same
    // level instead of the one that names `edge` — the wireframe drawn
    // underneath has no orange anywhere in it, so a ribbon that never
    // reached the renderer leaves this at zero.
    expect(
      ribbon,
      greaterThan(0),
      reason: 'the selected edge has no ribbon drawn over it',
    );
  });

  test('a selected face washes over the surface, changing pixels a bare '
      'wireframe leaves alone', () async {
    final bare = _rig();
    MeshOverlayBuilder().build(
      bare.overlay,
      mesh: bare.stage.editMesh!,
      selection: Selection.empty(ElementLevel.face),
      meshVersion: 1,
      selectionVersion: 1,
      view: _viewOf(bare.stage),
    );
    final bareFrame = await _draw(bare.device, bare.renderer, bare.stage);

    final washed = _rig();
    final face = Selection.all(
      washed.stage.editMesh!,
      ElementLevel.face,
    ).ids.first;
    MeshOverlayBuilder().build(
      washed.overlay,
      mesh: washed.stage.editMesh!,
      selection: Selection.of(ElementLevel.face, <int>[face]),
      meshVersion: 1,
      selectionVersion: 1,
      view: _viewOf(washed.stage),
    );
    final washedFrame = await _draw(
      washed.device,
      washed.renderer,
      washed.stage,
    );

    var changed = 0;
    for (var i = 0; i < bareFrame.length; i++) {
      if ((bareFrame[i] - washedFrame[i]).abs() > 2) changed++;
    }

    // Mutation: have `_emitFill` return early for every selection level
    // instead of only the non-face ones. Both frames are built from the
    // same cube from the same camera, so with the wash gone they come back
    // identical and this is the only test in the repository that draws the
    // fill batch and reads it back.
    expect(
      changed,
      greaterThan(0),
      reason: 'a selected face changed nothing in the picture',
    );
  });
}
