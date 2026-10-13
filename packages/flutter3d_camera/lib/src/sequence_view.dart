import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

/// What a cutscene shows: the camera's pose, the fade and the subtitle, read
/// off a [Sequence]'s keys for a frame.
///
/// **The picture half of a cutscene.** A [SequencePlayer] is played by the
/// step in `flutter3d_sim`: it holds the step, fires the signals and directs
/// the actors, and that is all a replay or a server needs of it. Where the
/// camera stands, how dark the screen is and what the subtitles read are
/// only drawn, so they are worked out here, from the player's step and the
/// frame's place between two steps, and nothing the step computes reads
/// them.
///
/// **Built once per sequence.** The eye and the point it looks at each run
/// along a curve through their keys, and the curves are made when the view
/// is, so a frame allocates nothing. A game keeps one view for as long as it
/// plays the sequence, and asks it about the player every frame:
///
/// ```dart
/// final view = SequenceView(cutscene.player.sequence);
/// // every frame
/// final fovY = view.cameraOf(cutscene.player, eye, target, alpha: alpha);
/// final fade = view.fadeOf(cutscene.player, alpha: alpha);
/// final words = view.subtitleOf(cutscene.player);
/// ```
///
/// An editor scrubbing a sequence with no player reads it by the step
/// instead: [cameraAt], [fadeAt] and [subtitleAt].
final class SequenceView {
  SequenceView(this.sequence)
    : _path = _curve(sequence.cameraKeys, (CameraKey k) => k.at),
      _looks = _curve(sequence.cameraKeys, (CameraKey k) => k.look);

  /// The sequence this view reads.
  final Sequence sequence;

  final CatmullRom? _path;
  final CatmullRom? _looks;

  static CatmullRom? _curve(
    List<CameraKey> keys,
    Vector3 Function(CameraKey key) of,
  ) => keys.length < 2
      ? null
      : CatmullRom(<Vector3>[for (final key in keys) of(key)], closed: false);

  /// Where the camera is at [step], a step that may fall between two: the
  /// eye into [at] and what it looks at into [look], both in metres, and its
  /// vertical field of view returned, in radians. Before the first key it
  /// holds the first, after the last the last. Throws a [StateError] for a
  /// sequence with no camera; see [Sequence.hasCamera].
  ///
  /// **On the path, at the keys' times.** The eye and the point it looks at
  /// each run along a curve through their keys, and between two keys they
  /// cover the curve between them at one speed (or, with [Sequence.ease],
  /// slowing into and out of each key), so the camera is at a key on its
  /// step exactly and never cuts a corner the author did not draw.
  double cameraAt(double step, Vector3 at, Vector3 look) {
    final keys = sequence.cameraKeys;
    if (keys.isEmpty) throw StateError('this sequence has no camera');
    if (keys.length == 1 || step <= keys.first.step) {
      at.setFrom(keys.first.at);
      look.setFrom(keys.first.look);
      return keys.first.fovY;
    }
    if (step >= keys.last.step) {
      at.setFrom(keys.last.at);
      look.setFrom(keys.last.look);
      return keys.last.fovY;
    }
    var i = 0;
    while (keys[i + 1].step <= step) {
      i++;
    }
    final a = keys[i];
    final b = keys[i + 1];
    final linear = (step - a.step) / (b.step - a.step);
    final f = sequence.ease ? linear * linear * (3.0 - 2.0 * linear) : linear;
    double along(CatmullRom curve) {
      final from = curve.distanceToPoint(i);
      return from + (curve.distanceToPoint(i + 1) - from) * f;
    }

    _path!.sampleAt(along(_path), at);
    _looks!.sampleAt(along(_looks), look);
    return a.fovY + (b.fovY - a.fovY) * f;
  }

  /// What the subtitles say at [step], or null: the one that started last
  /// among those showing.
  String? subtitleAt(int step) {
    String? showing;
    var since = -1;
    for (final cue in sequence.subtitles) {
      if (cue.from <= step && step < cue.to && cue.from >= since) {
        showing = cue.text;
        since = cue.from;
      }
    }
    return showing;
  }

  /// How dark the screen is at [step], a fraction from 0 clear to 1 black:
  /// straight between two keys, held before the first and after the last,
  /// 0 with none.
  double fadeAt(double step) {
    final fades = sequence.fades;
    if (fades.isEmpty) return 0.0;
    if (step <= fades.first.step) return fades.first.value;
    if (step >= fades.last.step) return fades.last.value;
    var i = 0;
    while (fades[i + 1].step <= step) {
      i++;
    }
    final a = fades[i];
    final b = fades[i + 1];
    return a.value + (b.value - a.value) * (step - a.step) / (b.step - a.step);
  }

  /// The moment of [player] to draw: [alpha] of the way from the step
  /// before the one it reached to that one, as a frame between two steps is
  /// drawn.
  double _drawn(SequencePlayer player, double alpha) {
    assert(
      identical(player.sequence, sequence),
      'a view reads the player of its own sequence',
    );
    return (player.step - 1 + alpha).clamp(0.0, sequence.steps.toDouble());
  }

  /// Where the camera is to be drawn from for [player], [alpha] of the way
  /// between its last two steps (see [cameraAt]), or null when the cutscene
  /// leaves the camera to the game.
  double? cameraOf(
    SequencePlayer player,
    Vector3 at,
    Vector3 look, {
    double alpha = 1.0,
  }) => sequence.hasCamera ? cameraAt(_drawn(player, alpha), at, look) : null;

  /// What the subtitles say at the step [player] reached, or null.
  String? subtitleOf(SequencePlayer player) {
    assert(
      identical(player.sequence, sequence),
      'a view reads the player of its own sequence',
    );
    return subtitleAt(player.step);
  }

  /// How dark the screen is to be drawn for [player], [alpha] of the way
  /// between its last two steps, from 0 clear to 1 black.
  double fadeOf(SequencePlayer player, {double alpha = 1.0}) =>
      fadeAt(_drawn(player, alpha));
}
