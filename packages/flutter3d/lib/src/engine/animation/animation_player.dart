import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'animation_clip.dart';
import 'animation_layer.dart';
import 'animation_mask.dart';
import 'animation_target.dart';
import 'animation_track.dart';
import 'morph_sink.dart';

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
/// **And [layers] over the top of that**, each one a clip on the joints its
/// mask names — an upper body that reloads while the legs keep running. A
/// crossfade moves the whole skeleton; a layer moves part of it and leaves the
/// rest alone. See [AnimationLayer], which says why it overrides rather than
/// adds, and [AnimationMask], which says why a mask is indices.
///
/// The base is applied first and a layer writes over it, so a player with no
/// layers poses exactly as it did before there were any — `animation_layer_test`
/// holds that, because a feature that moved every existing character by a hair
/// would have been a feature that moved every golden.
///
/// Additive blending is still a separate feature. What is missing above this is
/// a state machine that decides *which* clip — that belongs to the game layer,
/// not here.
final class AnimationPlayer {
  AnimationPlayer({
    required this.clips,
    required this.targets,
    List<MorphSink?>? morphs,
  }) : morphs = morphs ?? const <MorphSink?>[];

  final List<AnimationClip> clips;

  /// Node for each index a track can address, null where the instance created
  /// none. Index-aligned with the model's node list, which is what an animation
  /// channel addresses.
  final List<AnimationTarget?> targets;

  /// Where a weights track goes, index-aligned with [targets].
  ///
  /// Empty for a model that morphs nothing, which is almost all of them. A
  /// second list rather than a fourth setter on [AnimationTarget]: see
  /// [MorphSink], which says why a weight is not a transform.
  final List<MorphSink?> morphs;

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

  /// Scratch for a layer's own sample, and the keys the base clip writes.
  ///
  /// Both are fields rather than locals for the reason every buffer in a frame
  /// here is: `apply` runs once per model per frame, and a set allocated inside
  /// it would be a set allocated per model per frame.
  Float32List _layerSample = Float32List(4);
  final Set<int> _baseKeys = <int>{};

  final Quaternion _fadeQuaternion = Quaternion.identity();
  bool _playing = false;
  bool _reversing = false;

  /// Playback rate. Negative values run the clip backwards.
  double speed = 1.0;

  AnimationWrap wrap = AnimationWrap.loop;

  /// Clips playing over the base, in the order they are written.
  ///
  /// A list rather than one overlay, because the order is the answer to two
  /// layers wanting the same joint: the last one wins, which is the rule a
  /// caller can hold in their head. Empty is the ordinary case and costs a
  /// length check per frame.
  ///
  /// Owned by the caller: a game adds a layer when a reload starts and removes
  /// it when the layer reports [AnimationLayer.isFinished] and its weight has
  /// been faded back to nothing. The player does not remove them, because
  /// "finished" and "wanted gone" are not the same moment — a layer held at
  /// full weight on its last pose is how a game holds a pose.
  final List<AnimationLayer> layers = <AnimationLayer>[];

  /// Adds [layer] and returns it, for the one-liner a caller usually wants.
  AnimationLayer addLayer(AnimationLayer layer) {
    layers.add(layer);
    return layer;
  }

  /// Starts [clip] over [mask] and returns the layer driving it.
  ///
  /// Fades in rather than appearing, for the reason [AnimationLayer.fadeTo]
  /// exists: a layer that arrives at full weight on one frame pops.
  AnimationLayer playLayer(
    int clip, {
    AnimationMask? mask,
    AnimationWrap wrap = AnimationWrap.once,
    double fadeIn = 0.15,
    double speed = 1.0,
  }) {
    final layer = AnimationLayer(
      clip: clip,
      mask: mask,
      wrap: wrap,
      speed: speed,
      weight: fadeIn > 0.0 ? 0.0 : 1.0,
    );
    if (fadeIn > 0.0) layer.fadeTo(1.0, seconds: fadeIn);
    return addLayer(layer);
  }

  /// The first layer playing [clip], or null.
  ///
  /// What a caller asks before starting one, so a reload pressed twice does not
  /// stack two of the same layer on top of each other.
  AnimationLayer? layerOf(int clip) {
    for (final layer in layers) {
      if (layer.clip == clip) return layer;
    }
    return null;
  }

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

  /// One copy, shared with the layers — see [animationTrackKey].
  static int _trackKey(AnimationTrack track) => animationTrackKey(track);

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

    // Layers run whether or not the base does: a player paused on a pose with
    // a flinch over it should still finish the flinch.
    _advanceLayers(deltaSeconds);

    if (!_playing || clip == null) {
      if (layers.isNotEmpty) apply();
      return;
    }

    final length = duration;
    if (length <= 0.0) {
      apply();
      return;
    }

    final advanced = advanceTime(
      time: _time,
      deltaSeconds: deltaSeconds * speed,
      length: length,
      wrap: wrap,
      reversing: _reversing,
    );
    _time = advanced.time;
    _reversing = advanced.reversing;
    if (advanced.stopped) _playing = false;

    apply();
  }

  void _advanceLayers(double deltaSeconds) {
    for (final layer in layers) {
      final index = layer.clip;
      if (index < 0 || index >= clips.length) continue;
      layer.advance(deltaSeconds, clips[index].duration);
    }
  }

  /// Writes the pose at the current time onto the target nodes.
  ///
  /// Public because seeking, seeking after a reparent, and applying a clip while
  /// paused are all the same operation.
  void apply() {
    final active = clip;
    if (active == null) {
      if (layers.isNotEmpty) _applyLayersAlone();
      return;
    }

    _baseKeys.clear();
    for (final track in active.tracks) {
      _baseKeys.add(_trackKey(track));
    }

    for (final track in active.tracks) {
      // Weights go to a sink and not to a node, so they are answered before the
      // node lookup: a mesh that morphs need not be one an animation also
      // moves, and requiring an `AnimationTarget` for it would drop the track
      // of a face that never travels.
      if (track.path == AnimationPath.weights) {
        _applyWeights(track);
        continue;
      }

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

      // The crossfade's blend, folded into the sample rather than done at each
      // write. That is what lets a layer blend on top of it: by the time the
      // layers are asked, `_sample` holds one pose for this joint whatever the
      // base was doing to get there.
      if (previous != null) {
        _blendInto(_sample, _fadeSample, weight, track.path);
      }

      if (layers.isNotEmpty) {
        _blendLayersInto(_sample, _trackKey(track), track.path);
      }

      _write(node, track.path, _sample);
    }

    if (layers.isNotEmpty) _applyLayersWhereBaseIsSilent();
  }

  /// Samples a weights track and hands it to whatever is morphing.
  ///
  /// Not blended with a crossfade or a layer, and that is a limit rather than
  /// an oversight: two clips fading between two expressions would want the
  /// weights mixed, and doing it would mean the outgoing clip's weights track
  /// looked up the same way the outgoing pose is. It is written down here
  /// rather than half-built — nothing in this repository morphs through a
  /// crossfade yet, and guessing at how it should feel is how an API arrives
  /// that nobody can use.
  void _applyWeights(AnimationTrack track) {
    if (track.nodeIndex < 0 || track.nodeIndex >= morphs.length) return;
    final sink = morphs[track.nodeIndex];
    if (sink == null) return;

    if (_sample.length < track.componentCount) {
      _sample = Float32List(track.componentCount);
    }
    track.sample(_time, _sample);
    if (_weightScratch.length != track.componentCount) {
      _weightScratch = List<double>.filled(track.componentCount, 0.0);
    }
    for (var i = 0; i < track.componentCount; i++) {
      _weightScratch[i] = _sample[i];
    }
    sink.setWeights(_weightScratch);
  }

  /// The weights handed to a sink, reused: a list per model per frame is an
  /// allocation for a value that usually has not moved.
  List<double> _weightScratch = const <double>[];

  /// Mixes [from] into [into] by [weight], the way the path wants mixing.
  ///
  /// [into] is the destination pose and ends up holding the result. Rotation
  /// goes through the shortest arc; everything else is a straight line.
  void _blendInto(
    Float32List into,
    Float32List from,
    double weight,
    AnimationPath path,
  ) {
    switch (path) {
      case AnimationPath.rotation:
        _quaternion.setValues(into[0], into[1], into[2], into[3]);
        _fadeQuaternion.setValues(from[0], from[1], from[2], from[3]);
        // Slerp, not a component lerp: blending quaternions linearly and
        // renormalising takes the long way round whenever the two are more than
        // a quarter turn apart, which is exactly what a hurt reaction is.
        final mixed = _slerp(_fadeQuaternion, _quaternion, weight);
        into[0] = mixed.x;
        into[1] = mixed.y;
        into[2] = mixed.z;
        into[3] = mixed.w;

      case AnimationPath.translation:
      case AnimationPath.scale:
        for (var i = 0; i < 3; i++) {
          into[i] = _mix(from[i], into[i], weight);
        }

      case AnimationPath.weights:
        break;
    }
  }

  /// Lets every layer covering this joint write over [pose], in order.
  ///
  /// The last layer wins where two want the same joint, which is the rule the
  /// list's own documentation states — and it falls out of blending them one
  /// after another rather than being a special case.
  void _blendLayersInto(Float32List pose, int key, AnimationPath path) {
    for (final layer in layers) {
      final index = layer.clip;
      if (index < 0 || index >= clips.length) continue;
      final weight = layer.effectiveWeight;
      if (weight <= 0.0) continue;
      final track = layer.tracksOf(clips[index])[key];
      if (track == null) continue;
      if (!layer.mask.covers(track.nodeIndex)) continue;

      if (_layerSample.length < track.componentCount) {
        _layerSample = Float32List(track.componentCount);
      }
      track.sample(layer.time, _layerSample);
      // The layer is what is being mixed *in*, so it is the destination and the
      // pose so far is what it comes from — the same direction the crossfade
      // uses, where a weight of one means all of the newer thing. Written the
      // other way round first, with `1 - weight`, which is a layer at full
      // weight showing the base: the half-weight test passed anyway, because
      // mixing is symmetric at a half and says nothing about which end is which.
      _blendInto(_layerSample, pose, weight, path);
      pose.setRange(0, track.componentCount, _layerSample);
    }
  }

  /// Writes the joints layers animate that the base clip does not touch.
  ///
  /// **Taken outright rather than faded**, which is the rule the crossfade
  /// above already follows for the same situation: there is nothing to blend
  /// from. The base is not posing this joint, so the alternative would be to
  /// blend against whatever the node happened to be holding — and an
  /// [AnimationTarget] cannot be read, deliberately, because reading one would
  /// mean depending on the scene graph. The cost is that a layer fading in over
  /// a joint its base ignores arrives at once; an upper-body clip over a walk
  /// that animates the arms — which is the ordinary case — never meets it.
  void _applyLayersWhereBaseIsSilent() {
    for (final layer in layers) {
      final index = layer.clip;
      if (index < 0 || index >= clips.length) continue;
      if (layer.effectiveWeight <= 0.0) continue;

      for (final track in clips[index].tracks) {
        if (_baseKeys.contains(_trackKey(track))) continue;
        if (!layer.mask.covers(track.nodeIndex)) continue;
        if (track.nodeIndex < 0 || track.nodeIndex >= targets.length) continue;
        final node = targets[track.nodeIndex];
        if (node == null) continue;

        if (_layerSample.length < track.componentCount) {
          _layerSample = Float32List(track.componentCount);
        }
        track.sample(layer.time, _layerSample);
        _write(node, track.path, _layerSample);
      }
    }
  }

  /// Poses from the layers alone, for a player with no base clip selected.
  void _applyLayersAlone() {
    _baseKeys.clear();
    _applyLayersWhereBaseIsSilent();
  }

  void _write(AnimationTarget node, AnimationPath path, Float32List pose) {
    switch (path) {
      case AnimationPath.translation:
        node.setPosition(pose[0], pose[1], pose[2]);

      case AnimationPath.rotation:
        // glTF stores quaternions xyzw, which is the order this constructor
        // takes.
        _quaternion.setValues(pose[0], pose[1], pose[2], pose[3]);
        node.setRotation(_quaternion);

      case AnimationPath.scale:
        node.setScale(pose[0], pose[1], pose[2]);

      case AnimationPath.weights:
        // Answered before the node lookup — see `_applyWeights`. Nothing
        // reaches here.
        break;
    }
  }

  @override
  String toString() =>
      'AnimationPlayer(${clips.length} clips, '
      'clip $_clipIndex at ${_time.toStringAsFixed(2)}s'
      '${_playing ? ', playing' : ''})';
}
