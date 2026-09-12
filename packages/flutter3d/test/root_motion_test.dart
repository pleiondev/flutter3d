/// `AnimationPlayer.rootMotionDelta`: `anim-16`'s own runtime half, reading
/// back what `root_motion_commands.dart`'s own `ExtractRootMotion` saved
/// under `kRootMotionExtra` — the row's own worked example, "корень стоит,
/// сумма delta за цикл = 2 м".
///
///     flutter test test/root_motion_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/animation/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// The flattened track `ExtractRootMotion` leaves behind — every key at the
/// first key's own value — beside `extra`, the real values it saved.
AnimationClip _extractedWalkCycle({
  required double duration,
  required List<List<double>> realValues,
}) {
  final count = realValues.length;
  final times = Float32List(count);
  for (var i = 0; i < count; i++) {
    times[i] = duration * i / (count - 1);
  }
  final flat = Float32List(count * 3);
  for (var i = 0; i < count; i++) {
    flat[i * 3] = realValues[0][0];
    flat[i * 3 + 1] = realValues[0][1];
    flat[i * 3 + 2] = realValues[0][2];
  }
  return AnimationClip(
    name: 'walk',
    extras: <String, Object?>{
      kRootMotionExtra: <Object?>[for (final v in realValues) List<double>.of(v)],
    },
    tracks: <AnimationTrack>[
      AnimationTrack(
        nodeIndex: 0,
        path: AnimationPath.translation,
        interpolation: AnimationInterpolation.linear,
        componentCount: 3,
        times: times,
        values: flat,
      ),
    ],
  );
}

void main() {
  test('the root stands still in the clip itself, even though the real '
      'motion is 2m — the row\'s own "корень стоит"', () {
    final clip = _extractedWalkCycle(
      duration: 1.0,
      realValues: <List<double>>[
        <double>[0, 0, 0],
        <double>[1, 0, 0],
        <double>[2, 0, 0],
      ],
    );
    final track = clip.tracks.single;
    final out = Float32List(3);
    track.sample(0.5, out);
    // Whatever time is sampled, the flattened track answers the first key's
    // own value — the root has not moved an inch in the clip a mesh actually
    // renders with.
    expect(out.toList(), <double>[0, 0, 0]);
  });

  test('the sum of the deltas over one full cycle is 2m — the row\'s own '
      'worked example', () {
    final clip = _extractedWalkCycle(
      duration: 1.0,
      realValues: <List<double>>[
        <double>[0, 0, 0],
        <double>[1, 0, 0],
        <double>[2, 0, 0],
      ],
    );
    final player = AnimationPlayer(clips: <AnimationClip>[clip], targets: const [])
      ..play(0);

    const steps = 100;
    var total = Vector3.zero();
    for (var i = 0; i < steps; i++) {
      final from = i / steps;
      final to = (i + 1) / steps;
      final delta = player.rootMotionDelta(0, fromTime: from, toTime: to);
      expect(delta, isNotNull);
      total += delta!;
    }

    expect(total.x, closeTo(2.0, 1e-6));
    expect(total.y, closeTo(0.0, 1e-9));
    expect(total.z, closeTo(0.0, 1e-9));
  });

  test('a step that wraps from the end back to the start is one delta, not '
      'two chances to miss the seam', () {
    final clip = _extractedWalkCycle(
      duration: 1.0,
      realValues: <List<double>>[
        <double>[0, 0, 0],
        <double>[2, 0, 0],
      ],
    );
    final player = AnimationPlayer(clips: <AnimationClip>[clip], targets: const [])
      ..play(0);

    // A frame that lands on 0.9s and, after `update`'s own `%=`, on 0.1s of
    // the next lap: the leg from 0.9 to 1.0 (0.2m) plus the leg from 0.0 to
    // 0.1 (0.2m).
    final delta = player.rootMotionDelta(0, fromTime: 0.9, toTime: 0.1);

    expect(delta, isNotNull);
    expect(delta!.x, closeTo(0.4, 1e-6));
  });

  group('refusals', () {
    late AnimationClip clip;
    setUp(() {
      clip = _extractedWalkCycle(
        duration: 1.0,
        realValues: <List<double>>[
          <double>[0, 0, 0],
          <double>[2, 0, 0],
        ],
      );
    });

    test('an ordinary clip with nothing extracted answers null', () {
      final ordinary = AnimationClip(
        name: 'idle',
        tracks: <AnimationTrack>[
          AnimationTrack(
            nodeIndex: 0,
            path: AnimationPath.translation,
            interpolation: AnimationInterpolation.linear,
            componentCount: 3,
            times: Float32List.fromList(<double>[0.0, 1.0]),
            values: Float32List.fromList(<double>[0, 0, 0, 0, 0, 0]),
          ),
        ],
      );
      final player = AnimationPlayer(
        clips: <AnimationClip>[ordinary],
        targets: const [],
      )..play(0);

      expect(
        player.rootMotionDelta(0, fromTime: 0.0, toTime: 0.5),
        isNull,
      );
    });

    test('a node index with no matching track answers null', () {
      final player = AnimationPlayer(clips: <AnimationClip>[clip], targets: const [])
        ..play(0);

      expect(
        player.rootMotionDelta(7, fromTime: 0.0, toTime: 0.5),
        isNull,
      );
    });

    test('cubic tangents are refused rather than replayed as a plain value',
        () {
      final cubic = AnimationClip(
        name: 'walk',
        extras: <String, Object?>{
          kRootMotionExtra: <Object?>[
            <double>[0, 0, 0, 0, 0, 0, 0, 0, 0],
            <double>[0, 0, 0, 2, 0, 0, 0, 0, 0],
          ],
        },
        tracks: <AnimationTrack>[
          AnimationTrack(
            nodeIndex: 0,
            path: AnimationPath.translation,
            interpolation: AnimationInterpolation.cubicSpline,
            componentCount: 3,
            times: Float32List.fromList(<double>[0.0, 1.0]),
            values: Float32List.fromList(List<double>.filled(18, 0.0)),
          ),
        ],
      );
      final player = AnimationPlayer(
        clips: <AnimationClip>[cubic],
        targets: const [],
      )..play(0);

      expect(
        player.rootMotionDelta(0, fromTime: 0.0, toTime: 0.5),
        isNull,
      );
    });
  });
}
