/// What an AR runtime understands of the room, as the simulation takes it:
/// planes and scene meshes as external input on the tape, and as colliders.
library;

import 'dart:typed_data';

import 'package:flutter3d_physics/flutter3d_physics.dart'
    show Collider, CollisionBox, CollisionWorld;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        Assimilation,
        AssimilationContext,
        ExternalStateInput,
        PluginFormatException,
        ReadingKind;
import 'package:vector_math/vector_math.dart';

import 'xr_input.dart';

/// Which way a detected plane faces.
///
/// **Open.** ARKit and ARCore classify further (a table, a seat, a
/// ceiling), and OpenXR's scene extensions name their own; a class with
/// constants takes them.
final class XrPlaneOrientation {
  const XrPlaneOrientation._(this.name);

  /// Faces up: a floor, a table top.
  static const XrPlaneOrientation horizontalUp = XrPlaneOrientation._(
    'horizontalUp',
  );

  /// Faces down: a ceiling.
  static const XrPlaneOrientation horizontalDown = XrPlaneOrientation._(
    'horizontalDown',
  );

  /// Upright: a wall, a door.
  static const XrPlaneOrientation vertical = XrPlaneOrientation._('vertical');

  /// None of the three.
  static const XrPlaneOrientation arbitrary = XrPlaneOrientation._('arbitrary');

  /// Every value this version names, in declaration order. A later version
  /// appends; nothing is removed or renamed within a major.
  static const List<XrPlaneOrientation> values = <XrPlaneOrientation>[
    horizontalUp,
    horizontalDown,
    vertical,
    arbitrary,
  ];

  /// The value called [name], or null for a name this version does not
  /// know.
  static XrPlaneOrientation? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// The stable name, and the wire name. Never renamed within a major.
  final String name;

  @override
  String toString() => 'XrPlaneOrientation.$name';
}

/// A flat surface the runtime found: a rectangle of [width] by [depth]
/// meters centered at [pose], lying in the pose's x-z plane with its normal
/// along the pose's +y.
final class XrPlane {
  /// The plane [id], as the runtime keeps it from frame to frame.
  XrPlane({
    required this.id,
    required this.pose,
    required this.width,
    required this.depth,
    this.orientation = XrPlaneOrientation.arbitrary,
  }) {
    if (id.isEmpty) throw ArgumentError.value(id, 'id', 'empty');
    if (!(width >= 0.0) || !(depth >= 0.0)) {
      throw ArgumentError('a plane of ${width}x$depth m has no extent');
    }
  }

  /// The runtime's id, stable for as long as the plane is tracked.
  final String id;

  /// Its center and turn, in the session's space.
  final XrPose pose;

  /// Its extent along the pose's x, in meters.
  final double width;

  /// Its extent along the pose's z, in meters.
  final double depth;

  /// Which way it faces.
  final XrPlaneOrientation orientation;

  /// Where a plane goes on the tape: `xr.plane.<id>`.
  static String sourceOf(String id) => '${XrPoseSources.prefix}plane.$id';

  /// Whether [source] names a plane.
  static bool isPlane(String source) =>
      source.startsWith('${XrPoseSources.prefix}plane.');

  /// The plane as input for the step: the pose's seven numbers and the two
  /// extents, with the orientation as the reading's tag.
  ExternalStateInput toInput({double? displayTime}) => ExternalStateInput(
    source: sourceOf(id),
    value: <double>[...pose.components, width, depth],
    sourceTime: displayTime,
    kind: ReadingKind.measured,
    tag: orientation.name,
  );

  /// Input saying the plane [id] is no longer tracked: no numbers at all.
  static ExternalStateInput lost(String id, {double? displayTime}) =>
      ExternalStateInput(
        source: sourceOf(id),
        value: const <double>[],
        sourceTime: displayTime,
      );

  /// The plane [toInput] wrote. Throws a [PluginFormatException] for input
  /// that is not one.
  factory XrPlane.fromInput(ExternalStateInput input) {
    if (!isPlane(input.source) || input.value.length != 9) {
      throw PluginFormatException(
        'a plane is xr.plane.<id> with nine numbers, not ${input.source} '
        'with ${input.value.length}',
        input.toJson(),
      );
    }
    return XrPlane(
      id: input.source.substring('${XrPoseSources.prefix}plane.'.length),
      pose: XrPose.fromComponents(input.value.sublist(0, 7)),
      width: input.value[7],
      depth: input.value[8],
      orientation:
          XrPlaneOrientation.byName(input.tag ?? '') ??
          XrPlaneOrientation.arbitrary,
    );
  }

  /// A static collider over the plane: the axis-aligned box around it,
  /// [thickness] meters deep below its surface.
  ///
  /// **Exact for a floor or a table, a bound for anything turned.** The
  /// collision world's boxes do not turn, so a wall at an angle collides as
  /// the box around it; the rectangle's own corners are what is bounded.
  Collider toCollider({double thickness = 0.02}) {
    final turn = pose.orientation.asRotationMatrix();
    final center = pose.position;
    final min = Vector3.all(double.infinity);
    final max = Vector3.all(double.negativeInfinity);
    for (final (x, y, z) in <(double, double, double)>[
      for (final sx in const <double>[-0.5, 0.5])
        for (final sz in const <double>[-0.5, 0.5])
          for (final sy in <double>[0.0, -thickness])
            (sx * width, sy, sz * depth),
    ]) {
      final corner = turn.transformed(Vector3(x, y, z))..add(center);
      Vector3.min(min, corner, min);
      Vector3.max(max, corner, max);
    }
    return Collider(
      shape: CollisionBox.size(max - min),
      position: (min + max)..scale(0.5),
      userData: this,
    );
  }
}

/// A mesh the runtime made of the room: [vertices] as x, y, z triples in
/// the space of [pose], and [indices] three to a triangle.
final class XrSceneMesh {
  /// The mesh [id], as the runtime keeps it from frame to frame.
  XrSceneMesh({
    required this.id,
    required this.pose,
    required this.vertices,
    required this.indices,
  }) {
    if (vertices.length % 3 != 0 || indices.length % 3 != 0) {
      throw ArgumentError(
        'a scene mesh is triples: ${vertices.length} coordinates and '
        '${indices.length} indices',
      );
    }
  }

  /// The runtime's id, stable for as long as the mesh is tracked.
  final String id;

  /// Where its vertices' space sits in the session's.
  final XrPose pose;

  /// x, y, z of each vertex, in meters.
  final Float32List vertices;

  /// Three a triangle, into [vertices]' triples.
  final Uint32List indices;

  /// Where a scene mesh goes on the tape: `xr.mesh.<id>`.
  static String sourceOf(String id) => '${XrPoseSources.prefix}mesh.$id';

  /// The mesh as input for the step: the pose's seven numbers, the vertex
  /// count, the coordinates, then the indices.
  ExternalStateInput toInput({double? displayTime}) => ExternalStateInput(
    source: sourceOf(id),
    value: <double>[
      ...pose.components,
      (vertices.length ~/ 3).toDouble(),
      ...vertices,
      for (final index in indices) index.toDouble(),
    ],
    sourceTime: displayTime,
    kind: ReadingKind.measured,
  );

  /// The mesh [toInput] wrote. Throws a [PluginFormatException] for input
  /// that is not one.
  factory XrSceneMesh.fromInput(ExternalStateInput input) {
    final prefix = '${XrPoseSources.prefix}mesh.';
    final value = input.value;
    if (!input.source.startsWith(prefix) || value.length < 8) {
      throw PluginFormatException(
        'a scene mesh is xr.mesh.<id> with a pose and a vertex count',
        input.toJson(),
      );
    }
    final count = value[7].toInt();
    final end = 8 + count * 3;
    if (count < 0 || end > value.length || (value.length - end) % 3 != 0) {
      throw PluginFormatException(
        'the scene mesh ${input.source} says $count vertices and holds '
        '${value.length - 8} numbers after its pose',
        input.toJson(),
      );
    }
    return XrSceneMesh(
      id: input.source.substring(prefix.length),
      pose: XrPose.fromComponents(value.sublist(0, 7)),
      vertices: Float32List.fromList(value.sublist(8, end)),
      indices: Uint32List.fromList(<int>[
        for (final index in value.sublist(end)) index.toInt(),
      ]),
    );
  }

  /// A static collider over the mesh: the axis-aligned box around its
  /// vertices in the session's space.
  ///
  /// **A bound, not the surface.** The collision world has no triangle
  /// shape, so a scene mesh collides as its box: a sofa is a block. A body
  /// that must rest on the mesh's own triangles needs a mesh shape the
  /// world does not have yet.
  Collider toCollider() {
    final turn = pose.orientation.asRotationMatrix();
    final center = pose.position;
    final min = Vector3.all(double.infinity);
    final max = Vector3.all(double.negativeInfinity);
    for (var i = 0; i < vertices.length; i += 3) {
      final at = turn.transformed(
        Vector3(vertices[i], vertices[i + 1], vertices[i + 2]),
      )..add(center);
      Vector3.min(min, at, min);
      Vector3.max(max, at, max);
    }
    if (vertices.isEmpty) {
      min.setFrom(center);
      max.setFrom(center);
    }
    return Collider(
      shape: CollisionBox.size(max - min),
      position: (min + max)..scale(0.5),
      userData: this,
    );
  }
}

/// Keeps [world]'s colliders in step with the planes and scene meshes an
/// AR session feeds, inside the step.
///
/// **From the step's input, so a replay builds the same room.** A plane
/// arrives as input ([XrPlane.toInput]) and becomes a collider; it arrives
/// again moved or grown and its collider is replaced; [XrPlane.lost] takes
/// it away. A scene mesh goes the same way. A recorded AR session played
/// back puts the same colliders in the same steps, so a ball rolled across
/// the real table replays as it rolled.
final class XrSceneColliders extends Assimilation {
  /// Colliders for the room, in [world].
  XrSceneColliders(this.world);

  /// The world the colliders go into.
  final CollisionWorld world;

  final Map<String, Collider> _colliders = <String, Collider>{};

  /// The name it is installed under, with `LoopRegistry.addAssimilation`.
  static const String systemName = 'xr.scene';

  /// The collider standing for the plane or mesh fed under [source], or
  /// null.
  Collider? operator [](String source) => _colliders[source];

  /// How many planes and meshes are in [world] now.
  int get length => _colliders.length;

  @override
  void assimilate(AssimilationContext context) {
    for (final input in context.inputs) {
      final source = input.source;
      final isPlane = XrPlane.isPlane(source);
      if (!isPlane && !source.startsWith('${XrPoseSources.prefix}mesh.')) {
        continue;
      }
      if (_colliders.remove(source) case final old?) world.remove(old);
      if (input.value.isEmpty) continue;
      final collider = isPlane
          ? XrPlane.fromInput(input).toCollider()
          : XrSceneMesh.fromInput(input).toCollider();
      _colliders[source] = world.add(collider);
    }
  }
}
