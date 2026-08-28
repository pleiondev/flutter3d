import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'animation_clip.dart';
import 'animation_target.dart';
import 'animation_track.dart';

/// Plays [AnimationClip]s onto animation targets.
///
/// The player writes through `setPosition` / `setRotation` / `setScale`, which
/// is all it has to do: the version counters on a scene node make everything
/// derived from a transform — world matrices, bounds, normal matrices — refresh
/// on their own. There is no invalidation to remember and no update pass to run
/// in the right order.
///
/// One clip at a time, **crossfading between two**: `crossFadeTo` keeps the
/// clip being left over playing while the new one comes in, because cutting
/// straight to the new pose is what makes a character look as though it teleports
/// between animations.
///
/// Layers and additive blending are still a separate feature, and building them
/// in before there is anything to blend would be guessing at the API. What is
/// missing above this is a state machine that decides *which* clip — that
/// belongs to the game layer, not here.
final class AnimationPlayer {
  AnimationPlayer({required this.clips, required this.targets});

  final List<AnimationClip> clips;

  /// Node for each index a track can address, null where the instance created
  /// none. Index-aligned with the model's node list, which is what an animation
  /// channel addresses.
  final List<AnimationTarget?> targets;

  int _clipIndex = -1;
  double _time = 0.0;

  // A crossfade keeps the clip being left over playing while the new one comes
  // in. Cutting straight to the new pose is what makes a monster look as though
  // it teleported between animations, and it is most obvious exactly when it
  // matters: the moment something is shot and switches from walking to
  // flinching.
  int _fadingFrom = -1;
  double _fadeFromTime = 0.0;
  double _fadeRemaining = 0.0;
  double _fadeDuration = 0.0;

  /// Tracks of the outgoing clip, by node and path, so the matching one can be
  /// found without searching the list per track per frame.
  Map<int, AnimationTrack>? _fadeFromTracks;

  Float32List _fadeSample = Float32List(4);
  final Quaternion _fadeQuaternion = Quaternion.identity();
  bool _playing = false;
  bool _reversing = false;

  /// Playback rate. Negative values run the clip backwards.
  double speed = 1.0;

  AnimationWrap wrap = AnimationWrap.loop;

  /// Scratch big enough for any track's value, grown on demand.
  Float32List _sample = Float32List(4);

  final Quaternion _quaternion = Quaternion.identity();

  bool get isPlaying => _playing;

  /// Whether a crossfade is in progress.
  bool get isCrossFading => _fadingFrom >= 0;

  /// How far the crossfade has come, from 0 (all the old clip) to 1 (all the
  /// new one).
  double get fadeWeight {
    if (_fadingFrom < 0 || _fadeDuration <= 0.0) return 1.0;
    final done = 1.0 - _fadeRemaining / _fadeDuration;
    return done < 0.0 ? 0.0 : (done > 1.0 ? 1.0 : done);
  }

  /// Switches to [index], blending out of whatever is playing.
  ///
  /// A tenth to a fifth of a second is the useful range: shorter reads as a cut
  /// and longer makes a reaction feel late. Fading to the clip already playing
  /// is ignored rather than restarting it, so a state machine can ask every
  /// step without stuttering.
  void crossFadeTo(int index, {double duration = 0.15}) {
    if (index < 0 || index >= clips.length) return;
    if (index == _clipIndex && _playing) return;

    if (duration > 0.0 && _clipIndex >= 0 && _clipIndex < clips.length) {
      _fadingFrom = _clipIndex;
      _fadeFromTime = _time;
      _fadeDuration = duration;
      _fadeRemaining = duration;
      _fadeFromTracks = <int, AnimationTrack>{
        for (final track in clips[_clipIndex].tracks) _trackKey(track): track,
      };
    } else {
      _cancelFade();
    }

    _clipIndex = index;
    _time = 0.0;
    _playing = true;
    _reversing = false;
  }

  /// Fades to the clip called [name], if there is one.
  bool crossFadeToNamed(String name, {double duration = 0.15}) {
    for (var i = 0; i < clips.length; i++) {
      if (clips[i].name != name) continue;
      crossFadeTo(i, duration: duration);
      return true;
    }
    return false;
  }

  void _cancelFade() {
    _fadingFrom = -1;
    _fadeFromTracks = null;
    _fadeRemaining = 0.0;
    _fadeDuration = 0.0;
  }

  static double _mix(double from, double to, double t) =>
      from + (to - from) * t;

  /// Shortest-arc interpolation between two rotations.
  ///
  /// The sign flip is the part that matters: a quaternion and its negation are
  /// the same rotation, so without choosing the closer of the two, half of all
  /// blends spin the long way.
  static Quaternion _slerp(Quaternion from, Quaternion to, double t) {
    var dot = from.x * to.x + from.y * to.y + from.z * to.z + from.w * to.w;
    var sign = 1.0;
    if (dot < 0.0) {
      dot = -dot;
      sign = -1.0;
    }

    double scaleFrom;
    double scaleTo;
    if (dot > 0.9995) {
      // Nearly identical: the arc is so short that a straight line is closer
      // than the trigonometry's own error.
      scaleFrom = 1.0 - t;
      scaleTo = t;
    } else {
      final theta = math.acos(dot);
      final sinTheta = math.sin(theta);
      scaleFrom = math.sin((1.0 - t) * theta) / sinTheta;
      scaleTo = math.sin(t * theta) / sinTheta;
    }

    return Quaternion(
      scaleFrom * from.x + scaleTo * sign * to.x,
      scaleFrom * from.y + scaleTo * sign * to.y,
      scaleFrom * from.z + scaleTo * sign * to.z,
      scaleFrom * from.w + scaleTo * sign * to.w,
    )..normalize();
  }

  static int _trackKey(AnimationTrack track) =>
      track.nodeIndex * AnimationPath.values.length + track.path.index;

  bool get hasClips => clips.isNotEmpty;

  int get clipIndex => _clipIndex;

  AnimationClip? get clip =>
      _clipIndex >= 0 && _clipIndex < clips.length ? clips[_clipIndex] : null;

  /// Current playhead position in seconds.
  double get time => _time;

  double get duration => clip?.duration ?? 0.0;

  /// Names of the clips, for a UI that lets the user pick one.
  List<String> get clipNames => <String>[
    for (var i = 0; i < clips.length; i++) clips[i].name ?? 'clip $i',
  ];

  /// Starts a clip by index, or resumes the current one when [index] is null.
  ///
  /// Selecting a clip applies its first pose immediately rather than waiting for
  /// the next tick, so a paused player still shows the right thing.
  void play([int? index]) {
    if (clips.isEmpty) return;
    if (index != null) {
      if (index < 0 || index >= clips.length) {
        throw RangeError.index(index, clips, 'index');
      }
      if (index != _clipIndex) {
        _clipIndex = index;
        _time = 0.0;
        _reversing = false;
      }
    } else if (_clipIndex < 0) {
      _clipIndex = 0;
      _time = 0.0;
    }
    _playing = true;
    apply();
  }

  /// Starts the first clip whose name matches, returning false when there is
  /// none.
  bool playNamed(String name) {
    for (var i = 0; i < clips.length; i++) {
      if (clips[i].name == name) {
        play(i);
        return true;
      }
    }
    return false;
  }

  void pause() => _playing = false;

  /// Stops and rewinds, leaving the first pose applied.
  void stop() {
    _playing = false;
    _reversing = false;
    seek(0.0);
  }

  /// Moves the playhead, clamped to the clip, and applies the pose.
  void seek(double seconds) {
    final length = duration;
    _time = length <= 0.0 ? 0.0 : seconds.clamp(0.0, length);
    apply();
  }

  /// Advances by [deltaSeconds] and applies the resulting pose.
  ///
  /// Takes a delta rather than an absolute time so the caller can drive it from
  /// a `Ticker`, a fixed step, or a scrubber without the player caring which.
  void update(double deltaSeconds) {
    if (_fadingFrom >= 0) {
      // The clip being left keeps playing while it fades, which is the whole
      // difference between a crossfade and a dissolve to a frozen pose.
      _fadeFromTime += deltaSeconds * speed;
      final outgoing = clips[_fadingFrom].duration;
      if (outgoing > 0.0) _fadeFromTime %= outgoing;

      _fadeRemaining -= deltaSeconds;
      if (_fadeRemaining <= 0.0) _cancelFade();
    }

    if (!_playing || clip == null) return;

    final length = duration;
    if (length <= 0.0) {
      apply();
      return;
    }

    var next = _time + deltaSeconds * speed * (_reversing ? -1.0 : 1.0);

    switch (wrap) {
      case AnimationWrap.once:
        if (next >= length) {
          next = length;
          _playing = false;
        } else if (next <= 0.0) {
          next = 0.0;
          _playing = false;
        }

      case AnimationWrap.loop:
        // Modulo rather than a subtraction, so a long pause or a huge speed
        // does not need several iterations to catch up.
        next %= length;
        if (next < 0.0) next += length;

      case AnimationWrap.pingPong:
        while (next > length || next < 0.0) {
          if (next > length) {
            next = 2.0 * length - next;
            _reversing = !_reversing;
          } else if (next < 0.0) {
            next = -next;
            _reversing = !_reversing;
          }
        }
    }

    _time = next;
    apply();
  }

  /// Writes the pose at the current time onto the target nodes.
  ///
  /// Public because seeking, seeking after a reparent, and applying a clip while
  /// paused are all the same operation.
  void apply() {
    final active = clip;
    if (active == null) return;

    for (final track in active.tracks) {
      if (track.nodeIndex < 0 || track.nodeIndex >= targets.length) continue;
      final node = targets[track.nodeIndex];
      if (node == null) continue;

      if (_sample.length < track.componentCount) {
        _sample = Float32List(track.componentCount);
      }
      track.sample(_time, _sample);

      // During a crossfade, mix in the same joint's track from the clip being
      // left. A joint the outgoing clip did not animate simply arrives at its
      // new value, which is right: there is nothing to blend from.
      final weight = fadeWeight;
      // Written out rather than as a conditional expression: `a ? b?[c] : d`
      // parses as a nullable type in Dart and fails to compile.
      AnimationTrack? previous;
      if (weight < 1.0) {
        previous = _fadeFromTracks?[_trackKey(track)];
      }
      if (previous != null) {
        if (_fadeSample.length < previous.componentCount) {
          _fadeSample = Float32List(previous.componentCount);
        }
        previous.sample(_fadeFromTime, _fadeSample);
      }

      switch (track.path) {
        case AnimationPath.translation:
          if (previous == null) {
            node.setPosition(_sample[0], _sample[1], _sample[2]);
          } else {
            node.setPosition(
              _mix(_fadeSample[0], _sample[0], weight),
              _mix(_fadeSample[1], _sample[1], weight),
              _mix(_fadeSample[2], _sample[2], weight),
            );
          }

        case AnimationPath.rotation:
          // glTF stores quaternions xyzw, which is the order this constructor
          // takes.
          _quaternion.setValues(_sample[0], _sample[1], _sample[2], _sample[3]);
          if (previous != null) {
            _fadeQuaternion.setValues(
              _fadeSample[0],
              _fadeSample[1],
              _fadeSample[2],
              _fadeSample[3],
            );
            // Slerp, not a component lerp: blending quaternions linearly and
            // renormalising takes the long way round whenever the two are more
            // than a quarter turn apart, which is exactly what a hurt reaction
            // is.
            _quaternion.setFrom(_slerp(_fadeQuaternion, _quaternion, weight));
          }
          node.setRotation(_quaternion);

        case AnimationPath.scale:
          if (previous == null) {
            node.setScale(_sample[0], _sample[1], _sample[2]);
          } else {
            node.setScale(
              _mix(_fadeSample[0], _sample[0], weight),
              _mix(_fadeSample[1], _sample[1], weight),
              _mix(_fadeSample[2], _sample[2], weight),
            );
          }

        case AnimationPath.weights:
          // Morph targets are not implemented; the track is decoded and carried
          // so the clip round-trips, but there is nothing to write it to.
          break;
      }
    }
  }

  @override
  String toString() =>
      'AnimationPlayer(${clips.length} clips, '
      'clip $_clipIndex at ${_time.toStringAsFixed(2)}s'
      '${_playing ? ', playing' : ''})';
}
