/// `SimulationCache`: baked simulation frames, as a value — `pro-sim-03`'s
/// own row.
///
///     dart test test/simulation_cache_test.dart
library;

import 'dart:typed_data';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

Float32List frameOf(int vertexCount, double fill) =>
    Float32List(vertexCount * 3)..fillRange(0, vertexCount * 3, fill);

void main() {
  group('SimulationCache', () {
    test('holds exactly the frames and vertexCount it was built with', () {
      final cache = SimulationCache(
        vertexCount: 400,
        frames: <Float32List>[
          for (var i = 0; i < 120; i++) frameOf(400, i.toDouble()),
        ],
      );

      // The row's own worked scale: 120 frames × 400 vertices.
      expect(cache.vertexCount, 400);
      expect(cache.frameCount, 120);
      expect(cache.frames, hasLength(120));
      expect(cache.frame(0).length, 400 * 3);
      expect(cache.frame(119)[0], 119.0);
      expect(cache.isEmpty, isFalse);
    });

    test('an empty cache is empty and has zero frames', () {
      final cache = SimulationCache(vertexCount: 10, frames: <Float32List>[]);
      expect(cache.isEmpty, isTrue);
      expect(cache.frameCount, 0);
    });

    test('frames is unmodifiable and detached from the list handed in', () {
      final source = <Float32List>[frameOf(2, 1)];
      final cache = SimulationCache(vertexCount: 2, frames: source);

      // Mutation: keep a live reference to `source` instead of copying it —
      // a caller who appends another frame to their own list afterwards
      // would silently grow a cache that already claimed to be finished.
      source.add(frameOf(2, 2));
      expect(cache.frameCount, 1);

      expect(() => cache.frames.add(frameOf(2, 3)), throwsUnsupportedError);
    });

    test('throws for a frame whose length does not match vertexCount * 3', () {
      expect(
        () => SimulationCache(
          vertexCount: 4,
          frames: <Float32List>[frameOf(3, 0)],
        ),
        throwsArgumentError,
      );
    });

    group('coverage', () {
      test('is the fraction of target frames actually baked', () {
        final cache = SimulationCache(
          vertexCount: 1,
          frames: <Float32List>[for (var i = 0; i < 50; i++) frameOf(1, 0)],
        );
        // Mutation: divide by frameCount instead of targetFrameCount, or
        // swap the numerator and denominator — either gives a strip that
        // reads 100% while a bake is only half done.
        expect(cache.coverage(120), closeTo(50 / 120, 1e-12));
      });

      test('is 1.0 once every target frame is baked, never past it', () {
        final cache = SimulationCache(
          vertexCount: 1,
          frames: <Float32List>[for (var i = 0; i < 120; i++) frameOf(1, 0)],
        );
        expect(cache.coverage(120), 1.0);
        // A cache holding more frames than the target it is compared
        // against still reads as fully covered, not over 1.0.
        expect(cache.coverage(50), 1.0);
      });

      test('is 0.0 for an empty cache against any positive target', () {
        final cache = SimulationCache(vertexCount: 1, frames: <Float32List>[]);
        expect(cache.coverage(10), 0.0);
      });
    });

    group('JSON', () {
      test('round-trips vertexCount and every frame\'s own values', () {
        final cache = SimulationCache(
          vertexCount: 3,
          frames: <Float32List>[
            Float32List.fromList(<double>[1, 2, 3, 4, 5, 6, 7, 8, 9]),
            Float32List.fromList(<double>[9, 8, 7, 6, 5, 4, 3, 2, 1]),
          ],
        );

        final restored = SimulationCache.fromJson(cache.toJson());

        expect(restored, isNotNull);
        expect(restored!.vertexCount, 3);
        expect(restored.frameCount, 2);
        for (var f = 0; f < 2; f++) {
          expect(restored.frame(f), cache.frame(f));
        }
      });

      test('fromJson is null for a missing field', () {
        expect(
          SimulationCache.fromJson(<String, Object?>{'vertexCount': 3}),
          isNull,
        );
      });

      test('fromJson is null for a frame that is not a string', () {
        expect(
          SimulationCache.fromJson(<String, Object?>{
            'vertexCount': 1,
            'frames': <Object?>[42],
          }),
          isNull,
        );
      });

      test(
        'fromJson is null for a frame whose byte length is not a multiple of 4',
        () {
          expect(
            SimulationCache.fromJson(<String, Object?>{
              'vertexCount': 1,
              // Base64 for a single odd byte — five bytes decoded, not a
              // multiple of 4.
              'frames': <Object?>['AQIDBAU='],
            }),
            isNull,
          );
        },
      );

      test(
        'fromJson is null for a frame whose length does not match vertexCount',
        () {
          final mismatched = SimulationCache(
            vertexCount: 2,
            frames: <Float32List>[frameOf(2, 0)],
          ).toJson();
          // vertexCount says 5, but the one frame is still 2 vertices long.
          mismatched['vertexCount'] = 5;
          expect(SimulationCache.fromJson(mismatched), isNull);
        },
      );
    });
  });
}
