/// A parametric shape and its JSON, which two different files need.
///
/// **Split out because the format and the command ask the same question.** The
/// project file writes a cylinder's radius and segment count so that the
/// cylinder comes back a cylinder; `SetParametric` writes the same numbers so
/// that a journal replays the change somebody made to them. Two spellings of
/// one shape's parameters is two chances for a file and a journal to disagree
/// about what a torus is.
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

/// A parametric shape as JSON.
///
/// **The parameters, not the mesh they build.** This is the one thing glTF
/// cannot hold and therefore the whole reason the format exists: a cylinder
/// that comes back knowing it is a cylinder of 32 segments can be made a
/// cylinder of 48, and one that comes back as faces cannot.
///
/// The `shape` key is spelled out rather than taken from `ParametricShape.name`
/// — that one answers "cone" for a cylinder with a zero radius and is free text
/// on a lathe, so a file keyed by it would not read back as what it was.
Map<String, Object?> parametricShapeJson(ParametricShape shape) =>
    switch (shape) {
      ParametricCuboid(:final Vector3 size) => <String, Object?>{
        'shape': 'cuboid',
        'size': <double>[size.x, size.y, size.z],
      },
      ParametricPlane(
        :final double width,
        :final double depth,
        :final int widthSegments,
        :final int depthSegments,
      ) =>
        <String, Object?>{
          'shape': 'plane',
          'width': width,
          'depth': depth,
          'widthSegments': widthSegments,
          'depthSegments': depthSegments,
        },
      ParametricLathe(
        :final List<Vector2> profile,
        :final int segments,
        :final double startAngle,
        :final double sweepAngle,
        :final bool closedProfile,
        :final String name,
      ) =>
        <String, Object?>{
          'shape': 'lathe',
          'profile': <List<double>>[
            for (final Vector2 point in profile) <double>[point.x, point.y],
          ],
          'segments': segments,
          'startAngle': startAngle,
          'sweepAngle': sweepAngle,
          'closedProfile': closedProfile,
          'name': name,
        },
      ParametricSphere(
        :final double radius,
        :final int segments,
        :final int rings,
      ) =>
        <String, Object?>{
          'shape': 'sphere',
          'radius': radius,
          'segments': segments,
          'rings': rings,
        },
      ParametricCylinder(
        :final double radiusTop,
        :final double radiusBottom,
        :final double height,
        :final int segments,
        :final bool capped,
      ) =>
        <String, Object?>{
          'shape': 'cylinder',
          'radiusTop': radiusTop,
          'radiusBottom': radiusBottom,
          'height': height,
          'segments': segments,
          'capped': capped,
        },
      ParametricTorus(
        :final double radius,
        :final double tubeRadius,
        :final int segments,
        :final int tubeSegments,
      ) =>
        <String, Object?>{
          'shape': 'torus',
          'radius': radius,
          'tubeRadius': tubeRadius,
          'segments': segments,
          'tubeSegments': tubeSegments,
        },
    };

/// The shape [json] describes, or null if this build cannot build it.
///
/// Every parameter is required rather than defaulted. A missing `segments` that
/// quietly became 32 would give back a cylinder that is not the one that was
/// saved, and the person who notices is the one who exported it.
ParametricShape? parametricShapeFrom(Map<String, Object?> json) =>
    switch (json) {
      {'shape': 'cuboid', 'size': [final num x, final num y, final num z]} =>
        ParametricCuboid(
          size: Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
        ),
      {
        'shape': 'plane',
        'width': final num width,
        'depth': final num depth,
        'widthSegments': final int widthSegments,
        'depthSegments': final int depthSegments,
      } =>
        ParametricPlane(
          width: width.toDouble(),
          depth: depth.toDouble(),
          widthSegments: widthSegments,
          depthSegments: depthSegments,
        ),
      {
        'shape': 'lathe',
        'profile': final List<Object?> profile,
        'segments': final int segments,
        'startAngle': final num startAngle,
        'sweepAngle': final num sweepAngle,
        'closedProfile': final bool closedProfile,
        'name': final String name,
      } =>
        _latheFrom(
          profile,
          segments: segments,
          startAngle: startAngle.toDouble(),
          sweepAngle: sweepAngle.toDouble(),
          closedProfile: closedProfile,
          name: name,
        ),
      {
        'shape': 'sphere',
        'radius': final num radius,
        'segments': final int segments,
        'rings': final int rings,
      } =>
        ParametricSphere(
          radius: radius.toDouble(),
          segments: segments,
          rings: rings,
        ),
      {
        'shape': 'cylinder',
        'radiusTop': final num radiusTop,
        'radiusBottom': final num radiusBottom,
        'height': final num height,
        'segments': final int segments,
        'capped': final bool capped,
      } =>
        ParametricCylinder(
          radiusTop: radiusTop.toDouble(),
          radiusBottom: radiusBottom.toDouble(),
          height: height.toDouble(),
          segments: segments,
          capped: capped,
        ),
      {
        'shape': 'torus',
        'radius': final num radius,
        'tubeRadius': final num tubeRadius,
        'segments': final int segments,
        'tubeSegments': final int tubeSegments,
      } =>
        ParametricTorus(
          radius: radius.toDouble(),
          tubeRadius: tubeRadius.toDouble(),
          segments: segments,
          tubeSegments: tubeSegments,
        ),
      _ => null,
    };

ParametricLathe? _latheFrom(
  List<Object?> profile, {
  required int segments,
  required double startAngle,
  required double sweepAngle,
  required bool closedProfile,
  required String name,
}) {
  final points = <Vector2>[];
  for (final Object? point in profile) {
    if (point case [final num x, final num y]) {
      points.add(Vector2(x.toDouble(), y.toDouble()));
    } else {
      return null;
    }
  }
  return ParametricLathe(
    profile: points,
    segments: segments,
    startAngle: startAngle,
    sweepAngle: sweepAngle,
    closedProfile: closedProfile,
    name: name,
  );
}
