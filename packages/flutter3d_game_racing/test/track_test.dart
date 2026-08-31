import 'dart:math' as math;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A plain ring: sixteen points, sixty metres across, twelve metres wide.
///
/// Flat and untilted unless a test asks otherwise, because a test about camber
/// should not also be a test about the shape of a hill.
TrackSpline ring({
  double radius = 60.0,
  int points = 16,
  double width = 12.0,
  double shoulder = 4.0,
  double Function(int index)? height,
  double Function(int index)? bank,
  double Function(int index)? widthAt,
  List<SurfaceBand> surfaces = const <SurfaceBand>[],
  List<BarrierBand> barriers = const <BarrierBand>[],
  List<double> checkpoints = const <double>[],
  StartGrid grid = const StartGrid(),
}) {
  final positions = <Vector3>[
    for (var i = 0; i < points; i++)
      Vector3(
        radius * math.cos(2 * math.pi * i / points),
        height?.call(i) ?? 0.0,
        radius * math.sin(2 * math.pi * i / points),
      ),
  ];
  return TrackSpline(
    centre: CatmullRom(positions),
    widths: <double>[
      for (var i = 0; i < points; i++) widthAt?.call(i) ?? width,
    ],
    banks: <double>[for (var i = 0; i < points; i++) bank?.call(i) ?? 0.0],
    shoulder: shoulder,
    surfaces: surfaces,
    barriers: barriers,
    checkpoints: checkpoints,
    grid: grid,
  );
}

void main() {
  group('the frame on the road', () {
    test('forward, right and up are a right-angled set of unit vectors', () {
      final track = ring();
      final frame = TrackFrame();

      for (var i = 0; i < 40; i++) {
        track.frameAt(track.length * i / 40, frame);

        expect(frame.forward.length, closeTo(1.0, 1e-6));
        expect(frame.right.length, closeTo(1.0, 1e-6));
        expect(frame.up.length, closeTo(1.0, 1e-6));
        expect(frame.forward.dot(frame.right), closeTo(0.0, 1e-6));
        expect(frame.forward.dot(frame.up), closeTo(0.0, 1e-6));
        expect(frame.right.dot(frame.up), closeTo(0.0, 1e-6));
      }
    });

    test('an untilted road is level and its normal points up', () {
      final track = ring();
      final frame = TrackFrame();

      track.frameAt(0.0, frame);

      expect(frame.right.y, closeTo(0.0, 1e-9));
      expect(frame.up.y, closeTo(1.0, 1e-9));
    });

    test('camber raises the outside edge and leans the normal into the turn',
        () {
      // Mutation: rotate `right` and leave `up` alone. The road would tilt and
      // its normal would not, so the load a car puts through a banked corner
      // would still be straight down — the corner would look banked and drive
      // flat, which is the one thing a banked corner is for.
      final track = ring(bank: (_) => 0.15);
      final frame = TrackFrame();
      final outside = Vector3.zero();
      final inside = Vector3.zero();

      track
        ..frameAt(0.0, frame)
        ..surfacePoint(0.0, 6.0, outside)
        ..surfacePoint(0.0, -6.0, inside);

      expect(outside.y, greaterThan(inside.y));
      expect(frame.up.y, lessThan(1.0));
      expect(frame.up.y, greaterThan(0.9));
      expect(frame.forward.dot(frame.up), closeTo(0.0, 1e-9));
    });

    test('the road surface is one flat ribbon across its width', () {
      // The whole reason the road is not made of boxes: across the track it must
      // be a straight line, not a staircase.
      final track = ring(bank: (_) => 0.2);
      final frame = TrackFrame();
      final near = Vector3.zero();
      final far = Vector3.zero();
      final middle = Vector3.zero();

      track
        ..frameAt(30.0, frame)
        ..surfacePoint(30.0, -6.0, near)
        ..surfacePoint(30.0, 6.0, far)
        ..surfacePoint(30.0, 0.0, middle);

      final midpoint = (near + far)..scale(0.5);
      expect(midpoint.distanceTo(middle), lessThan(1e-9));
    });
  });

  group('numbers authored per control point', () {
    test('a value is exact at the control point it was authored at', () {
      final track = ring(widthAt: (i) => i.isEven ? 8.0 : 16.0);

      expect(track.widthAt(track.centre.distanceToPoint(0)), closeTo(8.0, 1e-6));
      expect(track.widthAt(track.centre.distanceToPoint(1)), closeTo(16.0, 1e-6));
      expect(track.widthAt(track.centre.distanceToPoint(2)), closeTo(8.0, 1e-6));
    });

    test('the road edge has no crease where two widths meet', () {
      // Mutation: interpolate in a straight line instead of smoothing. The width
      // stays continuous either way — what breaks is its slope, and the kink
      // that leaves at every control point is visible down the edge of the road
      // and audible in the suspension crossing it.
      final track = ring(widthAt: (i) => i.isEven ? 8.0 : 16.0);
      final at = track.centre.distanceToPoint(1);
      const step = 0.25;

      // The second difference of the width across the control point: zero for a
      // smooth join, and the full change of slope for a linear one.
      final before = track.widthAt(at - step);
      final here = track.widthAt(at);
      final after = track.widthAt(at + step);
      final kink = (after - 2 * here + before).abs();

      expect(kink, lessThan(0.02));
    });

    test('a width for every point, or the track is refused', () {
      // Mutation: pad or truncate to fit. A track whose widths are off by one
      // is a track where every corner is the width of the one before it, and
      // nothing about that says so at load time.
      expect(
        () => TrackSpline(
          centre: CatmullRom([
            Vector3(0.0, 0.0, 0.0),
            Vector3(50.0, 0.0, 0.0),
            Vector3(25.0, 0.0, 40.0),
          ]),
          widths: <double>[12.0, 12.0],
          banks: <double>[0.0, 0.0, 0.0],
        ),
        throwsArgumentError,
      );
    });

    test('checkpoints out of order are refused', () {
      // A lap counter walks them in turn, so a list that doubles back is a lap
      // that can never be completed — and the symptom is a car driving round
      // forever with the lap counter stuck at nought.
      expect(
        () => ring(checkpoints: <double>[100.0, 60.0]),
        throwsArgumentError,
      );
    });
  });

  group('what the track says about a place on it', () {
    test('the road is named at the centre and the shoulder beside it', () {
      final track = ring(
        surfaces: <SurfaceBand>[
          SurfaceBand(fromS: 0.0, toS: 1000.0, centre: 'asphalt', shoulder: 'gravel'),
        ],
      );

      expect(track.surfaceAt(20.0, 0.0), 'asphalt');
      expect(track.surfaceAt(20.0, 5.0), 'asphalt');
      expect(track.surfaceAt(20.0, 8.0), 'gravel');
    });

    test('a band that runs across the start line covers both sides of it', () {
      // Mutation: `s >= fromS && s < toS` alone. The one band that has to work
      // is the one over the finish line, and it would be the one that silently
      // covers nothing.
      final track = ring(
        surfaces: <SurfaceBand>[
          SurfaceBand(fromS: 300.0, toS: 40.0, centre: 'ice'),
        ],
      );

      expect(track.surfaceAt(320.0, 0.0), 'ice');
      expect(track.surfaceAt(10.0, 0.0), 'ice');
      expect(track.surfaceAt(150.0, 0.0), isNull);
    });

    test('a wall is reported on the side it was built', () {
      final track = ring(
        barriers: <BarrierBand>[
          BarrierBand(fromS: 0.0, toS: 100.0, right: true),
        ],
      );

      expect(track.barrierAt(50.0, left: false), isTrue);
      expect(track.barrierAt(50.0, left: true), isFalse);
      expect(track.barrierAt(200.0, left: false), isFalse);
    });
  });

  group('the starting grid', () {
    test('pole is ahead of the row behind it', () {
      // Mutation: lay the rows out forwards from `grid.s`. The field would start
      // in front of the line it is meant to be behind, and every car would be
      // credited with a lap it had not driven.
      //
      // Measured along the track rather than straight across. Slots offset
      // towards the inside of a corner sit on a smaller radius, so the distance
      // through the air between two rows is genuinely shorter than the distance
      // round the track — a difference of a sixth of a metre on this ring, and
      // nothing to do with where the rows were put.
      final track = ring(grid: const StartGrid(columns: 2, rowGap: 6.0));
      final pole = Vector3.zero();
      final third = Vector3.zero();
      final forward = Vector3.zero();

      track
        ..startSlot(0, pole, forward)
        ..startSlot(2, third, forward);

      final ahead = track.centre.closestSGlobal(pole);
      final behind = track.centre.closestSGlobal(third);

      expect(track.centre.wrap(ahead - behind), closeTo(6.0, 0.2));
    });

    test('a row straddles the centre line rather than sitting on one side', () {
      // Mutation: offset slots by `column * columnGap`. The grid would sit
      // entirely to one side of the track and the outside row would start on
      // the grass.
      final track = ring(grid: const StartGrid(columns: 2, columnGap: 4.0));
      final left = Vector3.zero();
      final right = Vector3.zero();
      final forward = Vector3.zero();
      final centre = Vector3.zero();

      track
        ..startSlot(0, left, forward)
        ..startSlot(1, right, forward)
        ..centreAt(track.grid.s, centre);

      expect(left.distanceTo(right), closeTo(4.0, 1e-6));
      expect(centre.distanceTo(left), closeTo(2.0, 1e-6));
      expect(centre.distanceTo(right), closeTo(2.0, 1e-6));
    });

    test('the grid faces the way the track goes', () {
      final track = ring();
      final position = Vector3.zero();
      final forward = Vector3.zero();
      final tangent = Vector3.zero();

      track
        ..startSlot(0, position, forward)
        ..centre.tangentAt(track.grid.s, tangent);

      expect(forward.dot(tangent), closeTo(1.0, 1e-6));
    });
  });

  group('the ground under a car', () {
    test('the road answers without touching the collision world', () {
      // There is no world here at all. If the surface came from geometry this
      // could not be written, and that is the point of it.
      final field = TrackField(track: ring());
      final sample = GroundSample();
      final on = Vector3(60.0, 2.0, 0.0);

      expect(field.sample(on, 0.0, sample), isTrue);
      expect(sample.onRoad, isTrue);
      expect(sample.height, closeTo(0.0, 1e-6));
      expect(sample.lateral.abs(), lessThan(0.01));
    });

    test('height is continuous all the way round an undulating track', () {
      // Mutation: work the height out per segment from the control points either
      // side rather than from the curve. A seam of a few centimetres at every
      // control point is a car that hits a step sixteen times a lap.
      final field = TrackField(
        track: ring(height: (i) => 3.0 * math.sin(2 * math.pi * i / 8)),
      );
      final sample = GroundSample();
      final probe = Vector3.zero();
      final track = ring(height: (i) => 3.0 * math.sin(2 * math.pi * i / 8));

      var previous = double.nan;
      var hint = 0.0;
      var biggestStep = 0.0;
      for (var s = 0.0; s < track.length; s += 0.2) {
        track.surfacePoint(s, 3.0, probe);
        expect(field.sample(probe, hint, sample), isTrue);
        if (!previous.isNaN) {
          biggestStep = math.max(biggestStep, (sample.height - previous).abs());
        }
        previous = sample.height;
        hint = sample.s;
      }

      expect(biggestStep, lessThan(0.05));
    });

    test('the shoulder is off the road but still ground', () {
      final field = TrackField(
        track: ring(
          surfaces: <SurfaceBand>[
            SurfaceBand(fromS: 0.0, toS: 1000.0, centre: 'asphalt', shoulder: 'gravel'),
          ],
        ),
      );
      final sample = GroundSample();

      // Eight metres out: past the six-metre half width, inside the four-metre
      // shoulder.
      expect(field.sample(Vector3(68.0, 1.0, 0.0), 0.0, sample), isTrue);
      expect(sample.onRoad, isFalse);
      expect(sample.surface, 'gravel');
    });

    test('past the shoulder the level answers instead', () {
      final world = CollisionWorld();
      final brush = Brush(
        centre: Vector3(90.0, -1.0, 0.0),
        size: Vector3(20.0, 2.0, 20.0),
        surface: 'grass',
      );
      world.add(
        Collider(
          shape: CollisionBox(Vector3(10.0, 1.0, 10.0)),
          position: Vector3(90.0, -1.0, 0.0),
          userData: brush,
        ),
      );

      final field = TrackField(track: ring(), world: world);
      final sample = GroundSample();

      expect(field.sample(Vector3(90.0, 1.0, 0.0), 0.0, sample), isTrue);
      expect(sample.onRoad, isFalse);
      expect(sample.height, closeTo(0.0, 1e-6));
      expect(sample.surface, 'grass');
    });

    test('over nothing at all is a fall, not a floor at zero', () {
      // Mutation: return true with whatever is left in `out`. A car off the edge
      // of the world would land on the last surface it drove over, which reads
      // as a car hovering in mid-air.
      final field = TrackField(track: ring(), world: CollisionWorld());
      final sample = GroundSample();

      expect(field.sample(Vector3(400.0, 1.0, 0.0), 0.0, sample), isFalse);
    });

    test('the hint keeps a car on its own side of a narrow track', () {
      // The reason `sample` takes a hint at all. This ring is sixty metres
      // across; a point in the middle of it is equidistant from everywhere, so
      // the answer is whatever the search happened to look at first — unless the
      // hint decides it.
      final track = ring();
      final field = TrackField(track: track);
      final sample = GroundSample();
      final middle = Vector3(0.0, 0.0, 0.0);

      field.sample(middle, 10.0, sample);
      final nearStart = sample.s;
      field.sample(middle, track.length / 2, sample);
      final nearHalfway = sample.s;

      double gap(double a, double b) {
        final raw = (track.centre.wrap(a) - track.centre.wrap(b)).abs();
        return math.min(raw, track.length - raw);
      }

      expect(gap(nearStart, 10.0), lessThan(31.0));
      expect(gap(nearHalfway, track.length / 2), lessThan(31.0));
      expect(gap(nearStart, nearHalfway), greaterThan(100.0));
    });
  });
}
