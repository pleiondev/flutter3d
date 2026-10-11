/// Where a world's origin is on the Earth: [GeoOrigin].
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Flutter3dFormatException, Portable, WorldPosition;

/// A place on the Earth that a world's origin stands on, and the frame the
/// world's axes keep there.
///
/// **A local east-north-up frame on the WGS 84 ellipsoid.** The world's
/// origin is the point at [latitude], [longitude] and [altitude]; from
/// there **+x is east, +y is up and −z is north**, the engine's
/// right-handed y-up frame laid on the tangent plane, so a twin's site
/// drawn in the engine needs no rotation and a level's "north" is the way a
/// camera with no rotation looks. [frame] names it, and is the one frame
/// 1.0 knows.
///
/// **Radians here, degrees in the document.** The engine's angles are
/// radians (docs/CONTRACTS.md), so [latitude] and [longitude] are; a level
/// or a world writes them in degrees, `{"latitude": 59.9386, …}`, as every
/// survey, GPS fix and map gives them, and the document's numbers are what
/// is kept, so a place read and written is the same text. [altitude] is
/// metres above the ellipsoid.
///
/// **Bit for bit on every platform.** [geodeticOf] and [positionOf] use the
/// engine's `Portable` sine, cosine and arctangent, so two machines put a
/// sensor at the same place in the world, and a tape that turns a GPS fix
/// into metres replays.
///
/// Held by `WorldProperties.geoOrigin` and a level's `geoOrigin` (the
/// level's wins where both say).
final class GeoOrigin {
  /// The origin at [latitude] and [longitude], in radians, and [altitude]
  /// metres above the ellipsoid. Throws an [ArgumentError] for a latitude
  /// outside ±π/2, a longitude outside ±π or a number that is not finite.
  factory GeoOrigin({
    required double latitude,
    required double longitude,
    double altitude = 0.0,
  }) => GeoOrigin._(
    latitude * 180 / math.pi,
    longitude * 180 / math.pi,
    altitude,
  );

  GeoOrigin._(this._latitude, this._longitude, this.altitude) {
    if (!_latitude.isFinite || _latitude.abs() > 90) {
      throw ArgumentError.value(_latitude, 'latitude', 'not within ±90°');
    }
    if (!_longitude.isFinite || _longitude.abs() > 180) {
      throw ArgumentError.value(_longitude, 'longitude', 'not within ±180°');
    }
    if (!altitude.isFinite) {
      throw ArgumentError.value(altitude, 'altitude', 'not finite');
    }
  }

  /// The one frame a world's axes keep on the Earth in 1.0: east-north-up,
  /// laid on the engine's axes as +x east, +y up, −z north.
  static const String frame = 'enu';

  // As the document says them, in degrees: what equality and the document
  // read, so a place written and read back is the same place to the bit.
  final double _latitude;
  final double _longitude;

  /// Radians north of the equator, −π/2 to π/2.
  double get latitude => _latitude * math.pi / 180;

  /// Radians east of Greenwich, −π to π.
  double get longitude => _longitude * math.pi / 180;

  /// Metres above the WGS 84 ellipsoid.
  final double altitude;

  // WGS 84.
  static const double _a = 6378137.0;
  static const double _f = 1 / 298.257223563;
  static const double _e2 = _f * (2 - _f);

  /// The place on the Earth of [position], a point of the world whose
  /// origin is here, as the origin a world centred on it would have.
  GeoOrigin geodeticOf(WorldPosition position) {
    final (x0, y0, z0) = _ecef(this);
    final east = position.x, up = position.y, north = -position.z;
    final sp = Portable.sin(latitude), cp = Portable.cos(latitude);
    final sl = Portable.sin(longitude), cl = Portable.cos(longitude);
    final x = x0 - sl * east - sp * cl * north + cp * cl * up;
    final y = y0 + cl * east - sp * sl * north + cp * sl * up;
    final z = z0 + cp * north + sp * up;
    final p = math.sqrt(x * x + y * y);
    var lat = Portable.atan2(z, p * (1 - _e2));
    var height = 0.0;
    // Five rounds take the latitude to well under a millimetre anywhere a
    // world is built, from the first guess on the sphere's.
    for (var i = 0; i < 5; i++) {
      final s = Portable.sin(lat);
      final n = _a / math.sqrt(1 - _e2 * s * s);
      height = p / Portable.cos(lat) - n;
      lat = Portable.atan2(z, p * (1 - _e2 * n / (n + height)));
    }
    return GeoOrigin(
      latitude: lat,
      longitude: Portable.atan2(y, x),
      altitude: height,
    );
  }

  /// Where [place] is in the world whose origin is here: metres east (+x),
  /// up (+y) and north (−z).
  WorldPosition positionOf(GeoOrigin place) {
    final (x0, y0, z0) = _ecef(this);
    final (x, y, z) = _ecef(place);
    final dx = x - x0, dy = y - y0, dz = z - z0;
    final sp = Portable.sin(latitude), cp = Portable.cos(latitude);
    final sl = Portable.sin(longitude), cl = Portable.cos(longitude);
    final east = -sl * dx + cl * dy;
    final north = -sp * cl * dx - sp * sl * dy + cp * dz;
    final up = cp * cl * dx + cp * sl * dy + sp * dz;
    return WorldPosition(east, up, -north);
  }

  static (double, double, double) _ecef(GeoOrigin at) {
    final s = Portable.sin(at.latitude);
    final n = _a / math.sqrt(1 - _e2 * s * s);
    final r = (n + at.altitude) * Portable.cos(at.latitude);
    return (
      r * Portable.cos(at.longitude),
      r * Portable.sin(at.longitude),
      (n * (1 - _e2) + at.altitude) * s,
    );
  }

  /// `{"latitude": …, "longitude": …, "altitude": …, "frame": "enu"}`, in
  /// degrees and metres: what a level's `geoOrigin` and a world's hold.
  Map<String, Object?> toJson() => <String, Object?>{
    'latitude': _latitude,
    'longitude': _longitude,
    'altitude': altitude,
    'frame': frame,
  };

  /// Reads what [toJson] wrote, latitude and longitude in degrees;
  /// `altitude` and `frame` may be left out. Throws a
  /// [GeoOriginFormatException] naming the field that is not what it says,
  /// a frame other than [frame] among them.
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
      return GeoOrigin._(
        number('latitude'),
        number('longitude'),
        number('altitude', or: 0.0),
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
      other._latitude == _latitude &&
      other._longitude == _longitude &&
      other.altitude == altitude;

  @override
  int get hashCode => Object.hash(_latitude, _longitude, altitude);

  @override
  String toString() => 'GeoOrigin($_latitude°, $_longitude°, $altitude m)';
}

/// A geo origin in a document that cannot be read.
final class GeoOriginFormatException extends Flutter3dFormatException {
  const GeoOriginFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'GeoOriginFormatException: $message';
}
