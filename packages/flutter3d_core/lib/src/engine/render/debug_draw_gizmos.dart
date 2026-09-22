import 'dart:math' as math;

import 'package:flutter3d_core/geometry.dart';
import 'package:vector_math/vector_math.dart';

import '../scene/camera_node.dart';
import '../scene/light_node.dart';
import '../scene/mesh_node.dart';
import '../scene/scene.dart';
import '../scene/scene_node.dart';
import 'debug_draw.dart';

/// The shape-level overlays — boxes, axes, normals, frusta, spheres, light
/// gizmos — and [buildForScene], which assembles them from a [Scene].
///
/// Kept apart from [DebugDraw]'s buffer core in an ordinary file rather than a
/// `part`: every one of these reaches the buffer only through [DebugDraw]'s
/// public `addLine` / `addLineXyz` / `clear`, never through its private
/// fields, so there is nothing here that privacy would have to give up to
/// live in its own library.
extension DebugDrawGizmos on DebugDraw {
  /// The twelve edges of an axis-aligned box.
  void addBox(Aabb3 box, Vector4 color) {
    final min = box.min;
    final max = box.max;
    _addBoxCorners(min.x, min.y, min.z, max.x, max.y, max.z, color);
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
      axis.setValues(
        i == 0 ? size : 0.0,
        i == 1 ? size : 0.0,
        i == 2 ? size : 0.0,
      );
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
    final step = math.max(1, (count / DebugDraw.maxNormalsPerMesh).ceil());

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
        final offset =
            basis.$1 * (math.cos(a) * radius) +
            basis.$2 * (math.sin(a) * radius);
        addLine(origin, tip + offset, DebugColors.light);
      }
    }
  }

  /// A bone: an octahedron stretched from [from] toward [to], the standard
  /// rig-viewport shape — the twelve edges of a real octahedron, one waist
  /// ring a tenth of the way along rather than in the middle, which is what
  /// makes the shape read as *pointing* from a joint toward its child
  /// instead of as a bulge sitting between two unrelated points.
  ///
  /// Draws nothing when [from] and [to] coincide — a zero-length bone has no
  /// direction to build a ring around, and dividing by that length would
  /// produce lines of `NaN`.
  void addBoneOctahedron(
    Vector3 from,
    Vector3 to,
    double width,
    Vector4 color,
  ) {
    final axis = to - from;
    final length = axis.length;
    if (length < 1e-9) return;
    final direction = axis / length;
    final basis = _perpendicularBasis(direction);
    final waist = from + axis * 0.1;
    final ring = <Vector3>[
      waist + basis.$1 * width,
      waist + basis.$2 * width,
      waist - basis.$1 * width,
      waist - basis.$2 * width,
    ];
    for (var i = 0; i < ring.length; i++) {
      addLine(from, ring[i], color);
      addLine(ring[i], ring[(i + 1) % ring.length], color);
      addLine(ring[i], to, color);
    }
  }

  /// A three-line crosshair at [center] — what a joint with no child to
  /// stretch a bone toward ([addBoneOctahedron] needs two ends) is drawn as
  /// instead, the same way a light with no cone still needs a marker.
  void addJointCross(Vector3 center, double size, Vector4 color) {
    addLineXyz(
      center.x - size,
      center.y,
      center.z,
      center.x + size,
      center.y,
      center.z,
      color,
    );
    addLineXyz(
      center.x,
      center.y - size,
      center.z,
      center.x,
      center.y + size,
      center.z,
      color,
    );
    addLineXyz(
      center.x,
      center.y,
      center.z - size,
      center.x,
      center.y,
      center.z + size,
      color,
    );
  }

  /// A skeleton, drawn one [addBoneOctahedron] per parent/child pair and one
  /// [addJointCross] at every joint [parents] gives no child — `anim-08`'s
  /// own row.
  ///
  /// [worldPositions] and [parents] are index-aligned and [parents] holds
  /// each joint's own parent index, or a value outside `0..worldPositions
  /// .length` for a root — the same convention `Pose.parents` already
  /// keeps, so a caller already holding one hands it straight through.
  /// [problem] names indices to draw in [DebugColors.jointProblem] instead
  /// of [color] — built from `anim-13`'s own `rigIssues` by a caller that
  /// has one; empty draws every joint the same colour.
  ///
  /// **What this does not do.** Screen-space picking (`anim-08`'s own "клик
  /// по суставу 7 выбирает 7") and the golden frame `skeleton-overlay` are
  /// both app-layer, and neither is here — this is the drawing this row's
  /// picking half would need a joint to already be visible to hit.
  void addSkeletonOverlay(
    List<Vector3> worldPositions,
    List<int> parents, {
    Vector4? color,
    double boneWidth = 0.02,
    double crossSize = 0.03,
    Set<int> problem = const <int>{},
  }) {
    final normal = color ?? DebugColors.selection;
    final hasChild = List<bool>.filled(worldPositions.length, false);
    for (final parent in parents) {
      if (parent >= 0 && parent < hasChild.length) hasChild[parent] = true;
    }
    for (var joint = 0; joint < worldPositions.length; joint++) {
      final own = problem.contains(joint) ? DebugColors.jointProblem : normal;
      if (hasChild[joint]) {
        for (var child = 0; child < parents.length; child++) {
          if (parents[child] == joint) {
            addBoneOctahedron(
              worldPositions[joint],
              worldPositions[child],
              boneWidth,
              own,
            );
          }
        }
      } else {
        addJointCross(worldPositions[joint], crossSize, own);
      }
    }
  }

  static (Vector3, Vector3) _perpendicularBasis(Vector3 direction) {
    final n = direction.normalized();
    final helper = n.z.abs() < 0.9
        ? Vector3(0.0, 0.0, 1.0)
        : Vector3(1.0, 0.0, 0.0);
    final u = helper.cross(n)..normalize();
    final v = n.cross(u)..normalize();
    return (u, v);
  }

  /// The world bounds of everything drawable at or under [node], or null when
  /// there is nothing drawable there.
  static Aabb3? _boundsOf(SceneNode node) {
    Aabb3? total;
    void visit(SceneNode at) {
      if (at is MeshNode) {
        final bounds = at.worldBounds;
        if (total == null) {
          total = Aabb3.copy(bounds);
        } else {
          total!.hull(bounds);
        }
      }
      for (final child in at.children) {
        visit(child);
      }
    }

    visit(node);
    return total;
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

    if (options.skeletons) {
      final position = Vector3.zero();
      for (final node in scene.meshes) {
        final skeleton = node.skeleton;
        if (skeleton == null || !node.visibleInHierarchy) continue;
        final joints = skeleton.joints;
        final worldPositions = List<Vector3>.generate(joints.length, (i) {
          joints[i].readWorldPosition(position);
          return position.clone();
        });
        final indexOf = <SceneNode, int>{
          for (var i = 0; i < joints.length; i++) joints[i]: i,
        };
        final parents = List<int>.generate(
          joints.length,
          (i) => indexOf[joints[i].parent] ?? -1,
        );
        addSkeletonOverlay(worldPositions, parents);
      }
    }

    for (final node in highlighted) {
      // **A group is outlined by what is under it.** A caller marking a
      // selection does not always hand over a mesh: an editor's marker is a
      // holder with twelve thin bars beneath it, and the first version of this
      // drew axes a tenth of the *scene* long through the middle of the level
      // instead — three enormous lines where a small box was wanted.
      final bounds = _boundsOf(node);
      if (bounds != null) {
        addBox(bounds, DebugColors.selection);
      } else {
        // Nothing drawable under it at all: a light, an empty, a spawn point.
        // Axes are the only thing a transform on its own can be shown as.
        addAxes(node.worldMatrix, size: math.max(sceneSize * 0.1, 0.1));
      }
    }
  }
}
