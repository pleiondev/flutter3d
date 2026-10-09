import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show LinearColor, WorldPosition;
import 'package:vector_math/vector_math.dart';

/// Which debug overlays to build for a frame.
///
/// A value rather than a set of flags on the renderer: the overlays are a
/// property of what the user asked to see, and the renderer should not grow a
/// field per toggle.
final class DebugDrawSettings {
  const DebugDrawSettings({
    this.bounds = false,
    this.normals = false,
    this.lightGizmos = false,
    this.axes = false,
    this.cameraFrustums = false,
    this.skeletons = false,
    this.normalLength = 0.0,
  });

  /// World-space bounding box of every visible [MeshNode].
  final bool bounds;

  /// A short segment along the normal of each vertex.
  final bool normals;

  /// Position and aim of every light in the scene.
  final bool lightGizmos;

  /// The world axes at the origin.
  final bool axes;

  /// The view volume of every camera except the one being rendered — the whole
  /// reason culling is inspectable at all.
  final bool cameraFrustums;

  /// One octahedron per bone and one cross per leaf joint, for every skinned
  /// mesh node in the scene — `anim-08`'s own overlay.
  final bool skeletons;

  /// Length of a normal segment in world units. Zero picks a length from the
  /// scene size, which is the only way one setting suits both a 1-unit cube and
  /// a 200-unit model.
  final double normalLength;

  bool get anyEnabled =>
      bounds || normals || lightGizmos || axes || cameraFrustums || skeletons;

  DebugDrawSettings copyWith({
    bool? bounds,
    bool? normals,
    bool? lightGizmos,
    bool? axes,
    bool? cameraFrustums,
    bool? skeletons,
    double? normalLength,
  }) => DebugDrawSettings(
    bounds: bounds ?? this.bounds,
    normals: normals ?? this.normals,
    lightGizmos: lightGizmos ?? this.lightGizmos,
    axes: axes ?? this.axes,
    cameraFrustums: cameraFrustums ?? this.cameraFrustums,
    skeletons: skeletons ?? this.skeletons,
    normalLength: normalLength ?? this.normalLength,
  );
}

/// Colours used by the built-in overlays, so a screenshot is readable without a
/// legend.
///
/// Linear [LinearColor]s, as every colour in the engine is: they were picked
/// as the display values below, and [DebugDraw] encodes them back to exactly
/// those on the way to the screen. Immutable, so a `static final` is a
/// constant; a `Vector4` here had to be a getter, because a caller scaling
/// one changed it for every overlay in the process.
abstract final class DebugColors {
  static final LinearColor bounds = LinearColor.fromSrgb(0.25, 0.85, 1.0);
  static final LinearColor normal = LinearColor.fromSrgb(1.0, 0.45, 0.15);
  static final LinearColor light = LinearColor.fromSrgb(1.0, 0.92, 0.35);
  static final LinearColor frustum = LinearColor.fromSrgb(0.65, 0.45, 1.0);
  static final LinearColor selection = LinearColor.fromSrgb(0.35, 1.0, 0.45);
  static final LinearColor axisX = LinearColor.fromSrgb(1.0, 0.25, 0.25);
  static final LinearColor axisY = LinearColor.fromSrgb(0.25, 1.0, 0.35);
  static final LinearColor axisZ = LinearColor.fromSrgb(0.3, 0.5, 1.0);

  /// `#FF458E` — a joint the skeleton overlay draws to say something is
  /// wrong with it (`anim-13`'s own `rigIssues`, once a caller has one).
  static final LinearColor jointProblem = LinearColor.fromSrgb(
    1.0,
    0x45 / 255.0,
    0x8E / 255.0,
  );
}

/// Accumulates debug line segments into one reusable interleaved buffer.
///
/// Everything the engine wants to visualise — bounds, normals, gizmos, frusta —
/// is line segments, so all of it goes into a single buffer drawn with one
/// `PrimitiveType.line` call. That keeps the debug overlay off the frame's
/// critical path: one draw and one buffer upload regardless of how much is
/// shown.
///
/// The buffer is grown by doubling and never released, so a steady overlay
/// allocates nothing after the first few frames. This class knows nothing about
/// the graphics backend, which keeps it testable without a device.
///
/// ## Where a line is
///
/// **In scene space**: float32 offsets from the drawn scene's [origin]
/// (`Scene.origin`), the space every node's transform is in and the GPU
/// draws in — see "Space" in `docs/CONTRACTS.md`. A point read off a node
/// (`worldMatrix`, `localBounds` through it) is already there. A place in the
/// world, a `WorldPosition` in doubles, goes in through [addWorldLine], which
/// subtracts [origin] in doubles first, as `Scene.toScene` does.
///
/// ## Its colour
///
/// A [LinearColor], linear as every colour in the engine is. The overlay is
/// drawn after the frame is encoded for the display, so each line's colour
/// is encoded here, once, and reaches the screen as the sRGB value it names.
final class DebugDraw {
  DebugDraw({int reserveLines = 256})
    : _data = Float32List(math.max(1, reserveLines) * floatsPerLine);

  /// position.xyz + colour.rgba, matching [VertexLayout.positionColor].
  static const int floatsPerVertex = 7;
  static const int floatsPerLine = floatsPerVertex * 2;

  /// Upper bound on the normals drawn for one mesh.
  ///
  /// A 100k-vertex mesh would otherwise turn the overlay into the most expensive
  /// thing in the frame; sampling every n-th vertex still shows a flipped normal
  /// or a broken smoothing group.
  static const int maxNormalsPerMesh = 4096;

  Float32List _data;
  int _floats = 0;

  /// Where scene space starts in the world: the drawn scene's `Scene.origin`,
  /// which [buildForScene](DebugDrawGizmos.buildForScene) sets each frame
  /// before a game's own lines are added. [addWorldLine] measures from it.
  WorldPosition origin = WorldPosition.origin;

  /// The last colour encoded, and its display values, so a run of lines in
  /// one colour (a box, a sphere, every normal of a mesh) encodes it once.
  LinearColor? _encodedFrom;
  double _er = 0, _eg = 0, _eb = 0, _ea = 1;

  int get vertexCount => _floats ~/ floatsPerVertex;

  int get lineCount => _floats ~/ floatsPerLine;

  bool get isEmpty => _floats == 0;

  /// The used portion of the buffer, ready to upload.
  ByteData get vertexBytes =>
      _data.buffer.asByteData(_data.offsetInBytes, _floats * 4);

  void clear() => _floats = 0;

  /// Trims every line to the part of it the camera can actually see.
  ///
  /// **A line with an end behind the eye is a line drawn somewhere else.** The
  /// vertex shader multiplies a world position by the view projection and
  /// divides by w; behind the camera w is negative, and the division puts that
  /// end at a mirrored, meaningless place on screen. The line still draws —
  /// wildly wrong, and confidently. It was reported as "the frame is offset
  /// from the object", by the first person to select a wall six metres wide and
  /// stand next to it.
  ///
  /// Nothing else in the frame has this problem, because everything else is
  /// made of triangles and the rasteriser clips those. A line list is handed
  /// straight to the hardware, and the near plane is ours to respect.
  ///
  /// The intersection is found in clip space and applied to the *world*
  /// endpoints, because world positions are what this buffer holds. A segment
  /// with both ends behind the eye is collapsed to a point, which draws
  /// nothing.
  void clipToNearPlane(Matrix4 viewProjection, {double epsilon = 1e-4}) {
    final m = viewProjection.storage;
    double wOf(double x, double y, double z) =>
        m[3] * x + m[7] * y + m[11] * z + m[15];

    for (var line = 0; line + floatsPerLine <= _floats; line += floatsPerLine) {
      final b = line + floatsPerVertex;
      final ax = _data[line], ay = _data[line + 1], az = _data[line + 2];
      final bx = _data[b], by = _data[b + 1], bz = _data[b + 2];
      final wa = wOf(ax, ay, az);
      final wb = wOf(bx, by, bz);

      if (wa >= epsilon && wb >= epsilon) continue;

      if (wa < epsilon && wb < epsilon) {
        // Both behind: leave a degenerate line where the first end was, which
        // rasterises to nothing.
        _data[b] = ax;
        _data[b + 1] = ay;
        _data[b + 2] = az;
        continue;
      }

      // One of them crosses. `w` is linear along the segment, so the crossing
      // is where it reaches epsilon.
      final t = (epsilon - wa) / (wb - wa);
      final x = ax + (bx - ax) * t;
      final y = ay + (by - ay) * t;
      final z = az + (bz - az) * t;
      if (wa < epsilon) {
        _data[line] = x;
        _data[line + 1] = y;
        _data[line + 2] = z;
      } else {
        _data[b] = x;
        _data[b + 1] = y;
        _data[b + 2] = z;
      }
    }
  }

  /// A line from [a] to [b], both in scene space, in [color].
  void addLine(Vector3 a, Vector3 b, LinearColor color) =>
      addLineXyz(a.x, a.y, a.z, b.x, b.y, b.z, color);

  /// A line between two places in the world, in [color]: each is taken
  /// relative to [origin] in doubles and only then narrowed to scene space,
  /// so a line ten kilometres out is drawn where it is. For a game drawing
  /// what it holds as `WorldPosition`s — a route its AI planned, a ray a gun
  /// cast — from `Renderer.debugLines`.
  void addWorldLine(WorldPosition a, WorldPosition b, LinearColor color) {
    final from = a.relativeTo(origin);
    final to = b.relativeTo(origin);
    addLineXyz(from.x, from.y, from.z, to.x, to.y, to.z, color);
  }

  /// [addLine] from six scene-space coordinates, for a caller that has no
  /// `Vector3` to hand.

  void addLineXyz(
    double ax,
    double ay,
    double az,
    double bx,
    double by,
    double bz,
    LinearColor color,
  ) {
    if (_floats + floatsPerLine > _data.length) _grow();
    if (!identical(color, _encodedFrom) && color != _encodedFrom) {
      final (:r, :g, :b, :a) = color.toSrgb();
      _er = r;
      _eg = g;
      _eb = b;
      _ea = a;
      _encodedFrom = color;
    }
    final d = _data;
    var o = _floats;
    d[o++] = ax;
    d[o++] = ay;
    d[o++] = az;
    d[o++] = _er;
    d[o++] = _eg;
    d[o++] = _eb;
    d[o++] = _ea;
    d[o++] = bx;
    d[o++] = by;
    d[o++] = bz;
    d[o++] = _er;
    d[o++] = _eg;
    d[o++] = _eb;
    d[o++] = _ea;
    _floats = o;
  }

  void _grow() {
    final grown = Float32List(math.max(_data.length * 2, floatsPerLine * 16));
    grown.setRange(0, _floats, _data);
    _data = grown;
  }
}
