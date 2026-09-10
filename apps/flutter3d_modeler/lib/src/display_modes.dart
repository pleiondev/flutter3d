/// Which lens the viewport looks through, what the surface is shaded with, and
/// where the camera stands for a named view.
///
/// **Three small decisions kept out of the widget, and the reason is the same
/// for all three: each of them is wrong in a way a picture cannot show.** A
/// lens swapped without carrying the framing across leaves the model a
/// different size, which reads as a bug in the zoom. A shading mode that
/// forgets what the material was cannot be switched back, which reads as the
/// model having been damaged. A named view whose yaw is a quarter turn out puts
/// the light on the wrong side, which reads as the model being modelled wrong.
/// None of those need a window to test and all of them need testing, so they
/// are here rather than in `main.dart`.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart';

/// What the camera projects through.
enum ViewLens {
  /// What a person sees, and what a game will render with.
  perspective,

  /// What a plan is drawn in: parallel edges stay parallel, and two things the
  /// same size measure the same on screen wherever they are. The reason a
  /// modeller has it at all is alignment — a face is flat on an axis or it is
  /// not, and only this lens tells you which.
  orthographic,
}

/// What the surface is drawn as.
enum ShadingMode {
  /// The material the model actually has.
  material,

  /// The surface normal as a colour, which is how a person finds a face that
  /// is inside out or a normal that was left unsmoothed.
  normals,

  /// The material with the wireframe over it, so the topology is visible
  /// against the shape it makes.
  wireframe,
}

/// The six views everything else in the interface is aimed at.
///
/// **Named for what is being looked at, not where the camera is.** The
/// orientation gizmo's `−X` label and the `Right` menu item are the same
/// instruction — stand on `+X` and look back along the axis — and giving the
/// two of them one name here is what stops the pair drifting apart.
enum StandardView { front, back, left, right, top, bottom }

/// Where the camera stands for [view].
///
/// Both angles are fixed rather than half of each being left alone. A side view
/// that kept whatever pitch the camera happened to have is not a side view, and
/// a top view that kept the yaw shows the model turned differently every time
/// it is asked for — which is the whole property a named view is asked for.
///
/// A top view asks for exactly a quarter turn and gets a hair less, because
/// `OrbitController` clamps it: at the pole itself the up vector has no answer
/// and the picture spins as the next drag crosses it. Asking for the pole and
/// letting the clamp decide how close is safe is better than naming the
/// tolerance twice.
({double yaw, double pitch}) placementOf(StandardView view) => switch (view) {
  StandardView.front => (yaw: 0.0, pitch: 0.0),
  StandardView.back => (yaw: math.pi, pitch: 0.0),
  StandardView.right => (yaw: math.pi / 2, pitch: 0.0),
  StandardView.left => (yaw: -math.pi / 2, pitch: 0.0),
  StandardView.top => (yaw: 0.0, pitch: math.pi / 2),
  StandardView.bottom => (yaw: 0.0, pitch: -math.pi / 2),
};

/// Points [orbit] at [view], over [seconds].
void lookFrom(
  OrbitController orbit,
  StandardView view, {
  double seconds = 0.25,
}) {
  final placement = placementOf(view);
  orbit.animateTo(yaw: placement.yaw, pitch: placement.pitch, seconds: seconds);
}

/// Puts [lens] on [camera], keeping the framing [orbit] has.
///
/// **The framing is carried across rather than reset**, which is the one thing
/// a lens switch has to get right: the model must be the size it already was.
/// `OrbitController` holds both halves of the framing in step — the orbit
/// distance and the orthographic height — so this only has to hand the right
/// one over, and `syncProjectionDepth` fills in the near and far planes on the
/// next frame the way it does for every other frame.
void useLens(CameraNode camera, ViewLens lens, OrbitController orbit) {
  camera.projection = switch (lens) {
    ViewLens.perspective => PerspectiveProjection(
      fovYRadians: orbit.framingFov,
    ),
    ViewLens.orthographic => OrthographicProjection(height: orbit.orthoHeight),
  };
}

/// What [mode] asks the renderer for, over the settings a viewport already has.
///
/// **A normals view is not a picture of light**, and the composite has to be
/// told so twice. The colour in the buffer *is* the number being read, and two
/// separate stages would otherwise change it on the way out: the tone curve
/// rolls the highlights off, and the exposure — 1.6 by default, because that is
/// what a lit scene wants — multiplies everything before it. A +Y face comes
/// out at 137, 249, 137 with both left on and at 159, 255, 159 with only the
/// curve turned off; at 128, 255, 128, which is what a +Y normal encodes as,
/// only when the exposure is neutral as well. The difference between the first
/// two and the third is a face nobody can tell from one leaning a few degrees.
///
/// The rest of a display mode is the materials' business, which is
/// [SurfaceShading]'s.
RenderSettings settingsFor(ShadingMode mode, RenderSettings over) =>
    over.copyWith(
      wireframe: mode == ShadingMode.wireframe,
      tonemap: mode != ShadingMode.normals,
      exposure: mode == ShadingMode.normals ? 1.0 : over.exposure,
    );

/// Swaps the subject's materials for a debug one and back.
///
/// **It remembers, and that is the whole class.** The obvious way to show
/// normals is to walk the subject and assign a normals material to every mesh
/// under it; the obvious way back is to assign the original — and by then there
/// is no original, because it was overwritten by the walk. A person who
/// switched to normals to check one face and switched back would find their
/// model had turned grey, permanently, with the undo stack unable to explain
/// it. So the first swap records what each node had.
///
/// Recorded per node rather than per material, because two nodes sharing one
/// material is the normal case — glTF splits a mesh at material boundaries and
/// the halves point at the same object — and the map has to put back what each
/// node was drawn with, not what the material was.
final class SurfaceShading {
  /// What each node was drawn with before anything was swapped.
  ///
  /// An identity map: two `Material` values that compare equal are still two
  /// materials as far as putting one back is concerned, and `SceneNode` has no
  /// equality of its own, so this is the default `Map` behaviour and is stated
  /// here so it is not "simplified" into something keyed by name.
  final Map<MeshNode, Material> _own = <MeshNode, Material>{};

  /// The one material every normals view is drawn with.
  ///
  /// Shared rather than one per node: the stage it selects reads the surface
  /// normal and nothing else, so every field but [Material.lighting] is
  /// ignored, and a fresh instance per node would only cost the render list a
  /// sort key it cannot use.
  static final Material normals = Material(
    name: 'normals',
    lighting: LightingModel.normals,
  );

  /// What [apply] was last asked for, which is what the chips read to know
  /// which of them is lit.
  ShadingMode get mode => _mode;
  ShadingMode _mode = ShadingMode.material;

  /// Draws everything under [subject] the way [mode] asks.
  ///
  /// Idempotent, and walked every time rather than skipped when the mode has
  /// not changed: a viewport calls this every frame rather than remembering to
  /// call it when a chip is pressed, and a model opened while the normals view
  /// is on brings nodes this has never seen. Skipping the walk would leave
  /// those drawn with their own material in a view that is meant to show
  /// normals — and, worse, leave them unrecorded, so switching back would be
  /// the first thing that ever assigned them anything.
  void apply(SceneNode subject, ShadingMode mode) {
    _mode = mode;
    subject.traverse((SceneNode node) {
      if (node is! MeshNode) return;
      final Material own = _own.putIfAbsent(node, () => node.material);
      node.material = mode == ShadingMode.normals ? normals : own;
    });
  }

  /// Forgets everything, for a subject that has been replaced.
  ///
  /// Without it the map holds every node of every model ever opened, and the
  /// scene graph they belong to cannot be collected.
  void forget() {
    _own.clear();
    _mode = ShadingMode.material;
  }
}
