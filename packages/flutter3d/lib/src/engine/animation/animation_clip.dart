import 'animation_track.dart';

/// A named set of tracks that play together.
final class AnimationClip {
  AnimationClip({required this.tracks, this.name})
      : duration = _durationOf(tracks);

  final String? name;
  final List<AnimationTrack> tracks;

  /// Time of the last keyframe in any track.
  final double duration;

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
