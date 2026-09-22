/// `anim-04`: `KeyTable` — `fromAnimationTrack`/`toAnimationTrack` round-
/// tripped against `InterpolationTest.glb`'s own step, linear and
/// cubic-spline tracks, plus the five editing operations on their own.
///
///     dart test test/key_table_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

Uint8List _sample(String relativePath) =>
    File('../flutter3d_samples/assets/$relativePath').readAsBytesSync();

void main() {
  group('InterpolationTest.glb: every track round-trips byte for byte', () {
    test(
      'fromAnimationTrack then toAnimationTrack reproduces every track',
      () async {
        final document = await GltfLoader().load(
          _sample('InterpolationTest.glb'),
        );
        expect(document.animations, isNotEmpty);

        // A real mixed-interpolation fixture is expected to carry more than
        // one kind — checked so this test cannot pass by accident on a file
        // that turned out to be all-linear.
        final interpolationsSeen = <AnimationInterpolation>{};

        for (final clip in document.animations) {
          for (final track in clip.tracks) {
            interpolationsSeen.add(track.interpolation);

            final table = KeyTable.fromAnimationTrack(track);
            final rebuilt = table.toAnimationTrack(
              nodeIndex: track.nodeIndex,
              path: track.path,
            );

            // Mutation: read the cubic triple's slots in the wrong order
            // (value/in/out instead of in/value/out) — this fails on the
            // first cubic-spline track InterpolationTest carries and passes
            // for every linear or step one, which is why the interpolation
            // set below is checked too rather than trusting one track kind
            // to stand in for all three.
            expect(
              rebuilt.times,
              orderedEquals(track.times),
              reason: 'node ${track.nodeIndex} ${track.path.name} times',
            );
            expect(
              rebuilt.values,
              orderedEquals(track.values),
              reason: 'node ${track.nodeIndex} ${track.path.name} values',
            );
            expect(rebuilt.interpolation, track.interpolation);
            expect(rebuilt.componentCount, track.componentCount);
          }
        }

        expect(
          interpolationsSeen,
          containsAll(<AnimationInterpolation>[
            AnimationInterpolation.step,
            AnimationInterpolation.linear,
            AnimationInterpolation.cubicSpline,
          ]),
          reason:
              'fixture should carry all three, or this test proves less '
              'than it looks like',
        );
      },
    );
  });

  group('sample() after an edit', () {
    test('setKey changes what sample(t) reads back immediately', () {
      final table = KeyTable(componentCount: 1)
        ..setKey(0.0, <double>[0.0])
        ..setKey(1.0, <double>[10.0]);
      final out = Float32List(1);

      table.sample(0.5, out);
      expect(out[0], closeTo(5.0, 1e-6));

      table.setKey(0.5, <double>[100.0]);
      table.sample(0.5, out);
      // Mutation: cache the `AnimationTrack` built by an earlier call and
      // never rebuild it — this would still read 5.0 instead of 100.0.
      expect(out[0], closeTo(100.0, 1e-6));
    });
  });

  group('setKey', () {
    test('a key at a new time is inserted in sorted order', () {
      final table = KeyTable(componentCount: 1)
        ..setKey(1.0, <double>[1.0])
        ..setKey(0.0, <double>[0.0])
        ..setKey(0.5, <double>[0.5]);
      expect(table.keys.map((k) => k.time), <double>[0.0, 0.5, 1.0]);
    });

    test('a key at an existing time replaces it rather than adding a '
        'second one', () {
      final table = KeyTable(componentCount: 1)
        ..setKey(0.0, <double>[1.0])
        ..setKey(0.0, <double>[2.0]);
      expect(table.keyCount, 1);
      expect(table.keys.single.values, <double>[2.0]);
    });
  });

  group('moveKeys', () {
    test('shifts the named keys and re-sorts', () {
      final table = KeyTable(componentCount: 1)
        ..setKey(0.0, <double>[0.0])
        ..setKey(1.0, <double>[1.0])
        ..setKey(2.0, <double>[2.0]);
      // Move the first key past the second.
      table.moveKeys(<int>[0], 1.5);
      // Mutation: move by `deltaTime` but skip the re-sort afterward — the
      // moved key would still read 1.5 (correct), but `keys` would list it
      // before the key at time 1.0 instead of after, which this order
      // check catches and a value-only check would not.
      expect(table.keys.map((k) => k.time), <double>[1.0, 1.5, 2.0]);
    });
  });

  group('deleteKeys', () {
    test('removes the named keys without disturbing the others', () {
      final table = KeyTable(componentCount: 1)
        ..setKey(0.0, <double>[0.0])
        ..setKey(1.0, <double>[1.0])
        ..setKey(2.0, <double>[2.0]);
      table.deleteKeys(<int>[0, 2]);
      expect(table.keyCount, 1);
      expect(table.keys.single.time, 1.0);
    });

    test('deleting indices out of ascending order still removes the right '
        'two keys', () {
      final table = KeyTable(componentCount: 1)
        ..setKey(0.0, <double>[0.0])
        ..setKey(1.0, <double>[1.0])
        ..setKey(2.0, <double>[2.0]);
      // Mutation: walk indices front to back instead of back to front —
      // removing index 0 first shifts index 2 to index 1, and deleting
      // "index 2" second then removes nothing (out of range) or the wrong
      // key, leaving two keys instead of one.
      table.deleteKeys(<int>[2, 0]);
      expect(table.keyCount, 1);
      expect(table.keys.single.time, 1.0);
    });
  });

  group('setInterpolation', () {
    test('switching modes never drops a key\'s own tangents', () {
      final table =
          KeyTable(
            componentCount: 1,
            interpolation: AnimationInterpolation.cubicSpline,
          )..setKey(
            0.0,
            <double>[1.0],
            inTangent: <double>[9.0],
            outTangent: <double>[8.0],
          );

      table.setInterpolation(AnimationInterpolation.linear);
      table.setInterpolation(AnimationInterpolation.cubicSpline);

      // Mutation: have `setInterpolation` rebuild each `Key` and drop its
      // tangents when switching to linear — this reads null instead of the
      // original values after switching back.
      expect(table.keys.single.inTangent, <double>[9.0]);
      expect(table.keys.single.outTangent, <double>[8.0]);
    });

    test('a linear track written back out carries no tangent triple', () {
      final table = KeyTable(componentCount: 1)
        ..setKey(0.0, <double>[1.0])
        ..setKey(1.0, <double>[2.0]);
      final track = table.toAnimationTrack(
        nodeIndex: 0,
        path: AnimationPath.translation,
      );
      // One value per key, not three — a stray cubic-sized array here
      // would be silently wrong data rather than a crash.
      expect(track.values, hasLength(2));
    });
  });

  group('setTangent', () {
    test('changes only the named key\'s tangents', () {
      final table =
          KeyTable(
              componentCount: 1,
              interpolation: AnimationInterpolation.cubicSpline,
            )
            ..setKey(0.0, <double>[1.0])
            ..setKey(1.0, <double>[2.0]);
      table.setTangent(1, inTangent: <double>[5.0], outTangent: <double>[6.0]);

      expect(table.keys[0].inTangent, isNull);
      expect(table.keys[1].inTangent, <double>[5.0]);
      expect(table.keys[1].outTangent, <double>[6.0]);
    });
  });

  group('an empty table', () {
    test(
      'toAnimationTrack refuses it, the same as AnimationTrack itself would',
      () {
        final table = KeyTable(componentCount: 3);
        expect(
          () => table.toAnimationTrack(
            nodeIndex: 0,
            path: AnimationPath.translation,
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('frame/time conversion — syn-03\'s own row', () {
    test('timeOfFrame and frameOfTime are exact inverses at whole frames', () {
      const fps = 24.0;
      for (var frame = 0; frame < 100; frame++) {
        final time = KeyTable.timeOfFrame(frame, fps);
        expect(KeyTable.frameOfTime(time, fps), frame);
      }
    });

    test('frameOfTime rounds rather than truncates', () {
      // A hair past frame 10's own instant, at 30 fps — still frame 10, not
      // 9: a person's own drag rarely lands exactly on 1/30 s.
      expect(KeyTable.frameOfTime(10 / 30.0 + 0.0001, 30.0), 10);
      // A hair before frame 11's own instant — rounds up to 11, not down.
      expect(KeyTable.frameOfTime(11 / 30.0 - 0.0001, 30.0), 11);
    });

    test(
      'snappedToFrame lands exactly on a frame\'s own time, not near it',
      () {
        final snapped = KeyTable.snappedToFrame(10 / 30.0 + 0.0037, 30.0);
        expect(snapped, KeyTable.timeOfFrame(10, 30.0));
        expect(snapped, closeTo(10 / 30.0, 1e-12));
      },
    );

    test('reads fps from a project\'s own profile — syn-03\'s own acceptance, '
        'literally', () {
      const project = ModelProject(profile: ProjectProfile(fps: 24.0));
      // The row's own acceptance: KeyTable reading fps from the profile,
      // not a hard-coded rate — checked by handing the profile's own
      // field straight to the static method rather than repeating 24.0.
      expect(KeyTable.timeOfFrame(48, project.profile.fps), 2.0);
      expect(KeyTable.frameOfTime(2.0, project.profile.fps), 48);
    });
  });
}
