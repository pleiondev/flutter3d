import 'animation_track.dart';

/// A named moment in an animation: [at] seconds into a clip, or a share of
/// a state's cycle — see where it is held.
final class AnimationMarker {
  const AnimationMarker(this.at, this.name);

  /// Seconds into a clip, or a 0..1 share of a state's cycle.
  final double at;
  final String name;

  @override
  String toString() => 'AnimationMarker($name at $at)';
}

/// A named set of tracks that play together.
final class AnimationClip {
  AnimationClip({
    required this.tracks,
    this.name,
    this.extras,
    this.referenceTime,
  }) : duration = _durationOf(tracks);

  final String? name;
  final List<AnimationTrack> tracks;

  /// The moment in this clip that an additive layer measures its delta from —
  /// `gfx-10n`'s own row.
  ///
  /// **A time rather than a pose, and a field rather than a convention.** An
  /// additive clip is a difference: a breath is the distance between a chest
  /// at rest and a chest full of air, and playing it on its own poses a
  /// character into a shape nobody wants. Something has to say which frame is
  /// "at rest", and glTF has nowhere to put it — which is why the engine has
  /// had layers that override for as long as it has had layers, and no
  /// additive ones. See [AnimationLayer], whose doc comment said exactly that
  /// until this row.
  ///
  /// A time, because the reference is a frame of this clip in almost every
  /// case — the convention every tool exports is that frame zero is the rest
  /// pose — and sampling the clip at that time costs nothing and needs no
  /// second structure. A caller whose reference is *not* in the clip builds a
  /// one-frame clip of it and points here, which is the same arithmetic with
  /// an extra file.
  ///
  /// **Null means this clip is not additive**, and that is what every clip
  /// read from a file has: a layer asking for an additive blend over a clip
  /// with no reference has nothing to subtract, and the player says so rather
  /// than guessing at zero.
  final double? referenceTime;

  /// Time of the last keyframe in any track.
  final double duration;

  /// glTF's own `extras` on this animation, carried opaquely — see
  /// `ModelNode.extras` for what that means and why.
  final Map<String, Object?>? extras;

  bool get isEmpty => tracks.isEmpty;

  /// The moments named in this clip — a foot down, a blow landing — read
  /// from [extras] as `{"markers": [{"time": 0.3, "name": "step"}, …]}`,
  /// seconds into the clip, earliest first. glTF has nowhere of its own to
  /// put them; an animation's `extras` is where an exporter's custom
  /// properties go. Empty when it names none, or names them in another way.
  late final List<AnimationMarker> markers = () {
    final listed = extras?['markers'];
    if (listed is! List) return const <AnimationMarker>[];
    return <AnimationMarker>[
      for (final m in listed)
        if (m is Map && m['time'] is num && m['name'] is String)
          AnimationMarker((m['time'] as num).toDouble(), m['name'] as String),
    ]..sort((a, b) => a.at.compareTo(b.at));
  }();

  static double _durationOf(List<AnimationTrack> tracks) {
    var longest = 0.0;
    for (final track in tracks) {
      if (track.endTime > longest) longest = track.endTime;
    }
    return longest;
  }

  @override
  String toString() =>
      'AnimationClip(${name ?? 'unnamed'}, ${tracks.length} tracks, '
      '${duration.toStringAsFixed(3)}s)';
}
