import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import '../scene/scene_node.dart';
import 'animation_clip.dart';

/// How a clip behaves when it runs off its end.
enum AnimationWrap {
  /// Hold the final pose.
  once,

  /// Start over.
  loop,

  /// Play backwards, then forwards, and so on.
  pingPong,
}

/// Plays [AnimationClip]s onto scene nodes.
///
/// The player writes through `setPosition` / `setRotation` / `setScale`, which
/// is all it has to do: the version counters on [SceneNode] make everything
/// derived from a transform — world matrices, bounds, normal matrices — refresh
/// on their own. There is no invalidation to remember and no update pass to run
/// in the right order.
///
/// One clip at a time. Layers, crossfades and additive blending are a separate
/// feature, and building them in before there is anything to blend would be
/// guessing at the API.
final class AnimationPlayer {
  AnimationPlayer({required this.clips, required this.targets});

  final List<AnimationClip> clips;

  /// Node for each index a track can address, null where the instance created
  /// none. Index-aligned with the model's node list, which is what an animation
  /// channel addresses.
  final List<SceneNode?> targets;

  int _clipIndex = -1;
  double _time = 0.0;
  bool _playing = false;
  bool _reversing = false;

  /// Playback rate. Negative values run the clip backwards.
  double speed = 1.0;

  AnimationWrap wrap = AnimationWrap.loop;

  /// Scratch big enough for any track's value, grown on demand.
  Float32List _sample = Float32List(4);

  final Quaternion _quaternion = Quaternion.identity();

  bool get isPlaying => _playing;

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

      switch (track.path) {
        case AnimationPath.translation:
          node.setPosition(_sample[0], _sample[1], _sample[2]);

        case AnimationPath.rotation:
          // glTF stores quaternions xyzw, which is the order this constructor
          // takes.
          _quaternion.setValues(
            _sample[0],
            _sample[1],
            _sample[2],
            _sample[3],
          );
          node.setRotation(_quaternion);

        case AnimationPath.scale:
          node.setScale(_sample[0], _sample[1], _sample[2]);

        case AnimationPath.weights:
          // Morph targets are not implemented; the track is decoded and carried
          // so the clip round-trips, but there is nothing to write it to.
          break;
      }
    }
  }

  @override
  String toString() => 'AnimationPlayer(${clips.length} clips, '
      'clip $_clipIndex at ${_time.toStringAsFixed(2)}s'
      '${_playing ? ', playing' : ''})';
}
