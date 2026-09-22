/// `ShapeDriver`: a shape key driven by a joint's own rotation — `anim-20`'s
/// own row.
///
/// **What this covers, and what it does not.** The row's own "оценка из
/// `Pose`, аддитивно через `MorphSink`" names two engine-side runtime types
/// (`packages/flutter3d/lib/src/engine/animation/pose.dart` and
/// `morph_sink.dart`) that this package cannot reach — `flutter3d_model_core`
/// is a plain Dart package and does not depend on the windowed engine above
/// it, the same boundary every other file here keeps. What a project-level
/// driver can do, and what is built here, is the document-side half: a
/// [ShapeDriver] descriptor, evaluated straight off the same rotation data a
/// [ProjectClip] already carries (`ProjectTrack.track.sample`, the exact
/// arithmetic `Pose.sampleClip` itself calls), and [bakeShapeDrivers], which
/// freezes that evaluation into an ordinary weights track. Wiring a live
/// driver onto a running `Pose`/`MorphSink` pair is an app- or engine-layer
/// row's own work, not this one's; see `HANDOFF.md` for why this stays the
/// scope.
///
/// **The angle a driver reads is a twist, not a swing.** A joint's rotation
/// is one quaternion, and a driver only cares how far it has turned about
/// one axis — the elbow's own bend axis, say. For a quaternion built as a
/// pure rotation of angle θ about a unit axis `a`, the vector part is
/// `a * sin(θ/2)` and the scalar part is `cos(θ/2)`; projecting the vector
/// part onto `a` and reading `2 * atan2(projection, w)` recovers θ exactly,
/// and recovers the twist component even when the true rotation swings a
/// little off that axis too — the standard swing-twist decomposition, here
/// taken only as far as the twist half because that is the only half a
/// single-axis driver ever asked for.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:vector_math/vector_math.dart';

import 'key_table.dart';
import 'project_animation.dart';

/// Which local axis of a joint's rotation a [ShapeDriver] reads.
///
/// A `final class` with `static const` instances rather than an `enum` —
/// the same choice `BlendMode` beside `PaintLayer` makes and for the same
/// reason: this is a published package, and an `enum` there is a promise
/// nobody adds a fourth axis later. Its own [vector] is computed from three
/// `const`-compatible doubles rather than stored as a `Vector3` field,
/// because `Vector3`'s own constructor is not `const`.
final class DriverAxis {
  const DriverAxis._(this.name, this._x, this._y, this._z);

  /// Shown in a status line or a test failure; not read by anything that
  /// changes behavior on it.
  final String name;

  final double _x, _y, _z;

  /// The unit axis this instance names.
  Vector3 get vector => Vector3(_x, _y, _z);

  static const DriverAxis x = DriverAxis._('x', 1, 0, 0);
  static const DriverAxis y = DriverAxis._('y', 0, 1, 0);
  static const DriverAxis z = DriverAxis._('z', 0, 0, 1);

  @override
  String toString() => 'DriverAxis.$name';
}

/// How a [ShapeDriver] remaps the [0, 1] it gets from clamping an angle into
/// its `from`–`to` span before handing the result on.
///
/// A `final class` with `static const` instances for the same reason
/// [DriverAxis] is one. **One instance today, on purpose.** The row's own
/// worked example — 90° reads as 1.0, 45° as 0.5 — is exactly what [linear]
/// gives and asks for nothing else; a second, eased instance is a real
/// future need this leaves room to add, not a gap in this one.
final class ShapeDriverCurve {
  const ShapeDriverCurve._(this.name, this._apply);

  final String name;
  final double Function(double t) _apply;

  double apply(double t) => _apply(t);

  static double _linear(double t) => t;

  static const ShapeDriverCurve linear = ShapeDriverCurve._('linear', _linear);

  @override
  String toString() => 'ShapeDriverCurve.$name';
}

/// A shape key driven by how far one joint has turned, rather than by a
/// person's own slider — the project-side half of a face that flinches when
/// an elbow locks, without anyone keying the flinch by hand.
final class ShapeDriver {
  const ShapeDriver({
    required this.shapeIndex,
    required this.jointId,
    required this.axis,
    required this.from,
    required this.to,
    this.curve = ShapeDriverCurve.linear,
  });

  /// Index into the driven object's own `ShapeSet.keys`/`weights`.
  final int shapeIndex;

  /// [ModelObject.id] of the joint this reads — the same by-id addressing
  /// [ProjectSkeleton.joints] and [ProjectTrack.objectId] already use.
  final int jointId;

  final DriverAxis axis;

  /// The [axis] angle, in radians, that maps to an output of 0.
  final double from;

  /// The [axis] angle, in radians, that maps to an output of 1.
  final double to;

  final ShapeDriverCurve curve;

  /// A copy with some fields replaced — the same shape [ShapeSet.copyWith]
  /// gives its own value type, for the same reason: `SetShapeDriverField`
  /// changes one field of a driver already on [ModelObject.shapeDrivers]
  /// without spelling the constructor out fresh at every one of its
  /// branches.
  ShapeDriver copyWith({
    int? shapeIndex,
    int? jointId,
    DriverAxis? axis,
    double? from,
    double? to,
    ShapeDriverCurve? curve,
  }) => ShapeDriver(
    shapeIndex: shapeIndex ?? this.shapeIndex,
    jointId: jointId ?? this.jointId,
    axis: axis ?? this.axis,
    from: from ?? this.from,
    to: to ?? this.to,
    curve: curve ?? this.curve,
  );

  /// This driver, as the journal and `AddShapeDriver`'s own arguments write
  /// it — [from]/[to] straight through in radians, the same "the number is
  /// what the maths uses" rule `RotateBy`'s own `radians` argument already
  /// keeps; a UI showing degrees converts at its own edge, the way
  /// `transform_fields.dart`'s own doc comment converts a turn for its
  /// panel without the document ever holding anything but radians.
  Map<String, Object?> toJson() => <String, Object?>{
    'shapeIndex': shapeIndex,
    'jointId': jointId,
    'axis': axis.name,
    'from': from,
    'to': to,
    'curve': curve.name,
  };

  /// A [ShapeDriver] from its own [toJson], or null when [json] is missing a
  /// field or has one of the wrong type — the same "null and not an
  /// exception" rule `modelCommandFromJson` itself keeps, since this feeds
  /// straight into one of its own readers. [curve] always reads back as
  /// [ShapeDriverCurve.linear] — the only kind that exists yet, so there is
  /// nothing else a name in the file could mean, the same reasoning
  /// [DriverAxis]'s own `x` fallback gives for a name this build does not
  /// know.
  static ShapeDriver? fromJson(Object? json) {
    if (json case {
      'shapeIndex': final int shapeIndex,
      'jointId': final int jointId,
      'from': final num from,
      'to': final num to,
    }) {
      final axis = switch (json['axis']) {
        'y' => DriverAxis.y,
        'z' => DriverAxis.z,
        _ => DriverAxis.x,
      };
      return ShapeDriver(
        shapeIndex: shapeIndex,
        jointId: jointId,
        axis: axis,
        from: from.toDouble(),
        to: to.toDouble(),
      );
    }
    return null;
  }

  /// The twist [rotation] carries about [axis], in radians — see this
  /// library's own doc comment for the formula.
  double angleOf(Quaternion rotation) {
    final projection =
        rotation.x * axis.vector.x +
        rotation.y * axis.vector.y +
        rotation.z * axis.vector.z;
    return 2.0 * math.atan2(projection, rotation.w);
  }

  /// This driver's weight for [rotation]: the angle about [axis], mapped
  /// from [from]–[to] onto [0, 1] and clamped before [curve] sees it, so a
  /// joint bent past `to` holds the shape fully open rather than driving it
  /// past 1 or back down the far side of the curve.
  double evaluate(Quaternion rotation) {
    final span = to - from;
    final t = span == 0.0
        ? 0.0
        : ((angleOf(rotation) - from) / span).clamp(0.0, 1.0);
    return curve.apply(t);
  }

  @override
  String toString() =>
      'ShapeDriver(shape $shapeIndex from joint $jointId, ${axis.name})';
}

/// The rotation [clip] gives joint [jointId] at [time], or `null` when no
/// track in [clip] names that joint's rotation — the rest pose, as far as
/// this project-level view can tell, since a [ProjectClip] carries no rest
/// data of its own to fall back on.
Quaternion? _jointRotationAt(ProjectClip clip, int jointId, double time) {
  for (final projectTrack in clip.tracks) {
    if (projectTrack.objectId != jointId) continue;
    final track = projectTrack.track;
    if (track.path != AnimationPath.rotation) continue;
    final out = Float32List(4);
    track.sample(time, out);
    return Quaternion(out[0], out[1], out[2], out[3]);
  }
  return null;
}

/// Every driver in [drivers] evaluated against [clip] at [time], summed per
/// shape index into a [shapeCount]-long weight list — the additive
/// combination the row's own "аддитивно" asks for: two drivers naming the
/// same [ShapeDriver.shapeIndex] add rather than the second overwriting the
/// first, so a shape two joints both push stays pushed by both.
///
/// A joint [ShapeDriver.jointId] names with no rotation track in [clip] is
/// read as identity — the driver contributes whatever [ShapeDriver.evaluate]
/// gives an unrotated joint, exactly as if the clip held an explicit
/// identity keyframe there.
List<double> evaluateShapeDriversLive({
  required ProjectClip clip,
  required List<ShapeDriver> drivers,
  required double time,
  required int shapeCount,
}) {
  final weights = List<double>.filled(shapeCount, 0.0);
  for (final driver in drivers) {
    if (driver.shapeIndex < 0 || driver.shapeIndex >= shapeCount) continue;
    final rotation =
        _jointRotationAt(clip, driver.jointId, time) ?? Quaternion.identity();
    weights[driver.shapeIndex] += driver.evaluate(rotation);
  }
  return weights;
}

/// [clip], with one more track added: [drivers]' own combined output,
/// sampled at every time any of their joints already carries a rotation
/// keyframe at, written as an ordinary [AnimationPath.weights] track on
/// [shapeTargetObjectId] — so that playing the *baked* clip back needs no
/// driver, no joint lookup, and no [evaluateShapeDriversLive] call at all,
/// the same "запечённое = живое" trade every other bake in this package
/// makes.
///
/// [clip] unchanged when [drivers] is empty or none of them name a joint
/// this clip actually animates — baking a driver nothing here moves would
/// add a track that samples to zero everywhere, which is a real track for
/// no real reason.
ProjectClip bakeShapeDrivers({
  required ProjectClip clip,
  required List<ShapeDriver> drivers,
  required int shapeTargetObjectId,
  required int shapeCount,
}) {
  final times = <double>{};
  for (final driver in drivers) {
    for (final projectTrack in clip.tracks) {
      if (projectTrack.objectId != driver.jointId) continue;
      if (projectTrack.track.path != AnimationPath.rotation) continue;
      times.addAll(projectTrack.track.times);
    }
  }
  if (times.isEmpty) return clip;

  final sortedTimes = times.toList()..sort();
  final table = KeyTable(componentCount: shapeCount);
  for (final time in sortedTimes) {
    table.setKey(
      time,
      evaluateShapeDriversLive(
        clip: clip,
        drivers: drivers,
        time: time,
        shapeCount: shapeCount,
      ),
    );
  }

  return ProjectClip(
    name: clip.name,
    tracks: <ProjectTrack>[
      ...clip.tracks,
      ProjectTrack(
        objectId: shapeTargetObjectId,
        track: table.toAnimationTrack(
          nodeIndex: 0,
          path: AnimationPath.weights,
        ),
      ),
    ],
    extras: clip.extras,
  );
}
