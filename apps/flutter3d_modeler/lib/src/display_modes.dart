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
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

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

/// The transform panel's own pivot options — one more than [TransformPivot]
/// carries.
///
/// **[cursor] is a name with nothing behind it.** `doc-33n` sketched a third
/// pivot, a 3D cursor, and a `SetCursor` command to place it, and stopped
/// short of building either — there is no position anywhere in the document
/// this could hand to a `RotateBy`. It stays in this enum, and the chip that
/// draws it stays disabled (see `PivotAndSpaceChips` in
/// `ui/properties/pivot_space_chips.dart`), so the panel shows the
/// three-way choice `ui-35n`'s own row asks for rather than quietly
/// shrinking it to the two that work.
enum PivotChip { median, individual, cursor }

/// What [chip] means to a command that only knows [TransformPivot].
///
/// Total rather than partial on purpose: a `switch` that assumes [chip] can
/// never be [PivotChip.cursor] because the chip is disabled today is a
/// `switch` waiting to be wrong the day it stops being disabled, silently
/// rather than at a case a compiler could have caught.
TransformPivot transformPivotOf(PivotChip chip) => switch (chip) {
  PivotChip.median => TransformPivot.median,
  PivotChip.individual => TransformPivot.individual,
  // Unreachable while the chip stays disabled. Median rather than a throw: an
  // agent driving the modeller through some future door this enum did not
  // anticipate gets the default a person would have gotten too, not a crash.
  PivotChip.cursor => TransformPivot.median,
};

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
/// **The rest of a display mode used to be the materials' business**, and
/// `gfx-43n` is what ended that. A normals view was drawn by walking the
/// subject, swapping every mesh's material for a debug one and remembering
/// what each had so it could be put back — a class whose own docstring
/// documented the two ways the remembering had already failed. The scene pass
/// writes the interpolated normal into its second attachment for reflections
/// and occlusion to read, and that is the same normal `normals.frag` showed,
/// so the view is now a setting over a buffer that exists. Nothing is
/// modified and there is nothing to restore.
///
/// [edgesDrawn] says the overlay is already drawing the mesh's own edges, in
/// which case the renderer is asked for no wireframe of its own — `ux-31`.
///
/// **The two draw different shapes, and only one of them is the model.** The
/// renderer's wireframe is the triangles it rasterises, so a cube of six
/// quads comes out as eighteen lines with a diagonal across every face: a
/// picture of how the GPU was fed rather than of the topology somebody is
/// editing. `MeshOverlayBuilder` walks the `EditMesh` and draws each edge
/// once — twelve for the same cube — which is the thing a modeller counts.
/// Where there is no `EditMesh` to walk (an imported surface, a shape that
/// still knows its own parameters) the renderer's own is still better than
/// nothing, and that is what [edgesDrawn] false leaves in place.
/// **`gfx-40n` fixed a bug here rather than tidying the call.** This used to
/// set `tonemap` and `exposure` and touch nothing else, so a normals view over
/// a viewport with bloom switched on returned a glowing debug buffer: the
/// colour a person read off a face was not the normal that face had. The
/// engine's own `CompositeMix` had the complete answer all along — it forces
/// exposure, tone mapping *and* bloom off, because a debug buffer is data
/// rather than light and any of the three would misreport it — and this was
/// one of three places that reproduced two thirds of it.
RenderSettings settingsFor(
  ShadingMode mode,
  RenderSettings over, {
  bool edgesDrawn = false,
}) {
  final base = over.copyWith(
    wireframe: mode == ShadingMode.wireframe && !edgesDrawn,
  );
  return mode == ShadingMode.normals
      // `gfx-43n`. The normal comes out of the surface buffer now, through a
      // pass that writes into the *finished* picture — so the colour a person
      // reads off a face is the number the buffer holds, with nothing after
      // it to change it. `forMeasurement` stays: exposure, the curve and the
      // glow no longer reach the shaded pixels, but a frame that draws a
      // bloom chain nobody sees is a frame paying for nothing.
      ? base.forMeasurement().copyWith(
          viewportShading: const ViewportShadingSettings(
            mode: ViewportShading.normals,
          ),
        )
      // **`tonemap: true` rather than whatever arrived**, which is what this
      // did before `forMeasurement` existed and is not incidental: leaving a
      // caller's `tonemap: false` in place would carry a debug frame's
      // settings into the lit view, and the first version of this change did
      // exactly that. Two mode screenshots moved before anything caught it.
      : base.copyWith(tonemap: true);
}
