/// What a timeline's curve editor needs to draw one component of a
/// [KeyTable] — `anim-06`'s own row: dense samples for the line itself, a
/// handle pair for each key a person can drag, the value range to scale the
/// vertical axis by, and Euler angles for a rotation track's own display,
/// since nothing draws four quaternion components as three curves and
/// expects a person to recognize the shape.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:vector_math/vector_math.dart';

import 'key_table.dart';

/// [sampleCount] evenly-spaced points across [table]'s own duration, each
/// [table]'s own [component] read through [KeyTable.sample] — so a step
/// track comes out piecewise-constant (holding the previous key's value
/// until the next key's time) for the same reason [AnimationTrack.sample]
/// itself holds it, and a cubic-spline track matches
/// [AnimationTrack.sample] exactly, because this *is* that call, not a
/// second interpolation written to look the same.
List<(double, double)> curveSamples(
  KeyTable table,
  int component, {
  required int sampleCount,
}) {
  if (table.keyCount == 0 || sampleCount < 1) return const <(double, double)>[];
  final start = table.keys.first.time;
  final end = table.duration;
  final out = Float32List(table.componentCount);
  final points = <(double, double)>[];
  for (var i = 0; i < sampleCount; i++) {
    final t = sampleCount == 1
        ? start
        : start + (end - start) * i / (sampleCount - 1);
    table.sample(t, out);
    points.add((t, out[component]));
  }
  return points;
}

/// The screen-space positions of key [keyIndex]'s own two tangent handles,
/// [handleLength] seconds out from the key on either side — a straight
/// line from the key through `value + tangent * dt`, the ordinary
/// Hermite-handle construction: the tangent is a slope (value per second),
/// and a line at that slope for [handleLength] seconds is exactly the
/// segment a person drags to change it.
///
/// Both handles read as the key's own position itself — a zero-length
/// segment, not an error — when [table]'s own interpolation is not
/// [AnimationInterpolation.cubicSpline] or the key carries no tangent of
/// its own kind: there is nothing to drag on a straight line between two
/// points, and a handle that appeared anyway would suggest there was.
({Vector2 inHandle, Vector2 outHandle}) tangentHandles(
  KeyTable table,
  int keyIndex,
  int component, {
  double handleLength = 0.1,
}) {
  final key = table.keys[keyIndex];
  final value = key.values[component];
  final position = Vector2(key.time, value);

  if (table.interpolation != AnimationInterpolation.cubicSpline) {
    return (inHandle: position, outHandle: position);
  }

  final inSlope = key.inTangent?[component] ?? 0.0;
  final outSlope = key.outTangent?[component] ?? 0.0;
  return (
    inHandle: Vector2(
      key.time - handleLength,
      value - inSlope * handleLength,
    ),
    outHandle: Vector2(
      key.time + handleLength,
      value + outSlope * handleLength,
    ),
  );
}

/// The lowest and highest value [table]'s own [component] reaches across
/// every key — what a curve editor scales its vertical axis to fit.
({double min, double max}) valueRange(KeyTable table, int component) {
  if (table.keyCount == 0) return (min: 0.0, max: 0.0);
  var min = double.infinity;
  var max = double.negativeInfinity;
  for (final key in table.keys) {
    final v = key.values[component];
    if (v < min) min = v;
    if (v > max) max = v;
  }
  return (min: min, max: max);
}

/// [q]'s own rotation as yaw (around Y), pitch (around X) and roll (around
/// Z), in radians — the inverse of `Quaternion.euler(yaw, pitch, roll)`,
/// which composes a rotation from exactly these three in that order.
///
/// **For display only, and the row's own line says so.** Nothing in this
/// engine stores a rotation this way — `ModelNode.rotation`,
/// `AnimationTrack`'s own rotation path, `Pose.rotations`, all quaternions
/// — and this function's whole job is to give a curve editor three numbers
/// to draw as three lines, not to become a second representation anything
/// downstream reads. Gimbal lock is a fact about Euler angles, not about
/// the quaternion this reads from, and it shows up here as the yaw and
/// roll terms trading a whole turn between them at the pole — a real
/// property of the display, not a bug in the extraction.
Vector3 eulerOf(Quaternion q) {
  final x = q.x, y = q.y, z = q.z, w = q.w;

  final sinPitch = (2.0 * (w * x - y * z)).clamp(-1.0, 1.0);
  final pitch = math.asin(sinPitch);

  final yaw = math.atan2(2.0 * (w * y + x * z), 1.0 - 2.0 * (x * x + y * y));
  final roll = math.atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (x * x + z * z));

  return Vector3(pitch, yaw, roll);
}
