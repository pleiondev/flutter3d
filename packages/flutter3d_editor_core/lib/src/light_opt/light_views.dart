import 'dart:math' as math;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// Where the light optimizer looks at a level from: the eye, and the point
/// it looks at.
typedef LightView = ({Vector3 from, Vector3 at});

/// How high above the feet a player's eye is, in metres, when a view is
/// taken from where somebody stood.
const double lightViewEyeHeight = 1.6;

/// Views along a path somebody walked: [count] of its poses, evenly spaced
/// in time, each an eye [eyeHeight] above the pose looking the way it faced.
///
/// **Poses rather than the `.f3drun` itself.** A run file is a tape of
/// inputs, and where the player stood is only known by playing that tape
/// through the game's own simulation — which a level editor that knows no
/// genre cannot do. A game that can play its runs hands the poses it passed
/// through (a `Recorder` running during playback writes exactly these), and
/// the optimizer judges the lights from where players actually are.
///
/// Yaw nought looks down -Z and a positive yaw turns anticlockwise seen from
/// above, the way the shooter builds its forward; [around] adds that many
/// more headings per pose, evenly around, for a path whose facing is not
/// worth trusting.
List<LightView> viewsAlong(
  List<Pose> poses, {
  int count = 8,
  int around = 1,
  double eyeHeight = lightViewEyeHeight,
}) {
  if (poses.isEmpty || count <= 0) return const <LightView>[];
  final picked = poses.length <= count
      ? poses
      : <Pose>[
          for (var i = 0; i < count; i++)
            poses[(i * (poses.length - 1) / math.max(count - 1, 1)).round()],
        ];
  final headings = math.max(around, 1);
  return <LightView>[
    for (final pose in picked)
      for (var turn = 0; turn < headings; turn++)
        _looking(
          pose.position + Vector3(0.0, eyeHeight, 0.0),
          pose.yaw + turn * 2.0 * math.pi / headings,
        ),
  ];
}

/// Views for a level nobody has played yet: from every player spawn, four
/// headings a quarter turn apart; with no spawn, from the middle of the
/// level's brushes. Empty for a level with no brushes and no spawn.
List<LightView> defaultLightViews(
  Level level, {
  double eyeHeight = lightViewEyeHeight,
}) {
  final spawns = level.ofType(EntityTypes.playerSpawn).toList();
  final Iterable<({Vector3 at, double yaw})> stands = spawns.isNotEmpty
      ? spawns.map((EntityDef it) => (at: it.position, yaw: it.yaw))
      : level.brushes.isEmpty
      ? const <({Vector3 at, double yaw})>[]
      : <({Vector3 at, double yaw})>[(at: _floorMiddle(level), yaw: 0.0)];
  return <LightView>[
    for (final stand in stands)
      for (var turn = 0; turn < 4; turn++)
        _looking(
          stand.at + Vector3(0.0, eyeHeight, 0.0),
          stand.yaw + turn * math.pi / 2.0,
        ),
  ];
}

LightView _looking(Vector3 eye, double yaw) =>
    (from: eye, at: eye + Vector3(-Portable.sin(yaw), 0.0, -Portable.cos(yaw)));

/// The middle of the level's brushes, at the height of their lowest point:
/// the floor of a room, near enough, for a level with nowhere to start.
Vector3 _floorMiddle(Level level) {
  final box = Aabb3.minMax(
    level.brushes.first.min.clone(),
    level.brushes.first.max.clone(),
  );
  for (final brush in level.brushes) {
    box
      ..hullPoint(brush.min)
      ..hullPoint(brush.max);
  }
  return Vector3(box.center.x, box.min.y, box.center.z);
}
