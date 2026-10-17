/// Points fixed to the real world, kept by the runtime and in a level.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show RigidPose, WorldPosition;
import 'package:flutter3d_matter/flutter3d_matter.dart'
    show GeoOrigin, WorldProperties;
import 'package:flutter3d_sim/flutter3d_sim.dart' show EntityDef;
import 'package:vector_math/vector_math.dart' show Quaternion, Vector3;

import 'xr_session.dart';

/// What an anchor is asked to be fixed at.
final class XrAnchorRequest {
  /// An anchor at [pose] in [space], at [geo] on the Earth when the
  /// application knows it (outdoor AR).
  const XrAnchorRequest({
    required this.pose,
    this.space = XrSpace.localFloor,
    this.geo,
  });

  /// Where it goes.
  final RigidPose pose;

  /// The space [pose] is in.
  final XrSpace space;

  /// Where it is on the Earth, for an anchor a runtime places by latitude
  /// and longitude (ARCore's geospatial anchors).
  final GeoOrigin? geo;
}

/// A point fixed to the real world, which the runtime keeps where it is as
/// it learns the room.
///
/// **Its [id] outlives the session.** A runtime that persists anchors gives
/// back the same one under the same id next time
/// (`XrSession.restoreAnchor`), and a level keeps it as an entity of type
/// [entityType] ([toEntity], [XrAnchor.fromEntity]), so a lab bench placed
/// on a real table is on that table when the level is opened again. An
/// outdoor anchor carries [geo], the level's `GeoOrigin` ties the two, and
/// the anchor's pose is the world position that place has in the level.
final class XrAnchor {
  /// The anchor [id], at [pose] in [space].
  XrAnchor({
    required this.id,
    required this.pose,
    this.space = XrSpace.localFloor,
    this.geo,
  }) {
    if (id.isEmpty) throw ArgumentError.value(id, 'id', 'empty');
  }

  /// The anchor a level kept as [entity]. Throws an [ArgumentError] for an
  /// entity of another type or without an orientation of four numbers.
  factory XrAnchor.fromEntity(EntityDef entity) {
    if (entity.type != entityType) {
      throw ArgumentError.value(entity.type, 'entity', 'is not an $entityType');
    }
    final turn = switch (entity.properties['orientation']) {
      final List<Object?> q when q.length == 4 && q.every((v) => v is num) =>
        Quaternion(
          (q[0]! as num).toDouble(),
          (q[1]! as num).toDouble(),
          (q[2]! as num).toDouble(),
          (q[3]! as num).toDouble(),
        ),
      final other => throw ArgumentError.value(
        other,
        'entity',
        'anchor ${entity.id} has no orientation of four numbers',
      ),
    };
    return XrAnchor(
      id: entity.id,
      pose: RigidPose(
        position: Vector3.copy(entity.position),
        orientation: turn,
      ),
      space: switch (entity.properties['space']) {
        final String name => XrSpace.byName(name) ?? XrSpace.localFloor,
        _ => XrSpace.localFloor,
      },
      geo: switch (entity.properties['geo']) {
        null => null,
        final Object geo => GeoOrigin.fromJson(geo),
      },
    );
  }

  /// The runtime's id for it, stable across sessions where the runtime
  /// keeps anchors (a UUID on every runtime that has them).
  final String id;

  /// Where it is now, in [space].
  final RigidPose pose;

  /// The space [pose] is in.
  final XrSpace space;

  /// Where it is on the Earth, when it was placed there.
  final GeoOrigin? geo;

  /// The entity type an anchor is kept under in a level.
  static const String entityType = 'xr.anchor';

  /// Where [geo] is in [world]: the place seen from the world's own origin
  /// (`WorldProperties.geoOrigin`, a level's site), in metres east, up and
  /// north (−z) of it — where an outdoor anchor stands in the level. Null
  /// for an anchor placed by no place on the Earth, or in a world that is
  /// nowhere in particular.
  WorldPosition? placeIn(WorldProperties world) =>
      switch ((world.geoOrigin, geo)) {
        (final GeoOrigin origin?, final GeoOrigin place?) => origin.positionOf(
          place,
        ),
        _ => null,
      };

  /// The anchor as an entity of a level: [entityType], with the anchor's
  /// id as the entity's, its position, and the orientation, the space and
  /// the place on the Earth as properties.
  EntityDef toEntity() {
    final turn = pose.orientation;
    return EntityDef(
      type: entityType,
      id: id,
      position: pose.position,
      properties: <String, Object?>{
        'orientation': <double>[turn.x, turn.y, turn.z, turn.w],
        'space': space.name,
        if (geo case final geo?) 'geo': geo.toJson(),
      },
    );
  }

  @override
  String toString() => 'XrAnchor($id at $pose)';
}
