/// A layer that adds to the base instead of replacing it — `gfx-10n`.
///
/// **What an overriding layer cannot do.** `animation_layer_test.dart` covers
/// the layer that takes a joint: an upper body reloads while the legs walk, and
/// the arms are the layer's alone for as long as it lasts. That is right for a
/// clip authored as a whole performance and wrong for one authored as a
/// *difference* — a breath, a recoil, a lean. An overriding breath stops the
/// walk for as long as the breath lasts, because the layer's chest is the whole
/// chest and knows nothing about walking.
///
/// The reference frame is the whole of why this was override-only, and it is
/// what these fixtures are mostly about. A delta needs something to measure
/// from; glTF has nowhere to say which frame is at rest, so the clip carries
/// the time and the player samples it. A clip that names none is not additive,
/// and every clip read from a file names none — which is the second claim here,
/// and the one that says no existing character moved.
///
/// The mutations these catch, in order: measuring the delta from frame zero
/// when the clip names no reference (every existing layer would start
/// subtracting its own first frame); applying a rotation delta as `delta·base`
/// rather than `base·delta`; scaling a rotation delta component-wise instead of
/// slerping it from no rotation; adding a scale as a difference rather than as
/// a ratio.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_core/src/engine/animation/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

final class _Recorder implements AnimationTarget {
  final Vector3 position = Vector3.zero();
  final Quaternion rotation = Quaternion.identity();
  final Vector3 scale = Vector3.all(1.0);

  @override
  void setPosition(double x, double y, double z) => position.setValues(x, y, z);

  @override
  void setRotation(Quaternion value) => rotation.setFrom(value);

  @override
  void setScale(double x, double y, double z) => scale.setValues(x, y, z);
}

/// Two keys on [node], [from] at zero and [to] at [end].
AnimationTrack _track(
  int node,
  AnimationPath path,
  List<double> from,
  List<double> to, {
  double end = 1.0,
}) => AnimationTrack(
  nodeIndex: node,
  path: path,
  interpolation: AnimationInterpolation.linear,
  componentCount: from.length,
  times: Float32List.fromList(<double>[0.0, end]),
  values: Float32List.fromList(<double>[...from, ...to]),
);

List<double> _xyzw(Quaternion q) => <double>[q.x, q.y, q.z, q.w];

({AnimationPlayer player, _Recorder node}) _rig(List<AnimationClip> clips) {
  final node = _Recorder();
  return (
    player: AnimationPlayer(clips: clips, targets: <AnimationTarget?>[node]),
    node: node,
  );
}

/// A walk: the joint slides a metre along X over a second.
AnimationClip get _walk => AnimationClip(
  name: 'walk',
  tracks: <AnimationTrack>[
    _track(0, AnimationPath.translation, <double>[0, 0, 0], <double>[1, 0, 0]),
  ],
);

/// A breath authored as a difference: at rest at its start, a chest lifted
/// 0.2 up at the half second, back at rest at the end.
///
/// [reference] is what makes it additive; the same tracks without it are an
/// ordinary clip, which is the second group below.
AnimationClip _breath({double? reference}) => AnimationClip(
  name: 'breath',
  referenceTime: reference,
  tracks: <AnimationTrack>[
    AnimationTrack(
      nodeIndex: 0,
      path: AnimationPath.translation,
      interpolation: AnimationInterpolation.linear,
      componentCount: 3,
      times: Float32List.fromList(<double>[0.0, 0.5, 1.0]),
      values: Float32List.fromList(<double>[0, 0, 0, 0, 0.2, 0, 0, 0, 0]),
    ),
  ],
);

/// The player half a second in, with one layer over the base.
///
/// Half a second puts the walk mid-stride and the breath at its peak, which is
/// the moment every claim below is about. `update` advances the layer itself,
/// so there is no second playhead to keep in step.
_Recorder _posedAt(
  List<AnimationClip> clips,
  AnimationLayer layer, {
  double seconds = 0.5,
}) {
  final rig = _rig(clips);
  rig.player.play(0);
  rig.player.addLayer(layer);
  rig.player.update(seconds);
  return rig.node;
}

void main() {
  group('breathing over walking', () {
    test('keeps the walk and gains the breath', () {
      // The row's own sentence. The base is halfway through its stride, so the
      // joint is half a metre along X; the breath is at its peak. Additive
      // means both: 0.5 along X *and* 0.2 up.
      final node = _posedAt(<AnimationClip>[
        _walk,
        _breath(reference: 0.0),
      ], AnimationLayer(clip: 1, blend: AnimationBlend.additive));

      expect(node.position.x, closeTo(0.5, 1e-6));
      expect(node.position.y, closeTo(0.2, 1e-6));
    });

    test('an overriding layer loses the walk, which is the point', () {
      // The same clips with the blend changed. An override is not a worse
      // additive — it is a different thing, and this is what makes the
      // difference visible rather than asserted: the joint stops moving along
      // X for as long as the breath lasts.
      final node = _posedAt(<AnimationClip>[
        _walk,
        _breath(reference: 0.0),
      ], AnimationLayer(clip: 1));

      expect(node.position.x, closeTo(0.0, 1e-6));
      expect(node.position.y, closeTo(0.2, 1e-6));
    });

    test('half a weight is half the breath and all of the walk', () {
      final node = _posedAt(<AnimationClip>[
        _walk,
        _breath(reference: 0.0),
      ], AnimationLayer(clip: 1, blend: AnimationBlend.additive, weight: 0.5));

      // The stride is untouched by the layer's weight: fading a breath fades
      // the breath, not the walk under it.
      expect(node.position.x, closeTo(0.5, 1e-6));
      expect(node.position.y, closeTo(0.1, 1e-6));
    });

    test('a layer sitting on its own reference frame is invisible', () {
      // The property the whole arithmetic is built around: at the reference
      // time the delta is nothing, so a full-weight additive layer leaves the
      // base exactly as it found it. That is what makes an additive layer safe
      // to hold at weight one for ever — the breath at the top of its arc and
      // the breath at rest are the same walk.
      final node = _posedAt(<AnimationClip>[
        _walk,
        _breath(reference: 0.5),
      ], AnimationLayer(clip: 1, blend: AnimationBlend.additive));

      expect(node.position.x, closeTo(0.5, 1e-6));
      expect(node.position.y, closeTo(0.0, 1e-6));
    });
  });

  group('zero changes to existing clips', () {
    test('a clip read from a file names no reference time', () {
      // Nothing decodes this field: it is set by a caller who authored an
      // additive clip and knows which of its frames is at rest. A clip built
      // from tracks alone — every clip a glTF produces — is not additive, and
      // that is the guarantee that no existing character moved.
      expect(_breath().referenceTime, isNull);
      expect(_walk.referenceTime, isNull);
    });

    test('an additive layer over such a clip overrides', () {
      // Not a silent nothing, and not a guess at frame zero. A caller who asks
      // for an additive blend over a clip with no reference gets the clip —
      // and gets it as an override, which is what this asserts: the walk is
      // gone, exactly as in the override fixture above.
      final node = _posedAt(<AnimationClip>[
        _walk,
        _breath(),
      ], AnimationLayer(clip: 1, blend: AnimationBlend.additive));

      expect(node.position.x, closeTo(0.0, 1e-6));
      expect(node.position.y, closeTo(0.2, 1e-6));
    });
  });

  group('the paths that are not a subtraction', () {
    /// A recoil of a quarter turn about X, authored on a joint at rest and
    /// fully reached half a second in — a `once` layer then holds it there.
    AnimationClip recoilClip(Quaternion recoil) => AnimationClip(
      name: 'recoil',
      referenceTime: 0.0,
      tracks: <AnimationTrack>[
        _track(
          0,
          AnimationPath.rotation,
          _xyzw(Quaternion.identity()),
          _xyzw(recoil),
          end: 0.5,
        ),
      ],
    );

    AnimationClip heldRotation(Quaternion value) => AnimationClip(
      name: 'held',
      tracks: <AnimationTrack>[
        _track(0, AnimationPath.rotation, _xyzw(value), _xyzw(value)),
      ],
    );

    test('a rotation delta turns the base further, in the base\'s own frame', () {
      // A recoil authored on a T-pose, played over a base already turned a
      // quarter about Y. `base · delta` applies the recoil in the joint's own
      // frame, which is what the animator who authored it meant; `delta · base`
      // would apply it in the world's and tip the character sideways.
      final base = Quaternion.axisAngle(Vector3(0, 1, 0), math.pi / 2);
      final recoil = Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2);
      final node = _posedAt(
        <AnimationClip>[heldRotation(base), recoilClip(recoil)],
        AnimationLayer(
          clip: 1,
          blend: AnimationBlend.additive,
          wrap: AnimationWrap.once,
        ),
      );

      // A quaternion and its negation are the same rotation, so compare what
      // the rotation *does* rather than its four numbers — and along two axes,
      // because one probe cannot tell a turn from its mirror.
      final expected = (base * recoil)..normalize();
      for (final probe in <Vector3>[Vector3(0, 0, 1), Vector3(1, 0, 0)]) {
        final got = node.rotation.rotated(probe);
        final want = expected.rotated(probe);
        expect(got.x, closeTo(want.x, 1e-5));
        expect(got.y, closeTo(want.y, 1e-5));
        expect(got.z, closeTo(want.z, 1e-5));
      }
    });

    test('a quarter of a rotation delta is a quarter of the turn', () {
      // A quarter rather than a half, and the reason is worth stating: a
      // component-wise scale renormalised is *exactly* the slerp at a half, by
      // symmetry, so the obvious fixture would pass against the mutation it
      // exists to catch. At a quarter the two part company — 22.50° against
      // the 21.60° a component scale gives, measured.
      final recoil = Quaternion.axisAngle(Vector3(1, 0, 0), math.pi / 2);
      final node = _posedAt(
        <AnimationClip>[
          heldRotation(Quaternion.identity()),
          recoilClip(recoil),
        ],
        AnimationLayer(
          clip: 1,
          blend: AnimationBlend.additive,
          weight: 0.25,
          wrap: AnimationWrap.once,
        ),
      );

      expect(node.rotation.radians, closeTo(math.pi / 8, 1e-4));
    });

    test('a scale delta is a ratio, so it holds under a scaled base', () {
      // A swell authored on a chest at scale one, played over a base already
      // at two. A ratio swells it by the same proportion; a difference would
      // add half a unit to a chest twice the size and read as half the swell.
      final node = _posedAt(
        <AnimationClip>[
          AnimationClip(
            name: 'big',
            tracks: <AnimationTrack>[
              _track(
                0,
                AnimationPath.scale,
                <double>[2, 2, 2],
                <double>[2, 2, 2],
              ),
            ],
          ),
          AnimationClip(
            name: 'swell',
            referenceTime: 0.0,
            tracks: <AnimationTrack>[
              _track(
                0,
                AnimationPath.scale,
                <double>[1, 1, 1],
                <double>[1.5, 1.5, 1.5],
                end: 0.5,
              ),
            ],
          ),
        ],
        AnimationLayer(
          clip: 1,
          blend: AnimationBlend.additive,
          wrap: AnimationWrap.once,
        ),
      );

      expect(node.scale.x, closeTo(3.0, 1e-6));
    });
  });
}
