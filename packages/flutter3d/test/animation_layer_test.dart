/// A clip playing over part of a skeleton while the base plays over all of it.
///
/// **What a crossfade cannot do, and the reason this exists.**
/// `animation_blend_test.dart` covers the crossfade, which moves the whole
/// skeleton from one clip to another. A layer leaves the base playing and takes
/// the joints its mask names — a monster that flinches with its arms while its
/// legs keep walking, a soldier who reloads on the move.
///
/// The first thing here is not a layer at all. It is the assertion that a
/// player without one poses exactly as it did before layers existed: the
/// feature reorganised how `apply` writes a joint, folding the crossfade's
/// blend out of the per-path switch so a layer could sit on top of it, and a
/// reorganisation that moved every pose by a hair would have moved every golden
/// in the repository with it.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/animation/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

final class _Recorder implements AnimationTarget {
  final Vector3 position = Vector3.zero();
  final Quaternion rotation = Quaternion.identity();
  final Vector3 scale = Vector3.all(1.0);
  int writes = 0;

  @override
  void setPosition(double x, double y, double z) {
    writes++;
    position.setValues(x, y, z);
  }

  @override
  void setRotation(Quaternion value) {
    writes++;
    rotation.setFrom(value);
  }

  @override
  void setScale(double x, double y, double z) {
    writes++;
    scale.setValues(x, y, z);
  }
}

/// A clip holding [node] at a constant translation of [x] along X.
AnimationClip _still(String name, {required int node, required double x}) =>
    AnimationClip(
      name: name,
      tracks: <AnimationTrack>[
        AnimationTrack(
          nodeIndex: node,
          path: AnimationPath.translation,
          interpolation: AnimationInterpolation.linear,
          componentCount: 3,
          times: Float32List.fromList(<double>[0.0, 1.0]),
          values: Float32List.fromList(<double>[x, 0, 0, x, 0, 0]),
        ),
      ],
    );

/// A clip holding several nodes, each at its own constant translation.
AnimationClip _pose(String name, Map<int, double> byNode) => AnimationClip(
  name: name,
  tracks: <AnimationTrack>[
    for (final entry in byNode.entries)
      AnimationTrack(
        nodeIndex: entry.key,
        path: AnimationPath.translation,
        interpolation: AnimationInterpolation.linear,
        componentCount: 3,
        times: Float32List.fromList(<double>[0.0, 1.0]),
        values: Float32List.fromList(<double>[
          entry.value,
          0,
          0,
          entry.value,
          0,
          0,
        ]),
      ),
  ],
);

({AnimationPlayer player, List<_Recorder> nodes}) _rig(
  List<AnimationClip> clips, {
  int nodeCount = 4,
}) {
  final nodes = <_Recorder>[for (var i = 0; i < nodeCount; i++) _Recorder()];
  return (
    player: AnimationPlayer(
      clips: clips,
      targets: List<AnimationTarget?>.of(nodes),
    ),
    nodes: nodes,
  );
}

void main() {
  group('a player with no layers', () {
    test('poses exactly as it did before layers existed', () {
      // The regression this feature could most easily have been. `apply` used
      // to blend the crossfade inside the per-path switch and write there; it
      // now resolves one pose per joint and writes once, so that a layer has
      // something to write over. The arithmetic is the same arithmetic, and
      // this is what says so: a crossfade halfway between 0 and 10 is 5.
      final rig = _rig(<AnimationClip>[
        _still('a', node: 0, x: 0.0),
        _still('b', node: 0, x: 10.0),
      ]);
      rig.player
        ..play(0)
        ..crossFadeTo(1, duration: 0.2)
        ..update(0.1);

      expect(rig.player.fadeWeight, closeTo(0.5, 1e-6));
      expect(rig.nodes[0].position.x, closeTo(5.0, 1e-6));
    });
  });

  group('a layer', () {
    test('takes the joints its mask names and leaves the rest to the base', () {
      // The whole feature in one assertion: node 1 is masked and follows the
      // layer, node 2 is not and follows the base.
      final rig = _rig(<AnimationClip>[
        _pose('walk', <int, double>{1: 1.0, 2: 2.0}),
        _pose('wave', <int, double>{1: 9.0, 2: 9.0}),
      ]);
      rig.player.play(0);
      rig.player.playLayer(1, mask: AnimationMask(<int>[1]), fadeIn: 0.0);
      rig.player.update(0.0);

      expect(rig.nodes[1].position.x, closeTo(9.0, 1e-6), reason: 'masked');
      expect(rig.nodes[2].position.x, closeTo(2.0, 1e-6), reason: 'not masked');
    });

    test('at half weight is halfway between the two poses', () {
      // Mutation: ignore `effectiveWeight` and write the layer outright. The
      // node reads 9 instead of 5, so a fade-in becomes a pop and this catches
      // it.
      final rig = _rig(<AnimationClip>[
        _pose('walk', <int, double>{1: 1.0}),
        _pose('wave', <int, double>{1: 9.0}),
      ]);
      rig.player.play(0);
      rig.player.addLayer(
        AnimationLayer(clip: 1, mask: AnimationMask(<int>[1]), weight: 0.5),
      );
      rig.player.update(0.0);

      expect(rig.nodes[1].position.x, closeTo(5.0, 1e-6));
    });

    test('at nothing leaves the base untouched', () {
      final rig = _rig(<AnimationClip>[
        _pose('walk', <int, double>{1: 1.0}),
        _pose('wave', <int, double>{1: 9.0}),
      ]);
      rig.player.play(0);
      rig.player.addLayer(
        AnimationLayer(clip: 1, mask: AnimationMask(<int>[1]), weight: 0.0),
      );
      rig.player.update(0.0);

      expect(rig.nodes[1].position.x, closeTo(1.0, 1e-6));
    });

    test('writes a joint the base is silent about, at full value', () {
      // The documented rule, and the same one the crossfade already follows:
      // there is nothing to blend from, so the value is taken outright. An
      // `AnimationTarget` cannot be read — that is the boundary keeping the
      // scene graph out of the decoders — so the alternative would be blending
      // against a pose nobody can see.
      final rig = _rig(<AnimationClip>[
        _pose('walk', <int, double>{1: 1.0}),
        _pose('wave', <int, double>{3: 7.0}),
      ]);
      rig.player.play(0);
      rig.player.addLayer(
        AnimationLayer(clip: 1, mask: AnimationMask(<int>[3]), weight: 0.5),
      );
      rig.player.update(0.0);

      expect(rig.nodes[3].position.x, closeTo(7.0, 1e-6));
    });

    test('runs on its own clock, at its own speed', () {
      final rig = _rig(<AnimationClip>[
        _pose('walk', <int, double>{1: 1.0}),
        _pose('wave', <int, double>{1: 9.0}),
      ]);
      rig.player.play(0);
      final layer = rig.player.addLayer(
        AnimationLayer(clip: 1, wrap: AnimationWrap.loop, speed: 2.0),
      );
      rig.player.update(0.25);

      expect(layer.time, closeTo(0.5, 1e-6), reason: 'twice the base delta');
      expect(rig.player.time, closeTo(0.25, 1e-6));
    });

    test('the last of two over one joint is the one that lands', () {
      final rig = _rig(<AnimationClip>[
        _pose('walk', <int, double>{1: 1.0}),
        _pose('a', <int, double>{1: 4.0}),
        _pose('b', <int, double>{1: 8.0}),
      ]);
      rig.player.play(0);
      rig.player.addLayer(AnimationLayer(clip: 1));
      rig.player.addLayer(AnimationLayer(clip: 2));
      rig.player.update(0.0);

      expect(rig.nodes[1].position.x, closeTo(8.0, 1e-6));
    });

    test('keeps going while the base is paused', () {
      // A player holding a pose with a flinch over it should still finish the
      // flinch. Mutation: return early from `update` when the base is not
      // playing, and the layer freezes.
      final rig = _rig(<AnimationClip>[
        _pose('walk', <int, double>{1: 1.0}),
        _pose('wave', <int, double>{1: 9.0}),
      ]);
      rig.player
        ..play(0)
        ..pause();
      final layer = rig.player.addLayer(
        AnimationLayer(clip: 1, wrap: AnimationWrap.loop),
      );
      rig.player.update(0.25);

      expect(layer.time, closeTo(0.25, 1e-6));
    });

    test('a once clip stops at its end and says it is finished', () {
      final rig = _rig(<AnimationClip>[
        _pose('walk', <int, double>{1: 1.0}),
        _pose('wave', <int, double>{1: 9.0}),
      ]);
      rig.player.play(0);
      final layer = rig.player.playLayer(
        1,
        wrap: AnimationWrap.once,
        fadeIn: 0.0,
      );

      rig.player.update(0.5);
      expect(layer.isFinished, isFalse);

      rig.player.update(1.0);
      expect(layer.isFinished, isTrue);
      expect(layer.time, closeTo(1.0, 1e-6), reason: 'held on the last pose');
    });
  });

  group('the weight ramp', () {
    test('reaches its target exactly, and not before', () {
      final layer = AnimationLayer(clip: 0, weight: 0.0)
        ..fadeTo(1.0, seconds: 0.2);

      layer.advance(0.1, 1.0);
      expect(layer.weight, closeTo(0.5, 1e-6));

      layer.advance(0.1, 1.0);
      expect(layer.weight, closeTo(1.0, 1e-9), reason: 'exactly, not nearly');

      layer.advance(0.1, 1.0);
      expect(layer.weight, closeTo(1.0, 1e-9), reason: 'and stays');
    });

    test('a ramp to nothing is how a layer leaves', () {
      final layer = AnimationLayer(clip: 0)..fadeTo(0.0, seconds: 0.1);
      layer.advance(0.05, 1.0);
      expect(layer.weight, closeTo(0.5, 1e-6));
      layer.advance(0.05, 1.0);
      expect(layer.effectiveWeight, 0.0);
    });

    test('with no time at all is immediate', () {
      final layer = AnimationLayer(clip: 0, weight: 0.0)
        ..fadeTo(1.0, seconds: 0.0);
      expect(layer.weight, 1.0);
    });

    test('clamps what it is asked for', () {
      final layer = AnimationLayer(clip: 0)..fadeTo(4.0, seconds: 0.0);
      expect(layer.weight, 1.0);
      layer.fadeTo(-2.0, seconds: 0.0);
      expect(layer.weight, 0.0);
    });
  });

  group('a mask', () {
    test('covers what it names and nothing else', () {
      final mask = AnimationMask(<int>[2, 5]);
      expect(mask.covers(2), isTrue);
      expect(mask.covers(5), isTrue);
      expect(mask.covers(3), isFalse);
      expect(mask.length, 2);
    });

    test('everything covers everything and names nothing', () {
      expect(AnimationMask.everything.covers(0), isTrue);
      expect(AnimationMask.everything.covers(9999), isTrue);
      expect(AnimationMask.everything.isEmpty, isFalse);
    });

    test('an empty one stops a layer writing at all', () {
      // Which is what a misspelt joint name produces, and it is the safe
      // direction: a layer that does nothing rather than one that takes over
      // the skeleton.
      final rig = _rig(<AnimationClip>[
        _pose('walk', <int, double>{1: 1.0}),
        _pose('wave', <int, double>{1: 9.0}),
      ]);
      rig.player.play(0);
      rig.player.addLayer(
        AnimationLayer(clip: 1, mask: AnimationMask(const <int>[])),
      );
      rig.player.update(0.0);

      expect(rig.nodes[1].position.x, closeTo(1.0, 1e-6));
    });
  });

  group('the player', () {
    test('finds a layer by the clip it is playing', () {
      final rig = _rig(<AnimationClip>[_still('a', node: 0, x: 0.0)]);
      expect(rig.player.layerOf(0), isNull);
      final layer = rig.player.addLayer(AnimationLayer(clip: 0));
      expect(rig.player.layerOf(0), same(layer));
    });

    test('poses from layers alone when no base clip is selected', () {
      final rig = _rig(<AnimationClip>[
        _pose('wave', <int, double>{1: 6.0}),
      ]);
      rig.player.addLayer(AnimationLayer(clip: 0));
      rig.player.update(0.0);

      expect(rig.nodes[1].position.x, closeTo(6.0, 1e-6));
    });

    test('ignores a layer pointing at a clip that is not there', () {
      final rig = _rig(<AnimationClip>[
        _pose('walk', <int, double>{1: 1.0}),
      ]);
      rig.player.play(0);
      rig.player.addLayer(AnimationLayer(clip: 7));
      rig.player.update(0.1);

      expect(rig.nodes[1].position.x, closeTo(1.0, 1e-6));
    });
  });
}
