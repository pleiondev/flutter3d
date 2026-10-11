/// Where a world's origin is on the Earth: [GeoOrigin].
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Flutter3dFormatException, WorldPosition;

/// A place on the Earth that a world's origin stands on, and the frame the
/// world's axes keep there.
///
/// **A local east-north-up frame on the WGS 84 ellipsoid.** The world's
/// origin is the point at [latitudeDegrees], [longitudeDegrees] and
/// [altitude]; from there **+x is east, +y is up and −z is north**, the
/// engine's right-handed y-up frame laid on the tangent plane, so a
/// twin's site drawn in the engine needs no rotation and a level's "north"
/// is the way a camera with no rotation looks. [frame] names it, and is the
/// one frame 1.0 knows.
///
/// **Degrees in the names**, because latitude and longitude are written in
/// degrees everywhere they come from (a survey, a GPS fix, a map), and
/// docs/CONTRACTS.md asks a member whose unit is not the engine's to say so.
/// [altitude] is metres above the ellipsoid.
///
/// **Read by the view and the tools, not by the step.** [geodeticOf] and
/// [positionOf] use the platform's `dart:math`, which is not bit-exact
/// across platforms, so a step that must replay never calls them: it works
/// in the world's own metres, and a place on the Earth is turned into one
/// once, where it comes in.
///
/// Held by `WorldProperties.geoOrigin` and a level's `geoOrigin` (the
/// level's wins where both say).
final class GeoOrigin {
  /// The origin at this latitude and longitude, in degrees, and [altitude]
  /// metres above the ellipsoid. Throws an [ArgumentError] for a latitude
  /// outside ±90°, a longitude outside ±180° or a number that is not finite.
  GeoOrigin({
    required this.latitudeDegrees,
    required this.longitudeDegrees,
    this.altitude = 0.0,
  }) {
    if (!latitudeDegrees.isFinite || latitudeDegrees.abs() > 90) {
      throw ArgumentError.value(
        latitudeDegrees,
        'latitudeDegrees',
        'not within ±90',
      );
    }
    if (!longitudeDegrees.isFinite || longitudeDegrees.abs() > 180) {
      throw ArgumentError.value(
        longitudeDegrees,
        'longitudeDegrees',
        'not within ±180',
      );
    }
    if (!altitude.isFinite) {
      throw ArgumentError.value(altitude, 'altitude', 'not finite');
    }
  }

  /// The one frame a world's axes keep on the Earth in 1.0: east-north-up,
  /// laid on the engine's axes as +x east, +y up, −z north.
  static const String frame = 'enu';

  /// Degrees north of the equator, −90 to 90.
  final double latitudeDegrees;

  /// Degrees east of Greenwich, −180 to 180.
  final double longitudeDegrees;

  /// Metres above the WGS 84 ellipsoid.
  final double altitude;

  // WGS 84.
  static const double _a = 6378137.0;
  static const double _f = 1 / 298.257223563;
  static const double _e2 = _f * (2 - _f);

  static double _radians(double degrees) => degrees * math.pi / 180;

  /// The place on the Earth of [position], a point of the world whose
  /// origin is here, as the origin a world centred on it would have.
  GeoOrigin geodeticOf(WorldPosition position) {
    final (x0, y0, z0) = _ecef(this);
    final east = position.x, up = position.y, north = -position.z;
    final phi = _radians(latitudeDegrees), lambda = _radians(longitudeDegrees);
    final sp = math.sin(phi), cp = math.cos(phi);
    final sl = math.sin(lambda), cl = math.cos(lambda);
    final x = x0 - sl * east - sp * cl * north + cp * cl * up;
    final y = y0 + cl * east - sp * sl * north + cp * sl * up;
    final z = z0 + cp * north + sp * up;
    final p = math.sqrt(x * x + y * y);
    var lat = math.atan2(z, p * (1 - _e2));
    var height = 0.0;
    // Five rounds take the latitude to well under a millimetre anywhere a
    // world is built, from the first guess on the sphere's.
    for (var i = 0; i < 5; i++) {
      final s = math.sin(lat);
      final n = _a / math.sqrt(1 - _e2 * s * s);
      height = p / math.cos(lat) - n;
      lat = math.atan2(z, p * (1 - _e2 * n / (n + height)));
    }
    return GeoOrigin(
      latitudeDegrees: lat * 180 / math.pi,
      longitudeDegrees: math.atan2(y, x) * 180 / math.pi,
      altitude: height,
    );
  }

  /// Where [place] is in the world whose origin is here: metres east (+x),
  /// up (+y) and north (−z).
  WorldPosition positionOf(GeoOrigin place) {
    final (x0, y0, z0) = _ecef(this);
    final (x, y, z) = _ecef(place);
    final dx = x - x0, dy = y - y0, dz = z - z0;
    final phi = _radians(latitudeDegrees), lambda = _radians(longitudeDegrees);
    final sp = math.sin(phi), cp = math.cos(phi);
    final sl = math.sin(lambda), cl = math.cos(lambda);
    final east = -sl * dx + cl * dy;
    final north = -sp * cl * dx - sp * sl * dy + cp * dz;
    final up = cp * cl * dx + cp * sl * dy + sp * dz;
    return WorldPosition(east, up, -north);
  }

  static (double, double, double) _ecef(GeoOrigin at) {
    final phi = _radians(at.latitudeDegrees);
    final lambda = _radians(at.longitudeDegrees);
    final s = math.sin(phi);
    final n = _a / math.sqrt(1 - _e2 * s * s);
    final r = (n + at.altitude) * math.cos(phi);
    return (
      r * math.cos(lambda),
      r * math.sin(lambda),
      (n * (1 - _e2) + at.altitude) * s,
    );
  }

  /// `{"latitude": …, "longitude": …, "altitude": …, "frame": "enu"}`,
  /// degrees and metres: what a level's `geoOrigin` and a world's hold.
  Map<String, Object?> toJson() => <String, Object?>{
    'latitude': latitudeDegrees,
    'longitude': longitudeDegrees,
    'altitude': altitude,
    'frame': frame,
  };

  /// Reads what [toJson] wrote; `altitude` and `frame` may be left out.
  /// Throws a [GeoOriginFormatException] naming the field that is not what
  /// it says, a frame other than [frame] among them.
  factory GeoOrigin.fromJson(Object? json) {
    if (json is! Map) {
      throw GeoOriginFormatException('a geo origin is an object, not $json');
    }
    double number(String key, {double? or}) => switch (json[key]) {
      null when or != null => or,
      final num value when value.isFinite => value.toDouble(),
      final other => throw GeoOriginFormatException(
        'a geo origin\'s "$key" is $other, not a finite number',
      ),
    };
    switch (json['frame']) {
      case null || frame:
        break;
      case final other:
        throw GeoOriginFormatException(
          'a geo origin\'s frame is "$other"; this build knows "$frame" '
          '(east, north, up)',
        );
    }
    try {
      return GeoOrigin(
        latitudeDegrees: number('latitude'),
        longitudeDegrees: number('longitude'),
        altitude: number('altitude', or: 0.0),
      );
    } on ArgumentError catch (error) {
      throw GeoOriginFormatException(
        'a geo origin\'s ${error.name}: ${error.message}',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is GeoOrigin &&
      other.latitudeDegrees == latitudeDegrees &&
      other.longitudeDegrees == longitudeDegrees &&
      other.altitude == altitude;

  @override
  int get hashCode => Object.hash(latitudeDegrees, longitudeDegrees, altitude);

  @override
  String toString() =>
      'GeoOrigin($latitudeDegrees°, $longitudeDegrees°, $altitude m)';
}

/// A geo origin in a document that cannot be read.
final class GeoOriginFormatException extends Flutter3dFormatException {
  const GeoOriginFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'GeoOriginFormatException: $message';
}
