/// How a blend's progress, from nought to one in time, becomes how far the
/// shot has moved, from nought to one.
typedef BlendCurve = double Function(double t);

/// How the view gets from one virtual camera to the next.
///
/// **An open value class rather than an enum**, for the reason `LoopPhase` is
/// a name: a game has blends the engine cannot list, and [CameraBlend.custom]
/// takes any curve. The named ones are the three every game asks for first.
final class CameraBlend {
  /// A blend over [seconds] along [curve].
  ///
  /// [curve] is handed the time gone as a fraction of [seconds] and answers
  /// how much of the way the shot is. It should start at nought and end at
  /// one; what it answers is clamped to that range, so an overshooting curve
  /// settles rather than flinging the camera past the next shot.
  const CameraBlend.custom(this.seconds, this.curve, {this.name = 'custom'});

  /// Smoothstep over [seconds]: starts and stops gently. The default between
  /// two cameras, because a blend that starts at full speed reads as a cut
  /// somebody fumbled.
  const CameraBlend.ease(this.seconds) : curve = _smooth, name = 'ease';

  /// The same speed all the way. For a camera on rails, where an ease would
  /// read as the rails braking.
  const CameraBlend.linear(this.seconds) : curve = _straight, name = 'linear';

  /// No blend at all: the next frame is the next camera's.
  static const CameraBlend cut = CameraBlend.custom(
    0.0,
    _straight,
    name: 'cut',
  );

  /// How long the blend takes, in seconds. Nought or less is a cut.
  final double seconds;

  /// The shape of it.
  final BlendCurve curve;

  /// For a test or a log line: `ease`, `linear`, `cut` or what [custom] was
  /// called with.
  final String name;

  /// Whether this blend is a cut.
  bool get isCut => seconds <= 0.0;

  /// How far along the shot is after [elapsed] seconds, from nought to one.
  double weight(double elapsed) {
    if (isCut) return 1.0;
    final t = (elapsed / seconds).clamp(0.0, 1.0);
    return curve(t).clamp(0.0, 1.0);
  }

  @override
  String toString() =>
      isCut ? 'CameraBlend.cut' : 'CameraBlend.$name(${seconds}s)';
}

double _smooth(double t) => t * t * (3.0 - 2.0 * t);

double _straight(double t) => t;
