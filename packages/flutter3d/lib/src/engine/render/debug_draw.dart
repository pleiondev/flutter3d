import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../geometry/mesh_data.dart';
import '../scene/camera_node.dart';
import '../scene/light_node.dart';
import '../scene/mesh_node.dart';
import '../scene/scene.dart';
import '../scene/scene_node.dart';

/// Which debug overlays to build for a frame.
///
/// A value rather than a set of flags on the renderer: the overlays are a
/// property of what the user asked to see, and the renderer should not grow a
/// field per toggle.
final class DebugDrawOptions {
  const DebugDrawOptions({
    this.bounds = false,
    this.normals = false,
    this.lightGizmos = false,
    this.axes = false,
    this.cameraFrustums = false,
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

  /// Length of a normal segment in world units. Zero picks a length from the
  /// scene size, which is the only way one setting suits both a 1-unit cube and
  /// a 200-unit model.
  final double normalLength;

  bool get anyEnabled =>
      bounds || normals || lightGizmos || axes || cameraFrustums;

  DebugDrawOptions copyWith({
    bool? bounds,
    bool? normals,
    bool? lightGizmos,
    bool? axes,
    bool? cameraFrustums,
    double? normalLength,
  }) =>
      DebugDrawOptions(
        bounds: bounds ?? this.bounds,
        normals: normals ?? this.normals,
        lightGizmos: lightGizmos ?? this.lightGizmos,
        axes: axes ?? this.axes,
        cameraFrustums: cameraFrustums ?? this.cameraFrustums,
        normalLength: normalLength ?? this.normalLength,
      );
}

/// Colours used by the built-in overlays, so a screenshot is readable without a
/// legend.
///
/// **Getters, not `static final`, and this is a rule rather than a style.** A
/// `Vector4` is mutable, so a `static final` one is a global variable wearing a
/// constant's clothes: the first caller to write `DebugColors.bounds.scale(2)`
/// changes the colour for every overlay in the process, for the rest of its
/// life, in a field nothing declares as changeable. None of them is mutated
/// today, which is exactly why today is the cheap day to make it impossible.
abstract final class DebugColors {
  static Vector4 get bounds => Vector4(0.25, 0.85, 1.0, 1.0);
  static Vector4 get normal => Vector4(1.0, 0.45, 0.15, 1.0);
  static Vector4 get light => Vector4(1.0, 0.92, 0.35, 1.0);
  static Vector4 get frustum => Vector4(0.65, 0.45, 1.0, 1.0);
  static Vector4 get selection => Vector4(0.35, 1.0, 0.45, 1.0);
  static Vector4 get axisX => Vector4(1.0, 0.25, 0.25, 1.0);
  static Vector4 get axisY => Vector4(0.25, 1.0, 0.35, 1.0);
  static Vector4 get axisZ => Vector4(0.3, 0.5, 1.0, 1.0);
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

  int get vertexCount => _floats ~/ floatsPerVertex;

  int get lineCount => _floats ~/ floatsPerLine;

  bool get isEmpty => _floats == 0;

  /// The used portion of the buffer, ready to upload.
  ByteData get vertexBytes =>
      _data.buffer.asByteData(_data.offsetInBytes, _floats * 4);

  void clear() => _floats = 0;

  void addLine(Vector3 a, Vector3 b, Vector4 color) =>
      addLineXyz(a.x, a.y, a.z, b.x, b.y, b.z, color);

  void addLineXyz(
    double ax,
    double ay,
    double az,
    double bx,
    double by,
    double bz,
    Vector4 color,
  ) {
    if (_floats + floatsPerLine > _data.length) _grow();
    final d = _data;
    var o = _floats;
    d[o++] = ax;
    d[o++] = ay;
    d[o++] = az;
    d[o++] = color.x;
    d[o++] = color.y;
    d[o++] = color.z;
    d[o++] = color.w;
    d[o++] = bx;
    d[o++] = by;
    d[o++] = bz;
    d[o++] = color.x;
    d[o++] = color.y;
    d[o++] = color.z;
    d[o++] = color.w;
    _floats = o;
  }

  /// The twelve edges of an axis-aligned box.
  void addBox(Aabb3 box, Vector4 color) {
    final min = box.min;
    final max = box.max;
    _addBoxCorners(
      min.x,
      min.y,
      min.z,
      max.x,
      max.y,
      max.z,
      color,
    );
  }

  void _addBoxCorners(
    double x0,
    double y0,
    double z0,
    double x1,
    double y1,
    double z1,
    Vector4 color,
  ) {
    // Bottom face.
    addLineXyz(x0, y0, z0, x1, y0, z0, color);
    addLineXyz(x1, y0, z0, x1, y0, z1, color);
    addLineXyz(x1, y0, z1, x0, y0, z1, color);
    addLineXyz(x0, y0, z1, x0, y0, z0, color);
    // Top face.
    addLineXyz(x0, y1, z0, x1, y1, z0, color);
    addLineXyz(x1, y1, z0, x1, y1, z1, color);
    addLineXyz(x1, y1, z1, x0, y1, z1, color);
    addLineXyz(x0, y1, z1, x0, y1, z0, color);
    // Uprights.
    addLineXyz(x0, y0, z0, x0, y1, z0, color);
    addLineXyz(x1, y0, z0, x1, y1, z0, color);
    addLineXyz(x1, y0, z1, x1, y1, z1, color);
    addLineXyz(x0, y0, z1, x0, y1, z1, color);
  }

  /// A box in local space, drawn as the transformed parallelepiped.
  ///
  /// Unlike [addBox] on world bounds, this shows the object's actual orientation:
  /// a rotated cube reads as a rotated cube rather than as the larger axis-aligned
  /// box that encloses it.
  void addTransformedBox(Aabb3 local, Matrix4 transform, Vector4 color) {
    final corners = List<Vector3>.generate(8, (i) {
      final v = Vector3(
        (i & 1) == 0 ? local.min.x : local.max.x,
        (i & 2) == 0 ? local.min.y : local.max.y,
        (i & 4) == 0 ? local.min.z : local.max.z,
      );
      transform.transform3(v);
      return v;
    });
    _addBoxEdgesFromCorners(corners, color);
  }

  /// Corner order is the bit pattern `zyx`, as produced above and by
  /// [addFrustum].
  void _addBoxEdgesFromCorners(List<Vector3> c, Vector4 color) {
    const edges = <int>[
      0, 1, 1, 3, 3, 2, 2, 0, // z = min
      4, 5, 5, 7, 7, 6, 6, 4, // z = max
      0, 4, 1, 5, 2, 6, 3, 7, // connecting
    ];
    for (var i = 0; i < edges.length; i += 2) {
      addLine(c[edges[i]], c[edges[i + 1]], color);
    }
  }

  /// A right-handed axis tripod at the transform's origin: X red, Y green, Z blue.
  void addAxes(Matrix4 transform, {double size = 1.0}) {
    final origin = Vector3.zero();
    transform.transform3(origin);
    final axis = Vector3.zero();

    for (var i = 0; i < 3; i++) {
      axis.setValues(i == 0 ? size : 0.0, i == 1 ? size : 0.0,
          i == 2 ? size : 0.0);
      transform.transform3(axis);
      addLine(
        origin,
        axis,
        i == 0
            ? DebugColors.axisX
            : i == 1
                ? DebugColors.axisY
                : DebugColors.axisZ,
      );
    }
  }

  /// One segment per vertex, from the vertex along its normal.
  ///
  /// Normals are transformed by [normalMatrix] rather than by [worldMatrix]:
  /// under non-uniform scale the two differ, and using the world matrix tilts
  /// every segment, which looks exactly like a broken mesh.
  void addNormals(
    MeshData mesh,
    Matrix4 worldMatrix,
    Matrix4 normalMatrix, {
    required double length,
    Vector4? color,
  }) {
    final normalOffset = mesh.layout.floatOffsetOf('normal');
    if (normalOffset < 0) return;

    final tint = color ?? DebugColors.normal;
    final stride = mesh.layout.floatsPerVertex;
    final count = mesh.vertexCount;
    if (count == 0) return;

    // Sampling rather than truncating: showing the first 4096 vertices of a
    // dense mesh would cover one corner of it and leave the rest unchecked.
    final step = math.max(1, (count / maxNormalsPerMesh).ceil());

    final position = Vector3.zero();
    final normal = Vector3.zero();

    for (var v = 0; v < count; v += step) {
      final o = v * stride;
      position.setValues(
        mesh.vertices[o],
        mesh.vertices[o + 1],
        mesh.vertices[o + 2],
      );
      normal.setValues(
        mesh.vertices[o + normalOffset],
        mesh.vertices[o + normalOffset + 1],
        mesh.vertices[o + normalOffset + 2],
      );

      worldMatrix.transform3(position);
      normalMatrix.rotate3(normal);
      if (normal.length2 < 1e-20) continue;
      normal.normalize();
      normal.scale(length);

      addLineXyz(
        position.x,
        position.y,
        position.z,
        position.x + normal.x,
        position.y + normal.y,
        position.z + normal.z,
        tint,
      );
    }
  }

  /// The view volume of the camera that produced [viewProjection].
  ///
  /// The corners are the NDC cube pushed back through the inverse matrix. The
  /// near plane is at z = 0, not z = -1: every projection in this engine targets
  /// the Metal/Vulkan `[0, 1]` depth range, and using the OpenGL convention here
  /// would draw a frustum that reaches half as far as the real one.
  void addFrustum(Matrix4 viewProjection, Vector4 color) {
    final inverse = Matrix4.copy(viewProjection);
    if (inverse.invert() == 0.0) return; // singular, nothing to draw

    final corners = List<Vector3>.generate(8, (i) {
      final v = Vector3(
        (i & 1) == 0 ? -1.0 : 1.0,
        (i & 2) == 0 ? -1.0 : 1.0,
        (i & 4) == 0 ? 0.0 : 1.0,
      );
      return inverse.perspectiveTransform(v);
    });
    _addBoxEdgesFromCorners(corners, color);
  }

  /// A wire sphere as three orthogonal rings.
  void addSphere(
    Vector3 centre,
    double radius,
    Vector4 color, {
    int segments = 24,
  }) {
    if (radius <= 0.0 || segments < 3) return;
    final step = (2 * math.pi) / segments;

    // One ring per coordinate plane: XY, XZ, YZ.
    for (var plane = 0; plane < 3; plane++) {
      var px = 0.0, py = 0.0, pz = 0.0;
      for (var i = 0; i <= segments; i++) {
        final a = i * step;
        final c = math.cos(a) * radius;
        final s = math.sin(a) * radius;
        final x = plane == 2 ? 0.0 : c;
        final y = plane == 0 ? s : (plane == 1 ? 0.0 : c);
        final z = plane == 0 ? 0.0 : s;
        if (i > 0) {
          addLineXyz(
            centre.x + px,
            centre.y + py,
            centre.z + pz,
            centre.x + x,
            centre.y + y,
            centre.z + z,
            color,
          );
        }
        px = x;
        py = y;
        pz = z;
      }
    }
  }

  /// A gizmo showing where a light is and where it aims.
  ///
  /// Directional lights have no position that matters, so the arrow is drawn at
  /// the node anyway — it is the direction that is being checked, and a light
  /// parented to the camera is precisely the case where the direction is hard to
  /// reason about.
  void addLightGizmo(LightNode light, {double size = 0.25}) {
    final origin = light.readWorldPosition();
    final direction = light.readDirection()..scale(size * 4.0);

    addSphere(origin, size * 0.5, DebugColors.light, segments: 12);
    addLineXyz(
      origin.x,
      origin.y,
      origin.z,
      origin.x + direction.x,
      origin.y + direction.y,
      origin.z + direction.z,
      DebugColors.light,
    );

    if (light.type == LightType.spot) {
      // The outer cone, sketched with four ribs: enough to see the angle without
      // turning the gizmo into geometry of its own.
      final length = direction.length;
      final radius = length * math.tan(light.outerConeAngle);
      final tip = origin + direction;
      final basis = _perpendicularBasis(direction);
      for (var i = 0; i < 4; i++) {
        final a = i * math.pi / 2.0;
        final offset = basis.$1 * (math.cos(a) * radius) +
            basis.$2 * (math.sin(a) * radius);
        addLine(origin, tip + offset, DebugColors.light);
      }
    }
  }

  static (Vector3, Vector3) _perpendicularBasis(Vector3 direction) {
    final n = direction.normalized();
    final helper =
        n.z.abs() < 0.9 ? Vector3(0.0, 0.0, 1.0) : Vector3(1.0, 0.0, 0.0);
    final u = helper.cross(n)..normalize();
    final v = n.cross(u)..normalize();
    return (u, v);
  }

  /// Fills the buffer with the overlays [options] asks for.
  ///
  /// [activeCamera] is excluded from the frustum overlay: drawing the frustum of
  /// the camera you are looking through would just outline the screen.
  void buildForScene(
    Scene scene,
    DebugDrawOptions options, {
    CameraNode? activeCamera,
    double aspect = 1.0,
    Iterable<SceneNode> highlighted = const <SceneNode>[],
  }) {
    clear();
    if (!options.anyEnabled && highlighted.isEmpty) return;

    final sceneBounds = scene.computeBounds();
    final sceneSize = sceneBounds.min.x.isFinite
        ? (sceneBounds.max - sceneBounds.min).length
        : 1.0;
    final normalLength = options.normalLength > 0.0
        ? options.normalLength
        : math.max(sceneSize * 0.02, 1e-4);

    if (options.axes) {
      addAxes(Matrix4.identity(), size: math.max(sceneSize * 0.5, 0.5));
    }

    if (options.bounds || options.normals) {
      for (final node in scene.meshes) {
        if (!node.visibleInHierarchy) continue;
        if (options.bounds) addBox(node.worldBounds, DebugColors.bounds);
        if (options.normals) {
          final source = node.mesh.source;
          if (source != null) {
            addNormals(
              source,
              node.worldMatrix,
              node.worldNormalMatrix,
              length: normalLength,
            );
          }
        }
      }
    }

    if (options.lightGizmos) {
      final gizmoSize = math.max(sceneSize * 0.05, 0.05);
      for (final light in scene.lights) {
        addLightGizmo(light, size: gizmoSize);
      }
    }

    if (options.cameraFrustums) {
      for (final camera in scene.cameras) {
        if (identical(camera, activeCamera)) continue;
        addFrustum(camera.viewProjection(aspect), DebugColors.frustum);
      }
    }

    for (final node in highlighted) {
      if (node is MeshNode) {
        addBox(node.worldBounds, DebugColors.selection);
      } else {
        addAxes(node.worldMatrix, size: math.max(sceneSize * 0.1, 0.1));
      }
    }
  }

  void _grow() {
    final grown = Float32List(math.max(_data.length * 2, floatsPerLine * 16));
    grown.setRange(0, _floats, _data);
    _data = grown;
  }
}
