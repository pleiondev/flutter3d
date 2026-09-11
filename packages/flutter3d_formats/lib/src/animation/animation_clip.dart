import 'animation_track.dart';

/// A named set of tracks that play together.
final class AnimationClip {
  AnimationClip({required this.tracks, this.name, this.extras})
    : duration = _durationOf(tracks);

  final String? name;
  final List<AnimationTrack> tracks;

  /// Time of the last keyframe in any track.
  final double duration;

  /// glTF's own `extras` on this animation, carried opaquely — see
  /// `ModelNode.extras` for what that means and why.
  final Map<String, Object?>? extras;

  bool get isEmpty => tracks.isEmpty;

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
