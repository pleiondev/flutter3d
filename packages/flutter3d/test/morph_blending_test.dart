/// Two clips meeting over one face: the crossfade mixes weights, a layer adds
/// them.
///
/// **The two are different questions and this file is the answer to both.**
/// Fading from one clip to another is a transition between two whole
/// performances — halfway through it, halfway between the two expressions, the
/// same straight line a translation takes. A layer is not a transition: it is a
/// second thing happening at once, and a blink over a line of speech wants the
/// blink *on top of* the speech rather than instead of half of it.
///
/// Weights used to take neither: `_applyWeights` sampled the base clip and
/// wrote it straight to the sink, and it said so in a comment rather than
/// pretending otherwise. This is that comment cashed in.
library;

import 'dart:typed_data';

import 'package:flutter3d/src/engine/animation/animation.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Sink implements MorphSink {
  List<double> last = const <double>[];

  @override
  void setWeights(List<double> values) => last = List<double>.of(values);
}

/// A clip holding [node]'s weights at [to] for its whole length.
AnimationClip _holding(String name, int node, List<double> to) => AnimationClip(
  name: name,
  tracks: <AnimationTrack>[
    AnimationTrack(
      nodeIndex: node,
      path: AnimationPath.weights,
      interpolation: AnimationInterpolation.linear,
      componentCount: to.length,
      times: Float32List.fromList(<double>[0.0, 1.0]),
      values: Float32List.fromList(<double>[...to, ...to]),
    ),
  ],
);

/// A clip that moves a node and says nothing about its weights.
AnimationClip _moving(String name, int node) => AnimationClip(
  name: name,
  tracks: <AnimationTrack>[
    AnimationTrack(
      nodeIndex: node,
      path: AnimationPath.translation,
      interpolation: AnimationInterpolation.linear,
      componentCount: 3,
      times: Float32List.fromList(<double>[0.0, 1.0]),
      values: Float32List.fromList(<double>[0, 0, 0, 1, 0, 0]),
    ),
  ],
);

AnimationPlayer _player(List<AnimationClip> clips, _Sink sink) =>
    AnimationPlayer(
      clips: clips,
      targets: <AnimationTarget?>[null],
      morphs: <MorphSink?>[sink],
    );

void main() {
  group('a crossfade', () {
    test('mixes the weights the way it mixes a pose', () {
      // Halfway through a fade from all-of-the-first to all-of-the-second, the
      // face is halfway between them. Mutation: leave `_applyWeights` sampling
      // the incoming clip alone and the first assertion reads 0.0 rather than
      // 0.5 — the expression switches at the start of the fade instead of
      // arriving over it.
      final sink = _Sink();
      final player = _player(<AnimationClip>[
        _holding('angry', 0, <double>[1.0, 0.0]),
        _holding('sad', 0, <double>[0.0, 1.0]),
      ], sink);

      player.play(0);
      player.seek(0.0);
      expect(sink.last, <double>[1.0, 0.0]);

      player.crossFadeTo(1, duration: 1.0);
      player.update(0.5);
      expect(sink.last[0], closeTo(0.5, 1e-6));
      expect(sink.last[1], closeTo(0.5, 1e-6));

      player.update(0.5);
      expect(sink.last[0], closeTo(0.0, 1e-6));
      expect(sink.last[1], closeTo(1.0, 1e-6));
    });

    test('leaves a shape the outgoing clip never mentioned alone', () {
      // The incoming clip drives two shapes and the outgoing one drove two as
      // well, but a fade from a clip that says nothing about this node has
      // nothing to blend from — the incoming value arrives outright, which is
      // the rule a joint already follows.
      final sink = _Sink();
      final player = _player(<AnimationClip>[
        _holding('silent', 1, <double>[1.0]),
        _holding('angry', 0, <double>[1.0]),
      ], sink);

      player.play(0);
      player.crossFadeTo(1, duration: 1.0);
      player.update(0.5);

      expect(sink.last, <double>[1.0]);
    });
  });

  group('a layer', () {
    test('adds its expression on top of the base', () {
      // A wince over a shout. Mutation: blend instead of add — the base's 0.6
      // drops to 0.3 at half weight, and a layer that was meant to add a
      // little takes most of the face away instead.
      final sink = _Sink();
      final player = _player(<AnimationClip>[
        _holding('shout', 0, <double>[0.6, 0.0]),
        _holding('wince', 0, <double>[0.0, 0.5]),
      ], sink);

      player.play(0);
      player.addLayer(AnimationLayer(clip: 1));
      player.seek(0.0);

      expect(sink.last[0], closeTo(0.6, 1e-6), reason: 'the base is untouched');
      expect(sink.last[1], closeTo(0.5, 1e-6), reason: 'the layer is added');
    });

    test('is scaled by its own weight, so fading it in fades the shape', () {
      final sink = _Sink();
      final player = _player(<AnimationClip>[
        _holding('rest', 0, <double>[0.0]),
        _holding('blink', 0, <double>[1.0]),
      ], sink);

      player.play(0);
      player.addLayer(AnimationLayer(clip: 1, weight: 0.25));
      player.seek(0.0);

      expect(sink.last.single, closeTo(0.25, 1e-6));
    });

    test('stops at one however many layers ask for the same shape', () {
      // Two layers each asking for most of an expression reach it rather than
      // overshoot it. Mutation: drop the ceiling and this reads 1.4, which is
      // a face pushed past the shape its author sculpted.
      final sink = _Sink();
      final player = _player(<AnimationClip>[
        _holding('rest', 0, <double>[0.0]),
        _holding('a', 0, <double>[0.7]),
        _holding('b', 0, <double>[0.7]),
      ], sink);

      player.play(0);
      player
        ..addLayer(AnimationLayer(clip: 1))
        ..addLayer(AnimationLayer(clip: 2));
      player.seek(0.0);

      expect(sink.last.single, 1.0);
    });

    test('does not bound a base clip that asks for more on its own', () {
      // glTF allows a weight past one and this engine reads files faithfully.
      // The ceiling belongs to the *sum* a layer makes, so a file left alone
      // gets what it asked for.
      final sink = _Sink();
      final player = _player(<AnimationClip>[
        _holding('overdriven', 0, <double>[1.4]),
      ], sink);

      player.play(0);
      player.seek(0.0);

      expect(sink.last.single, closeTo(1.4, 1e-6));
    });

    test('reaches a node the base clip says nothing about', () {
      // The case that needed a pass of its own: the base moves a node and
      // never mentions its weights, so nothing in the main loop would look for
      // a weights track at all. Mutation: delete the
      // `_applyLayerWeightsWhereBaseIsSilent` call and the sink is never
      // written, so a face driven only by a layer stays at rest.
      final sink = _Sink();
      final player = _player(<AnimationClip>[
        _moving('walk', 0),
        _holding('smile', 0, <double>[0.8]),
      ], sink);

      player.play(0);
      player.addLayer(AnimationLayer(clip: 1));
      player.seek(0.0);

      expect(sink.last.single, closeTo(0.8, 1e-6));
    });

    test('is added once when two layers name the same node', () {
      // The reason the base-is-silent pass keeps a set of the keys it has
      // done. Written as `_applyLayersWhereBaseIsSilent` is — a write per
      // layer — the last layer would win and the first would vanish; written
      // without the set, the sum would be applied once per layer and double.
      final sink = _Sink();
      final player = _player(<AnimationClip>[
        _moving('walk', 0),
        _holding('a', 0, <double>[0.3]),
        _holding('b', 0, <double>[0.2]),
      ], sink);

      player.play(0);
      player
        ..addLayer(AnimationLayer(clip: 1))
        ..addLayer(AnimationLayer(clip: 2));
      player.seek(0.0);

      expect(sink.last.single, closeTo(0.5, 1e-6));
    });

    test('a mask that does not cover the node keeps the layer out', () {
      final sink = _Sink();
      final player = _player(<AnimationClip>[
        _holding('rest', 0, <double>[0.1]),
        _holding('blink', 0, <double>[0.9]),
      ], sink);

      player.play(0);
      player.addLayer(
        AnimationLayer(clip: 1, mask: AnimationMask(const <int>{7})),
      );
      player.seek(0.0);

      expect(sink.last.single, closeTo(0.1, 1e-6));
    });
  });
}
