import 'package:flutter3d_core/formats.dart';
import 'animation_target.dart';

/// Where a track sits in a pose: one number for a node and a path together.
///
/// Shared by the player's crossfade and by every layer, so the two cannot
/// disagree about which track matches which.
int animationTrackKey(AnimationTrack track) =>
    track.nodeIndex * AnimationPath.values.length + track.path.index;

/// How a layer's pose meets the base's — `gfx-10n`.
enum AnimationBlend {
  /// The layer's value replaces the base's, faded by the layer's weight.
  ///
  /// What every layer did before there was a choice, and still the right one
  /// for a clip authored as a whole performance of the joints it covers: an
  /// upper-body reload is a reload, not a correction to one.
  override,

  /// The layer's distance from its own reference pose is laid on top of the
  /// base.
  ///
  /// For a clip authored as a *difference*: a breath, a recoil, a lean, a
  /// flinch. Playing one of these on its own poses a character into a shape
  /// nobody wants, which is the sign that it is additive — and the reason it
  /// needs [AnimationClip.referenceTime] to say what it is a difference
  /// *from*.
  additive,
}

/// A clip played over part of a skeleton, on top of whatever the base is doing.
///
/// **The thing a crossfade cannot do.** `AnimationPlayer.crossFadeTo` moves the
/// whole skeleton from one clip to another; a layer leaves the base playing and
/// takes over the joints its [mask] names. That is the difference between a
/// monster that stops walking in order to flinch and one that flinches while it
/// keeps walking, and between a soldier who must stand still to reload and one
/// who reloads on the move.
///
/// **Override by default, additive when asked** — [blend], `gfx-10n`. Where a
/// layer covers a joint and has a track for it, the layer's value replaces the
/// base's, faded by [weight]. [AnimationBlend.additive] instead takes the
/// distance between the clip at this moment and the clip at its own
/// [AnimationClip.referenceTime] and lays that *on top of* the base — which is
/// what a breath over a walk, a recoil over an aim and a lean over a run all
/// want, and what an override can never be: an overriding breath stops the
/// walk for as long as it lasts.
///
/// The reference frame was the whole of why this was override-only. glTF has
/// nowhere to say which frame is the rest pose, so the clip carries it now;
/// a clip that does not name one cannot be blended additively and the player
/// leaves it to the override path rather than guessing at zero.
///
/// **A joint the layer's clip does not animate keeps the base's value**, even
/// inside the mask. A mask says where a layer *may* write, not where it must:
/// an upper-body clip that animates the arms and not the head leaves the head
/// to the walk, which is what a hand-authored upper-body clip expects.
///
/// [weight] is not faded by this class. A layer that snapped from nothing to
/// everything would pop, so a caller ramps it — `fadeTo` is the ramp, and it is
/// here rather than in the caller because every caller would write the same
/// four lines and one of them would forget to clamp.
final class AnimationLayer {
  AnimationLayer({
    required this.clip,
    AnimationMask? mask,
    this.weight = 1.0,
    this.wrap = AnimationWrap.loop,
    this.speed = 1.0,
    this.blend = AnimationBlend.override,
  }) : mask = mask ?? AnimationMask.everything;

  /// Index into the player's clips.
  int clip;

  /// Whether this layer replaces the base's pose or adds to it — `gfx-10n`.
  ///
  /// [AnimationBlend.additive] needs the clip to name an
  /// [AnimationClip.referenceTime]; without one there is nothing to measure a
  /// delta from and the player falls back to overriding, which is the answer
  /// that at least shows the clip rather than silently posing nothing.
  AnimationBlend blend;

  /// The joints this layer may write.
  AnimationMask mask;

  /// How much of this layer's pose is used, from 0 (none) to 1 (all of it).
  ///
  /// Clamped where it is read rather than where it is set, so a caller driving
  /// it from a curve or a slider cannot leave the player holding a number it
  /// has to defend against every frame.
  double weight;

  /// How the clip behaves at its end. `once` is the usual one for a layer: a
  /// reload or a flinch happens and is over.
  AnimationWrap wrap;

  /// Playback rate, independent of the base's.
  double speed;

  /// Where the layer's own playhead is, in seconds.
  double get time => _time;
  double _time = 0.0;

  bool get isPlaying => _playing;
  bool _playing = true;

  bool _reversing = false;

  /// Where [weight] is heading and how long it has to get there.
  double _targetWeight = 1.0;
  double _rampRemaining = 0.0;

  /// Whether the layer has finished a `once` clip and gone quiet.
  bool get isFinished => !_playing && wrap == AnimationWrap.once;

  /// Rewinds to the start and plays again.
  void restart() {
    _time = 0.0;
    _reversing = false;
    _playing = true;
  }

  /// Moves [weight] to [to] over [seconds], or immediately when that is zero.
  ///
  /// The ramp that keeps a layer from popping in. Fading *out* is the same call
  /// with a target of nought, and a caller that wants the layer gone rather
  /// than silent removes it from `AnimationPlayer.layers` once it gets there.
  void fadeTo(double to, {double seconds = 0.15}) {
    final wanted = to.clamp(0.0, 1.0);
    if (seconds <= 0.0) {
      weight = wanted;
      _targetWeight = wanted;
      _rampRemaining = 0.0;
      return;
    }
    _targetWeight = wanted;
    _rampRemaining = seconds;
  }

  /// Advances the playhead and the weight ramp. Called by the player.
  void advance(double deltaSeconds, double clipDuration) {
    if (_rampRemaining > 0.0) {
      if (deltaSeconds >= _rampRemaining) {
        weight = _targetWeight;
        _rampRemaining = 0.0;
      } else {
        // Toward the target by the fraction of the ramp this step used, which
        // reaches it exactly rather than approaching it for ever.
        weight += (_targetWeight - weight) * (deltaSeconds / _rampRemaining);
        _rampRemaining -= deltaSeconds;
      }
    }

    if (!_playing || clipDuration <= 0.0) return;

    final advanced = advanceTime(
      time: _time,
      deltaSeconds: deltaSeconds * speed,
      length: clipDuration,
      wrap: wrap,
      reversing: _reversing,
    );
    _time = advanced.time;
    _reversing = advanced.reversing;
    if (advanced.stopped) _playing = false;
  }

  /// What this layer contributes, from 0 to 1, with the clamp applied.
  double get effectiveWeight =>
      weight < 0.0 ? 0.0 : (weight > 1.0 ? 1.0 : weight);

  /// This layer's tracks by [animationTrackKey], built once per clip.
  ///
  /// Cached on the layer rather than in the player because the layer is what
  /// outlives a frame and what knows when its clip changed. Rebuilt when the
  /// caller points [clip] somewhere else, which is the only way it can go
  /// stale.
  Map<int, AnimationTrack> tracksOf(AnimationClip source) {
    if (identical(_cachedFor, source)) return _cachedTracks;
    _cachedFor = source;
    _cachedTracks = <int, AnimationTrack>{
      for (final track in source.tracks) animationTrackKey(track): track,
    };
    return _cachedTracks;
  }

  AnimationClip? _cachedFor;
  Map<int, AnimationTrack> _cachedTracks = const <int, AnimationTrack>{};
}

/// Where a playhead lands after a step, and what the wrap did to it.
///
/// **One copy of this arithmetic**, shared by the base player and every layer.
/// It was the base's alone and a layer needed the same three cases; two copies
/// of a ping-pong are two chances to turn round on a different frame, and the
/// bug that produces is a layer that drifts against the clip it is supposed to
/// be in step with.
({double time, bool reversing, bool stopped}) advanceTime({
  required double time,
  required double deltaSeconds,
  required double length,
  required AnimationWrap wrap,
  required bool reversing,
}) {
  var next = time + deltaSeconds * (reversing ? -1.0 : 1.0);
  var turned = reversing;

  switch (wrap) {
    case AnimationWrap.once:
      if (next >= length) {
        return (time: length, reversing: turned, stopped: true);
      }
      if (next <= 0.0) return (time: 0.0, reversing: turned, stopped: true);

    case AnimationWrap.loop:
      // Modulo rather than a subtraction, so a long pause or a huge speed does
      // not need several iterations to catch up.
      next %= length;
      if (next < 0.0) next += length;

    case AnimationWrap.pingPong:
      while (next > length || next < 0.0) {
        if (next > length) {
          next = 2.0 * length - next;
          turned = !turned;
        } else if (next < 0.0) {
          next = -next;
          turned = !turned;
        }
      }
  }

  return (time: next, reversing: turned, stopped: false);
}
