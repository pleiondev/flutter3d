import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter3d/src/engine/animation/animation.dart';
import 'package:flutter3d/src/engine/scene/scene_graph.dart';

AnimationTrack translationTrack({
  required List<double> times,
  required List<double> values,
  AnimationInterpolation interpolation = AnimationInterpolation.linear,
  int nodeIndex = 0,
}) =>
    AnimationTrack(
      nodeIndex: nodeIndex,
      path: AnimationPath.translation,
      interpolation: interpolation,
      times: Float32List.fromList(times),
      values: Float32List.fromList(values),
      componentCount: 3,
    );

/// Samples a track into a fresh list, so assertions read as values not buffers.
List<double> sampleAt(AnimationTrack track, double time) {
  final out = Float32List(track.componentCount);
  track.sample(time, out);
  return out.toList();
}

void main() {
  group('track validation', () {
    test('a track with no keyframes is refused', () {
      expect(
        () => translationTrack(times: <double>[], values: <double>[]),
        throwsArgumentError,
      );
    });

    test('a value count that does not match the keys is refused', () {
      expect(
        () => translationTrack(times: <double>[0, 1], values: <double>[0, 0, 0]),
        throwsArgumentError,
      );
    });

    test('cubic keys need three values each', () {
      // Two keys x 3 components x (in, value, out) = 18 values.
      expect(
        () => translationTrack(
          times: <double>[0, 1],
          values: List<double>.filled(6, 0.0),
          interpolation: AnimationInterpolation.cubicSpline,
        ),
        throwsArgumentError,
      );
      expect(
        () => translationTrack(
          times: <double>[0, 1],
          values: List<double>.filled(18, 0.0),
          interpolation: AnimationInterpolation.cubicSpline,
        ),
        returnsNormally,
      );
    });
  });

  group('sampling boundaries', () {
    final track = translationTrack(
      times: <double>[1.0, 2.0],
      values: <double>[0, 0, 0, 10, 0, 0],
    );

    test('before the first key holds the first value', () {
      expect(sampleAt(track, 0.0), <double>[0, 0, 0]);
      expect(sampleAt(track, -100.0), <double>[0, 0, 0]);
    });

    test('after the last key holds the last value', () {
      expect(sampleAt(track, 2.0), <double>[10, 0, 0]);
      expect(sampleAt(track, 99.0), <double>[10, 0, 0]);
    });

    test('exactly on a key returns that key', () {
      expect(sampleAt(track, 1.0), <double>[0, 0, 0]);
    });

    test('a single-key track is constant', () {
      final constant =
          translationTrack(times: <double>[5.0], values: <double>[1, 2, 3]);
      expect(sampleAt(constant, 0.0), <double>[1, 2, 3]);
      expect(sampleAt(constant, 100.0), <double>[1, 2, 3]);
    });

    test('two keys at the same time behave as a step', () {
      final coincident = translationTrack(
        times: <double>[0.0, 0.0, 1.0],
        values: <double>[0, 0, 0, 5, 0, 0, 5, 0, 0],
      );
      final sample = sampleAt(coincident, 0.0);
      expect(sample[0].isNaN, isFalse);
    });
  });

  group('interpolation', () {
    test('step holds the previous key until the next one', () {
      final track = translationTrack(
        times: <double>[0.0, 1.0],
        values: <double>[0, 0, 0, 10, 0, 0],
        interpolation: AnimationInterpolation.step,
      );
      expect(sampleAt(track, 0.0)[0], 0.0);
      expect(sampleAt(track, 0.99)[0], 0.0);
      expect(sampleAt(track, 1.0)[0], 10.0);
    });

    test('linear blends proportionally', () {
      final track = translationTrack(
        times: <double>[0.0, 2.0],
        values: <double>[0, 0, 0, 10, -4, 0],
      );
      final mid = sampleAt(track, 1.0);
      expect(mid[0], closeTo(5.0, 1e-6));
      expect(mid[1], closeTo(-2.0, 1e-6));
    });

    test('cubic spline honours the authored tangents', () {
      // Flat tangents at both ends: an ease in and out, so the midpoint is the
      // average but the quarter point is behind a straight line.
      final track = translationTrack(
        times: <double>[0.0, 1.0],
        values: <double>[
          0, 0, 0, // in tangent, key 0
          0, 0, 0, // value, key 0
          0, 0, 0, // out tangent, key 0
          0, 0, 0, // in tangent, key 1
          10, 0, 0, // value, key 1
          0, 0, 0, // out tangent, key 1
        ],
        interpolation: AnimationInterpolation.cubicSpline,
      );

      expect(sampleAt(track, 0.0)[0], closeTo(0.0, 1e-6));
      expect(sampleAt(track, 1.0)[0], closeTo(10.0, 1e-6));
      expect(sampleAt(track, 0.5)[0], closeTo(5.0, 1e-6));
      // Hermite with zero tangents: 2t^3 - 3t^2 + ... gives 1.5625 at t = 0.25.
      expect(sampleAt(track, 0.25)[0], closeTo(1.5625, 1e-5));
      expect(sampleAt(track, 0.25)[0], lessThan(2.5));
    });

    test('cubic tangents scale with the key interval', () {
      // The same tangents over a longer interval must move the curve further:
      // glTF authors tangents per second, and dropping the interval factor
      // makes an animation correct at one key spacing and wrong at another.
      List<double> valuesWithTangent(double tangent) => <double>[
            0, 0, 0,
            0, 0, 0,
            tangent, 0, 0,
            0, 0, 0,
            0, 0, 0,
            0, 0, 0,
          ];

      final short = translationTrack(
        times: <double>[0.0, 1.0],
        values: valuesWithTangent(4.0),
        interpolation: AnimationInterpolation.cubicSpline,
      );
      final long = translationTrack(
        times: <double>[0.0, 2.0],
        values: valuesWithTangent(4.0),
        interpolation: AnimationInterpolation.cubicSpline,
      );

      // Same fraction through each interval, twice the span.
      expect(
        sampleAt(long, 0.5)[0],
        closeTo(sampleAt(short, 0.25)[0] * 2.0, 1e-5),
      );
    });

    test('rotations slerp rather than blending component-wise', () {
      // 0 and 180 degrees about Y: a component-wise blend collapses to a
      // zero-length quaternion at the midpoint, slerp gives 90 degrees.
      final track = AnimationTrack(
        nodeIndex: 0,
        path: AnimationPath.rotation,
        interpolation: AnimationInterpolation.linear,
        times: Float32List.fromList(<double>[0.0, 1.0]),
        values: Float32List.fromList(<double>[
          0, 0, 0, 1, // identity
          0, 1, 0, 0, // 180 degrees about Y
        ]),
        componentCount: 4,
      );

      final out = Float32List(4);
      track.sample(0.5, out);

      final q = Quaternion(out[0], out[1], out[2], out[3]);
      expect(q.length, closeTo(1.0, 1e-5));

      final rotated = q.rotated(Vector3(0.0, 0.0, 1.0));
      // 90 degrees about Y takes +Z to +X.
      expect(rotated.x.abs(), closeTo(1.0, 1e-4));
      expect(rotated.z.abs(), closeTo(0.0, 1e-4));
    });

    test('slerp takes the short way round', () {
      // The second key is the same rotation written with the opposite sign;
      // without the dot-product flip the blend would travel the long way and
      // pass through the antipode.
      final track = AnimationTrack(
        nodeIndex: 0,
        path: AnimationPath.rotation,
        interpolation: AnimationInterpolation.linear,
        times: Float32List.fromList(<double>[0.0, 1.0]),
        values: Float32List.fromList(<double>[
          0, 0, 0, 1,
          0, 0, 0, -1,
        ]),
        componentCount: 4,
      );

      final out = Float32List(4);
      track.sample(0.5, out);
      final q = Quaternion(out[0], out[1], out[2], out[3]);
      final rotated = q.rotated(Vector3(1.0, 2.0, 3.0));
      expect(rotated.x, closeTo(1.0, 1e-4));
      expect(rotated.y, closeTo(2.0, 1e-4));
      expect(rotated.z, closeTo(3.0, 1e-4));
    });

    test('cubic rotations are renormalized', () {
      final track = AnimationTrack(
        nodeIndex: 0,
        path: AnimationPath.rotation,
        interpolation: AnimationInterpolation.cubicSpline,
        times: Float32List.fromList(<double>[0.0, 1.0]),
        values: Float32List.fromList(<double>[
          0, 0, 0, 0, // in tangent
          0, 0, 0, 1, // value
          0, 4, 0, 0, // out tangent, deliberately large
          0, 0, 0, 0,
          0, math.sin(0.5), 0, math.cos(0.5),
          0, 0, 0, 0,
        ]),
        componentCount: 4,
      );

      final out = Float32List(4);
      track.sample(0.5, out);
      final length = math.sqrt(
        out[0] * out[0] + out[1] * out[1] + out[2] * out[2] + out[3] * out[3],
      );
      expect(length, closeTo(1.0, 1e-5));
    });
  });

  group('clip', () {
    test('duration is the latest key across all tracks', () {
      final clip = AnimationClip(
        name: 'mixed',
        tracks: <AnimationTrack>[
          translationTrack(times: <double>[0, 1], values: List.filled(6, 0.0)),
          translationTrack(
            nodeIndex: 1,
            times: <double>[0, 4],
            values: List.filled(6, 0.0),
          ),
        ],
      );
      expect(clip.duration, 4.0);
    });

    test('an empty clip has zero duration', () {
      expect(AnimationClip(tracks: const <AnimationTrack>[]).duration, 0.0);
    });
  });

  group('player', () {
    ({AnimationPlayer player, SceneNode node}) build({
      AnimationClip? clip,
    }) {
      final scene = Scene();
      final node = scene.add(SceneNode(name: 'target'));
      return (
        player: AnimationPlayer(
          clips: <AnimationClip>[
            clip ??
                AnimationClip(
                  name: 'slide',
                  tracks: <AnimationTrack>[
                    translationTrack(
                      times: <double>[0.0, 1.0],
                      values: <double>[0, 0, 0, 10, 0, 0],
                    ),
                  ],
                ),
          ],
          targets: <SceneNode?>[node],
        ),
        node: node,
      );
    }

    test('playing applies the first pose immediately', () {
      final (:player, :node) = build();
      node.setPosition(99.0, 99.0, 99.0);
      player.play();
      expect(node.readPosition().x, 0.0);
    });

    test('update advances the pose', () {
      final (:player, :node) = build();
      player.play();
      player.update(0.5);
      expect(node.readPosition().x, closeTo(5.0, 1e-5));
    });

    test('pause freezes the pose and resume continues from it', () {
      final (:player, :node) = build();
      player.play();
      player.update(0.25);
      player.pause();
      player.update(10.0);
      expect(node.readPosition().x, closeTo(2.5, 1e-5));

      player.play();
      player.update(0.25);
      expect(node.readPosition().x, closeTo(5.0, 1e-5));
    });

    test('seek clamps to the clip', () {
      final (:player, :node) = build();
      player.play();
      player.seek(99.0);
      expect(player.time, 1.0);
      expect(node.readPosition().x, closeTo(10.0, 1e-5));

      player.seek(-5.0);
      expect(player.time, 0.0);
    });

    test('loop wraps around instead of stopping', () {
      final (:player, :node) = build();
      player.wrap = AnimationWrap.loop;
      player.play();
      player.update(1.25);
      expect(player.isPlaying, isTrue);
      expect(player.time, closeTo(0.25, 1e-6));
      expect(node.readPosition().x, closeTo(2.5, 1e-5));
    });

    test('a single huge step wraps once, not many times', () {
      final (:player, :node) = build();
      player.wrap = AnimationWrap.loop;
      player.play();
      player.update(100.5);
      expect(player.time, closeTo(0.5, 1e-4));
    });

    test('once stops at the end and holds the last pose', () {
      final (:player, :node) = build();
      player.wrap = AnimationWrap.once;
      player.play();
      player.update(5.0);
      expect(player.isPlaying, isFalse);
      expect(player.time, 1.0);
      expect(node.readPosition().x, closeTo(10.0, 1e-5));
    });

    test('ping-pong reverses at the end', () {
      final (:player, :node) = build();
      player.wrap = AnimationWrap.pingPong;
      player.play();
      player.update(1.5);
      // Half a second past the end means half a second back into the clip.
      expect(player.time, closeTo(0.5, 1e-5));
      player.update(0.25);
      expect(player.time, closeTo(0.25, 1e-5));
    });

    test('negative speed runs the clip backwards', () {
      final (:player, :node) = build();
      player.wrap = AnimationWrap.once;
      player.play();
      player.seek(1.0);
      player.speed = -1.0;
      player.update(0.5);
      expect(player.time, closeTo(0.5, 1e-5));
      expect(node.readPosition().x, closeTo(5.0, 1e-5));
    });

    test('a clip missing a track leaves that property alone', () {
      // Only translation is animated, so a rotation set by the caller survives.
      final (:player, :node) = build();
      node.setRotationYawPitchRoll(0.5, 0.0, 0.0);
      final before = node.readRotation();

      player.play();
      player.update(0.5);

      final after = node.readRotation();
      expect(after.x, closeTo(before.x, 1e-6));
      expect(after.y, closeTo(before.y, 1e-6));
      expect(after.z, closeTo(before.z, 1e-6));
      expect(after.w, closeTo(before.w, 1e-6));
    });

    test('a track pointing past the target list is skipped, not fatal', () {
      final scene = Scene();
      final node = scene.add(SceneNode());
      final player = AnimationPlayer(
        clips: <AnimationClip>[
          AnimationClip(
            tracks: <AnimationTrack>[
              translationTrack(
                nodeIndex: 7,
                times: <double>[0.0, 1.0],
                values: <double>[0, 0, 0, 10, 0, 0],
              ),
            ],
          ),
        ],
        targets: <SceneNode?>[node],
      );

      expect(() => player.play(), returnsNormally);
      expect(node.readPosition().x, 0.0);
    });

    test('an animated parent carries its child', () {
      final scene = Scene();
      final parent = scene.add(SceneNode(name: 'parent'));
      final child = SceneNode(name: 'child')..setPosition(0.0, 2.0, 0.0);
      parent.add(child);

      final player = AnimationPlayer(
        clips: <AnimationClip>[
          AnimationClip(
            tracks: <AnimationTrack>[
              translationTrack(
                times: <double>[0.0, 1.0],
                values: <double>[0, 0, 0, 10, 0, 0],
              ),
            ],
          ),
        ],
        targets: <SceneNode?>[parent, child],
      );

      // Not the default loop: at exactly the clip length a looping player is
      // back at time zero, which would make this assert the start pose.
      player.wrap = AnimationWrap.once;
      player.play();
      player.update(1.0);

      // No update pass was run: the version counters make the child's world
      // matrix current the moment it is read.
      final world = child.readWorldPosition();
      expect(world.x, closeTo(10.0, 1e-5));
      expect(world.y, closeTo(2.0, 1e-5));
    });

    test('playNamed finds a clip and reports when it cannot', () {
      final scene = Scene();
      final node = scene.add(SceneNode());
      final player = AnimationPlayer(
        clips: <AnimationClip>[
          AnimationClip(name: 'a', tracks: <AnimationTrack>[
            translationTrack(times: <double>[0], values: <double>[0, 0, 0]),
          ]),
          AnimationClip(name: 'b', tracks: <AnimationTrack>[
            translationTrack(times: <double>[0], values: <double>[1, 0, 0]),
          ]),
        ],
        targets: <SceneNode?>[node],
      );

      expect(player.playNamed('b'), isTrue);
      expect(player.clipIndex, 1);
      expect(player.playNamed('nope'), isFalse);
      expect(player.clipIndex, 1);
      expect(player.clipNames, <String>['a', 'b']);
    });

    test('a player with no clips does nothing rather than throwing', () {
      final player =
          AnimationPlayer(clips: const <AnimationClip>[], targets: const []);
      expect(player.hasClips, isFalse);
      expect(() => player.play(), returnsNormally);
      expect(() => player.update(1.0), returnsNormally);
      expect(player.clip, isNull);
    });

    test('an out-of-range clip index is refused', () {
      final (:player, :node) = build();
      expect(() => player.play(5), throwsRangeError);
    });
  });
}
