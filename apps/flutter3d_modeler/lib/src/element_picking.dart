/// Turning a click into a selection.
///
/// **The layer above `MeshPicker`, and the only one here that knows what a
/// pixel is.** That class answers three questions in world units — the face a
/// ray hits, the vertex or edge within some world radius of it, everything
/// inside a frustum — and refuses to grow a camera, because a viewport is the
/// only thing that knows how many world units a dozen logical pixels are at the
/// depth being looked at. This file is that viewport's half of the bargain: a
/// point on screen and a camera become a ray, a pointer kind becomes a radius
/// in pixels, the depth of whatever is under the pointer turns that radius into
/// world units, and a dragged rectangle becomes a frustum.
///
/// **Nothing here is a widget, and nothing here reads a global.** A pick is a
/// function of a mesh, a camera, a viewport size and a point, so a test can ask
/// what a click at (581, 119) selects without a render surface, a gesture
/// recogniser or a frame. The version of this that lived inside the viewport
/// widget could only be tested by pumping one, and every question about the
/// radius turned into a question about Flutter.
library;

import 'dart:ui' show Offset, PointerDeviceKind, Rect, Size;

import 'package:flutter3d/flutter3d.dart' show CameraNode;
import 'package:flutter3d_geometry/flutter3d_geometry.dart' show Ray;
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart' hide Ray;

/// How far from the pointer a vertex or an edge still counts, for a cursor, in
/// logical pixels.
const double cursorPickSlack = 8.0;

/// The same distance for a fingertip, which is three times as much.
///
/// **The three is a measurement, not a round number.** A logical pixel is about
/// a sixth of a millimetre — 160 to the inch on Android, 163 on iOS — so eight
/// of them is a millimetre and a third, which is about how far a hand moves a
/// cursor whose hotspot is a single pixel the person can see. A fingertip
/// presses eight to ten millimetres of glass and hides every one of them, so
/// the same confident click carries some four millimetres of doubt, and four
/// millimetres is twenty-four logical pixels.
///
/// One radius for both was the obvious alternative and it fails in whichever
/// direction it is set: eight everywhere makes selecting a vertex with a finger
/// a game of luck, and twenty-four everywhere makes a mouse click near the
/// middle of a face grab an edge the person can see they were nowhere near.
const double fingerPickSlack = 24.0;

/// The slack [pointer] earns, in logical pixels.
///
/// A stylus, a trackpad and a mouse all put a visible hotspot where the person
/// aimed, so they share the cursor's number. An unknown device is treated as a
/// finger: over-reaching picks the wrong element and the person clicks again,
/// while under-reaching on a touchscreen produces a click that does nothing at
/// all, which reads as the application being broken.
double pickSlackFor(PointerDeviceKind pointer) => switch (pointer) {
  PointerDeviceKind.touch || PointerDeviceKind.unknown => fingerPickSlack,
  _ => cursorPickSlack,
};

/// A camera and the box it draws into: enough to turn screen coordinates into
/// world ones.
///
/// **A value, rebuilt per pick, rather than a long-lived object with a
/// `resize`.** The camera moves every frame and the viewport size arrives from
/// layout, so anything cached here would be a second copy of two things that
/// already change under it; the matrices this builds cost a handful of
/// multiplies against the tree walk that follows.
final class PickingView {
  /// Throws for a viewport with no area, rather than asserting.
  ///
  /// A height of zero makes the aspect ratio infinite and the projection built
  /// from it singular; a size of zero in both directions makes it NaN
  /// throughout. Neither raises anything: `Matrix4.copyInverse` answers a
  /// determinant of zero by copying the matrix over unchanged and returning
  /// zero, so a ray unprojected afterwards comes from the projection matrix
  /// itself rather than from its inverse, and the pick answers something
  /// arbitrary with no error anywhere. An assert would say so in debug and go
  /// quiet in the build a person actually uses, which is the wrong way round
  /// for a failure this silent.
  PickingView({required this.camera, required this.size}) {
    if (size.isEmpty) {
      throw ArgumentError(
        'A viewport of $size has no area to pick in. A pointer event that '
        'arrives before layout has given the picture a size has nowhere to '
        'point, and the caller drops it rather than picking blind.',
      );
    }
  }

  final CameraNode camera;

  /// The viewport, in logical pixels — the same units the pointer arrives in.
  final Size size;

  /// The ray a click at [at] points along, in world space.
  ///
  /// **It starts on the near plane, and it is built by unprojecting two
  /// depths.** Taking the camera's world position and aiming it at the point
  /// would work for a perspective camera and be quietly wrong for an
  /// orthographic one, where every ray is parallel and none of them passes
  /// through the eye; unprojecting the same screen point at depth 0 and depth 1
  /// gives both cameras their correct ray, with no `is` check on the
  /// projection. Starting at the near plane rather than at the eye also matches
  /// what the person can see: geometry in front of the near plane is not on
  /// screen, so it is not clickable, and the depths [MeshPicker] compares are
  /// then depths from the first visible thing.
  Ray rayThrough(Offset at) {
    final inverse = Matrix4.copy(_worldToClip)..invert();
    final ndc = _ndcOf(at);
    final from = _unproject(inverse, ndc.x, ndc.y, 0.0);
    final to = _unproject(inverse, ndc.x, ndc.y, 1.0);
    return Ray(from, to - from).normalizeDirection();
  }

  /// How wide [pixels] logical pixels are in world units, [distance] along the
  /// ray through [at].
  ///
  /// **Measured by unprojecting, rather than from the field of view.** The
  /// arithmetic `2 * distance * tan(fov / 2) / height` is right for a
  /// [PerspectiveProjection] and gives nonsense for an orthographic camera and
  /// for the off-axis projection a headset hands over, and picking that behaves
  /// differently per projection type is picking that will be wrong in the view
  /// nobody tested. Two rays half the width apart, and the gap between them
  /// where the thing being picked actually is, needs to know nothing about
  /// which projection produced them.
  ///
  /// The two rays are separated horizontally, so a projection with different
  /// horizontal and vertical scale — which none of ours has — would be measured
  /// across rather than down.
  double worldWidthAt(
    Offset at, {
    required double pixels,
    required double distance,
  }) {
    final left = rayThrough(at.translate(-pixels / 2.0, 0.0)).pointAt(distance);
    final right = rayThrough(at.translate(pixels / 2.0, 0.0)).pointAt(distance);
    return (right - left).length;
  }

  /// The frustum a dragged [rect] cuts out of the world, or out of the space
  /// [objectToWorld] maps out of when there is one.
  ///
  /// **The matrix is remapped to OpenGL's depth range before it is handed
  /// over, and that is the whole subtlety.** `Frustum.setFromMatrix` reads the
  /// near plane as `w + z >= 0`, which is the `[-1, 1]` convention; every
  /// projection in this engine targets Metal and Vulkan's `[0, 1]`, where the
  /// near plane is `z >= 0`. Handing over the matrix as it stands puts the near
  /// plane about halfway to the eye — a box drag would then take in geometry
  /// between the camera and the near plane, which is invisible on screen and
  /// selected anyway. Doubling the depth row and subtracting w is exactly what
  /// `toDepthRange` does for a GL backend, for exactly the same reason.
  ///
  /// The same remap does the rectangle: mapping `[left, right]` to `[-1, 1]`
  /// in x and `[bottom, top]` to `[-1, 1]` in y turns the four side planes into
  /// the sides of the dragged box, which is why this is one matrix rather than
  /// six planes written by hand. Writing the planes was the first version, and
  /// it only worked because `Frustum.plane0` hands back the object the frustum
  /// stores; a vector_math that returned a copy would have left all six planes
  /// at zero, and a plane of zeroes reports every point as being on its inside.
  ///
  /// Throws for a rectangle with no area: its remap divides by zero, and the
  /// resulting planes of NaN report every point as inside, so a drag of two
  /// pixels would silently select the whole model.
  Frustum frustumOver(Rect rect, {Matrix4? objectToWorld}) {
    final box = Rect.fromPoints(rect.topLeft, rect.bottomRight);
    if (box.isEmpty) {
      throw ArgumentError(
        'A selection rectangle needs width and height, '
        'and $rect has none.',
      );
    }
    final low = _ndcOf(box.bottomLeft);
    final high = _ndcOf(box.topRight);

    final remap = Matrix4.zero()
      ..setEntry(0, 0, 2.0 / (high.x - low.x))
      ..setEntry(0, 3, -(high.x + low.x) / (high.x - low.x))
      ..setEntry(1, 1, 2.0 / (high.y - low.y))
      ..setEntry(1, 3, -(high.y + low.y) / (high.y - low.y))
      ..setEntry(2, 2, 2.0)
      ..setEntry(2, 3, -1.0)
      ..setEntry(3, 3, 1.0);

    final toClip = remap * _worldToClip as Matrix4;
    return Frustum.matrix(
      objectToWorld == null ? toClip : toClip * objectToWorld as Matrix4,
    );
  }

  Matrix4 get _worldToClip => camera.viewProjection(size.width / size.height);

  /// Where [at] falls in normalised device coordinates.
  ///
  /// Y is flipped and x is not: a pointer arrives with y growing downwards from
  /// the top of the viewport, and NDC has +Y up. Getting this wrong picks the
  /// mirror image of what the person clicked, which on a symmetrical model —
  /// a cube, the thing every test starts from — looks like nothing being wrong
  /// at all.
  ({double x, double y}) _ndcOf(Offset at) =>
      (x: 2.0 * at.dx / size.width - 1.0, y: 1.0 - 2.0 * at.dy / size.height);

  Vector3 _unproject(Matrix4 inverse, double x, double y, double depth) {
    final point = inverse.transform(Vector4(x, y, depth, 1.0));
    return Vector3(point.x / point.w, point.y / point.w, point.z / point.w);
  }
}

/// What a click at [at] picks, as a selection holding one element or none.
///
/// **The most specific element in reach wins: vertex, then edge, then face.**
/// Every vertex sits on an edge and every edge on a face, so a rule that
/// preferred the larger thing would make a vertex unclickable — the face is
/// always there too, and always in reach. Preferring the smaller one costs the
/// opposite mistake, a click near an edge that selects the edge when the person
/// meant the face, and that one the person sees immediately and corrects with a
/// click a few pixels further in.
///
/// [level] restricts the answer to one kind of element, which is what a
/// modeller in vertex or edge mode wants; leaving it null is the free mode
/// where all three are candidates.
///
/// [throughSurface] offers what the surface hides. Without it a vertex on the
/// far side of the model is not picked even when the ray runs straight through
/// it, which is what somebody working on the front of a model expects; with it,
/// the far side is fair game, which is what somebody deliberately reaching
/// through a shell wants.
///
/// [objectToWorld] is the transform of the object being edited, when it has
/// one. The ray is carried into the mesh's own space rather than the mesh being
/// carried into the world, because there are two of one and hundreds of
/// thousands of the other. A non-uniform scale has no single radius — a circle
/// on screen is an ellipse in a squashed object's space — and what this uses is
/// the scale along the ray, so picking on a squashed object is a little
/// generous across the squashed axis rather than wrong.
Selection pickElementAt(
  MeshPicker picker,
  PickingView view, {
  required Offset at,
  required PointerDeviceKind pointer,
  ElementLevel? level,
  bool throughSurface = false,
  Matrix4? objectToWorld,
}) {
  final ray = _intoMesh(view.rayThrough(at), objectToWorld);
  final hit = picker.bvh.raycast(ray.ray);

  // Face mode is answered here rather than at the bottom, and it is the same
  // answer: deleting this branch outright leaves every test in this file green,
  // which was run. What it saves is everything between — a radius that nothing
  // is going to be scanned against, the two unprojections that measure it, and,
  // for a click that misses the model, a pass over every vertex to find a depth
  // to measure it at. Face mode is where a modeller starts and this runs on
  // every hover as well as on every click, so the three lines pay for
  // themselves; what the tests pin is the answer, not the shortcut.
  if (level == ElementLevel.face) {
    return _one(ElementLevel.face, hit?.face ?? EditMesh.none);
  }

  // The radius has to be known before anything is scanned, and it depends on
  // how far away the thing being scanned for is — so the surface under the
  // pointer sets the depth. When the ray misses the model altogether, which is
  // what a click three pixels outside a silhouette edge does, the middle of the
  // mesh stands in for it: a click that near the model is a click at about the
  // model's distance, and the alternative is refusing to pick anything just
  // outside the outline, where half of the edges a person aims at are.
  final depth = hit?.distance ?? _depthOfCentre(picker.mesh, ray.ray);
  if (depth == null) return Selection.empty(level ?? ElementLevel.face);
  final radius =
      view.worldWidthAt(
        at,
        pixels: pickSlackFor(pointer),
        distance: depth / ray.shrink,
      ) *
      ray.shrink;

  if (level == null || level == ElementLevel.vertex) {
    final vertex = picker.vertexNear(
      ray.ray,
      radius: radius,
      visibleOnly: !throughSurface,
    );
    if (vertex != EditMesh.none) {
      return _one(ElementLevel.vertex, vertex);
    }
    if (level != null) return Selection.empty(ElementLevel.vertex);
  }

  if (level == null || level == ElementLevel.edge) {
    final edge = picker.edgeNear(
      ray.ray,
      radius: radius,
      visibleOnly: !throughSurface,
    );
    if (edge != EditMesh.none) return _one(ElementLevel.edge, edge);
    if (level != null) return Selection.empty(ElementLevel.edge);
  }

  return _one(ElementLevel.face, hit?.face ?? EditMesh.none);
}

/// Everything of [level] the dragged [rect] encloses.
///
/// **A box drag reaches through the model, and a click does not.** The
/// rectangle is a statement about a region rather than about the nearest
/// surface, so the vertices behind the ones on top are in it too — which is how
/// somebody selects the whole of a limb in one gesture, and why there is no
/// `throughSurface` here to turn off.
///
/// A rectangle dragged up and to the left arrives with its corners the wrong
/// way round; it means the same region, so it is normalised rather than
/// refused. A rectangle of no area selects nothing, which is what a click that
/// happened to be delivered as a drag should do.
Selection pickElementsIn(
  MeshPicker picker,
  PickingView view, {
  required Rect rect,
  required ElementLevel level,
  Matrix4? objectToWorld,
}) {
  final box = Rect.fromPoints(rect.topLeft, rect.bottomRight);
  if (box.isEmpty) return Selection.empty(level);
  return picker.inFrustum(
    view.frustumOver(box, objectToWorld: objectToWorld),
    level,
  );
}

/// A world ray in the mesh's own space, with how much shorter world lengths are
/// there.
///
/// The direction has to be normalised again after the transform: [MeshPicker]
/// reads a depth as `(point - origin) · direction` and trusts that to be a
/// distance, and under a scaled transform the rotated direction is not a unit
/// vector. The length it had before normalising is exactly the factor between
/// the two spaces, so it is kept rather than recovered from the matrix.
({Ray ray, double shrink}) _intoMesh(Ray world, Matrix4? objectToWorld) {
  if (objectToWorld == null) return (ray: world, shrink: 1.0);
  final inverse = Matrix4.copy(objectToWorld)..invert();
  final local = world.transformInto(inverse, Ray.zero());
  final shrink = local.direction.length;
  return (ray: local.normalizeDirection(), shrink: shrink);
}

/// How far along [ray] the middle of [mesh] is, or null when there is nothing
/// to measure to.
///
/// A pass over every vertex, which is affordable because the only caller that
/// reaches it is about to scan every vertex anyway — and because it is reached
/// only when the ray missed the tree entirely. The middle of the bounding box
/// rather than the average position, so that a mesh with a dense cluster in one
/// corner is still measured to the middle of the shape a person sees.
///
/// Null when the mesh is empty or sits behind the pointer: there is no depth to
/// size a radius at, and inventing one picks something arbitrary.
double? _depthOfCentre(EditMesh mesh, Ray ray) {
  final at = Vector3.zero();
  final low = Vector3.zero();
  final high = Vector3.zero();
  var found = false;
  for (var vertex = 0; vertex < mesh.vertexSlotCount; vertex++) {
    if (!mesh.isVertexAlive(vertex)) continue;
    mesh.positionOf(vertex, at);
    if (!found) {
      low.setFrom(at);
      high.setFrom(at);
      found = true;
      continue;
    }
    Vector3.min(low, at, low);
    Vector3.max(high, at, high);
  }
  if (!found) return null;
  final depth = ((low + high) * 0.5 - ray.origin).dot(ray.direction);
  return depth > 0.0 ? depth : null;
}

/// One element as a selection, with itself as the active one.
Selection _one(ElementLevel level, int id) => id == EditMesh.none
    ? Selection.empty(level)
    : Selection.of(level, <int>[id], active: id);
