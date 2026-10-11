import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:test/test.dart';

void main() {
  // Greenwich's meridian line, near enough.
  final greenwich = GeoOrigin.fromJson(<String, Object?>{
    'latitude': 51.4769,
    'longitude': -0.0005,
    'altitude': 46,
  });

  group('GeoOrigin', () {
    test('the origin is where it says, to a tenth of a millimetre', () {
      final here = greenwich.geodeticOf(WorldPosition.origin);
      expect(here.latDeg, closeTo(51.4769, 1e-9));
      expect(here.lonDeg, closeTo(-0.0005, 1e-9));
      expect(here.altitude, closeTo(46, 1e-4));
    });

    test('+x is east, +y is up and -z is north', () {
      final east = greenwich.geodeticOf(const WorldPosition(1000, 0, 0));
      final north = greenwich.geodeticOf(const WorldPosition(0, 0, -1000));
      final up = greenwich.geodeticOf(const WorldPosition(0, 10, 0));
      expect(east.lonDeg, greaterThan(greenwich.lonDeg));
      expect(east.latDeg, closeTo(greenwich.latDeg, 1e-4));
      expect(north.latDeg, greaterThan(greenwich.latDeg));
      expect(up.altitude, closeTo(56, 1e-3));
      // A degree of latitude there is about 111.25 km on WGS 84.
      expect((north.latDeg - greenwich.latDeg) * 111250, closeTo(1000, 2));
    });

    test('a place 5 km off comes back to the millimetre', () {
      const at = WorldPosition(3000, 25, -4000);
      final back = greenwich.positionOf(greenwich.geodeticOf(at));
      expect(back.x, closeTo(at.x, 1e-3));
      expect(back.y, closeTo(at.y, 1e-3));
      expect(back.z, closeTo(at.z, 1e-3));
    });

    test('round-trips through its document, frame named', () {
      final json = greenwich.toJson();
      expect(json['frame'], 'enu');
      expect(GeoOrigin.fromJson(json), greenwich);
      expect(
        GeoOrigin.fromJson(<String, Object?>{'latitude': 10, 'longitude': 20}),
        GeoOrigin(latitude: 10 * math.pi / 180, longitude: 20 * math.pi / 180),
      );
    });

    test('refuses a frame it does not know and a latitude past a pole', () {
      expect(
        () => GeoOrigin.fromJson(<String, Object?>{
          'latitude': 0,
          'longitude': 0,
          'frame': 'ned',
        }),
        throwsA(
          isA<GeoOriginFormatException>().having(
            (e) => e.message,
            'message',
            contains('ned'),
          ),
        ),
      );
      expect(
        () => GeoOrigin.fromJson(<String, Object?>{
          'latitude': 91,
          'longitude': 0,
        }),
        throwsA(isA<GeoOriginFormatException>()),
      );
    });
  });

  group('a world carries its profile and its place', () {
    test('the standard world writes neither, as it did before', () {
      expect(
        WorldProperties.standard.toJson().keys,
        isNot(contains('profile')),
      );
      expect(
        WorldProperties.standard.toJson().keys,
        isNot(contains('geoOrigin')),
      );
      expect(WorldProperties.standard.profile, SimulationProfile.deterministic);
    });

    test('both round-trip, and a patch lays them over a game', () {
      final world = WorldProperties(
        profile: SimulationProfile.accurate,
        geoOrigin: greenwich,
      );
      expect(WorldProperties.fromJson(world.toJson()), world);
      final patch = WorldPropertiesPatch(
        profile: SimulationProfile.accurate,
        geoOrigin: greenwich,
      );
      expect(patch.profile, SimulationProfile.accurate);
      expect(patch.geoOrigin, greenwich);
      expect(patch.over(WorldProperties.standard), world);
      expect(world.copyWith(clearGeoOrigin: true).geoOrigin, isNull);
    });

    test('a profile this build does not know refuses the world', () {
      expect(
        () => WorldProperties.fromJson(<String, Object?>{'profile': 'fast'}),
        throwsA(
          isA<WorldPropertiesFormatException>().having(
            (e) => e.message,
            'message',
            contains('fast'),
          ),
        ),
      );
    });
  });
}

extension on GeoOrigin {
  double get latDeg => latitude * 180 / math.pi;
  double get lonDeg => longitude * 180 / math.pi;
}
