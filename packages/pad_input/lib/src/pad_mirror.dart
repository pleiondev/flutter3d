import 'pad_snapshot.dart';

/// What a platform backend remembers between reads.
///
/// **Every platform pushes and this package pulls**, so something has to hold
/// the last thing each control said. Android has no way to ask a gamepad
/// anything at all — input arrives as events aimed at the focused window — and
/// `GameController` on Apple's platforms answers through a handler rather than a
/// question. The mirror is where the difference stops mattering: it takes
/// whatever shape its platform sends and fills an ordinary [PadSnapshot].
///
/// It is also where each platform's decisions live, which is the point. The
/// native code forwards; the mirror chooses; and choosing is the only part with
/// a mistake in it, so choosing is the part a test can reach.
abstract interface class PadMirror {
  /// Takes one message from the platform, in whatever shape that platform uses.
  ///
  /// Deliberately `Object?`: the wire format is the mirror's business and the
  /// channel above it has no opinion. A message it does not understand — an
  /// older Dart side reading a newer native one — changes nothing rather than
  /// throwing, because throwing here takes out the frame that read the pad.
  void note(Object? event);

  /// Whether a pad is attached.
  ///
  /// Read by the channel on either side of [note], which is how connection
  /// changes are announced: the mirror is the one that knows, so nobody parses
  /// the same message twice to find out.
  bool get connected;

  void fill(PadSnapshot out);
}
