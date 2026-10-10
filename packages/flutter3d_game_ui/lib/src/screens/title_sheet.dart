import 'package:flutter/material.dart';

import 'credits.dart';

/// What a game says before it starts: its name, one line about it, what the
/// controls are, who made the art, and how to begin.
///
/// **A gate rather than a picture.** Shown until the game is first played and
/// never again in that session: a card that comes back every time the
/// pointer or the keyboard is let go is a card in the middle of a run. It
/// waits for the player, which also makes it the first gesture a browser
/// asks for before a page may make a sound.
///
/// **The control lines are the game's and are handed in.** A list of what the
/// keys do, written beside the keys and checked by nothing, drifts the first
/// time either changes. So a game builds [lines] from what its build is —
/// touch or keys, a pointer that is captured or one that is not — and a test
/// can render each version without pretending to be a device.
///
/// **The credits are here because a licence can put them here.** CC BY asks
/// that attribution travel wherever the work does, and this is the screen
/// every player meets, including the ones who never finish.
class TitleSheet extends StatelessWidget {
  const TitleSheet({
    super.key,
    required this.title,
    required this.tagline,
    required this.lines,
    required this.credits,
    required this.prompt,
    this.notice,
    this.onBegin,
    this.creditsFootnote,
  });

  /// What the game made itself, under the credits — see
  /// [CreditsSection.footnote]. Null for no such line.
  final String? creditsFootnote;

  /// The game's name, large.
  final String title;

  /// One sentence under it.
  final String tagline;

  /// What the game is driven by, one line each.
  final List<String> lines;

  /// Whom the screen names: usually what is owed, `CreditLedger.owed`, or
  /// everything shipped when that fits.
  final List<Credit> credits;

  /// What the player has to do to begin, in the words of the device in hand.
  final String prompt;

  /// One line in amber under the controls, or null: a saved run waiting, a
  /// season half-played. Worth saying out loud, because a game that writes a
  /// checkpoint silently reassures nobody.
  final String? notice;

  /// The touch that takes the sheet down, on a build with no key to press.
  ///
  /// **On the sheet, because a layer under it cannot see the touch.** The
  /// sheet is a [ColoredBox], which hit-tests opaque, so a start layer that is
  /// a sibling below it in a `Stack` never receives a pointer. A [Listener]
  /// and not a [GestureDetector]: this must not enter the arena against the
  /// sheet's own scroll view, or a sheet too tall for the screen would begin
  /// the game on the first drag of a read.
  final VoidCallback? onBegin;

  @override
  Widget build(BuildContext context) {
    final begin = onBegin;
    final sheet = _sheet();
    if (begin == null) return sheet;
    return Listener(onPointerDown: (_) => begin(), child: sheet);
  }

  Widget _sheet() => ColoredBox(
    color: Colors.black.withValues(alpha: 0.78),
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 46,
                  fontWeight: FontWeight.w200,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tagline,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 22),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    line,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              if (notice case final said?) ...<Widget>[
                const SizedBox(height: 14),
                Text(
                  said,
                  style: TextStyle(
                    color: Colors.amber.withValues(alpha: 0.85),
                    fontSize: 14,
                  ),
                ),
              ],
              const SizedBox(height: 26),
              CreditsSection(credits: credits, footnote: creditsFootnote),
              const SizedBox(height: 26),
              Text(
                prompt,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
