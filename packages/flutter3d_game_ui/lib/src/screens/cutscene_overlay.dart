import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../access/flash_limit.dart';
import '../theme/game_ui_theme.dart';

/// What a cutscene puts over the picture: the dark of its fade, the words of
/// its subtitles, and the way out of it. Drawn over the game while a
/// `Sequence` plays.
///
/// **Only what the cutscene says, read every frame.** The fade and the
/// subtitle come from `SequenceView`, which reads them off the step the
/// `SequencePlayer` reached and the frame's place between two steps; this widget
/// keeps nothing of the cutscene, so a rewind or a skip shows what the step
/// says at once.
///
/// **But the fade goes through a [FlashLimit].** A sequence that blinks to
/// black and back faster than three times a second is a strobe, whoever
/// wrote it, so the fade is held to the limit as it is drawn. A fade in or
/// out, at any speed, is untouched.
///
/// **The words sit on [GameUiTheme.panel]**, and so does the way out, so
/// they read over a bright frame as over a dark one.
final class CutsceneOverlay extends StatefulWidget {
  /// An overlay darkened by [fade], showing [subtitle] when there is one and
  /// [skipHint] always, calling [onSkip] when skipped.
  const CutsceneOverlay({
    super.key,
    required this.fade,
    required this.subtitle,
    required this.skipHint,
    required this.onSkip,
  });

  /// How dark the screen is, nought to one.
  final double fade;

  /// What is being said, or null.
  final String? subtitle;

  /// How to skip, in the words of the device in hand.
  final String skipHint;

  /// Called when the player taps the way out, the button labelled
  /// [skipHint] in the bottom right corner.
  final VoidCallback onSkip;

  @override
  State<CutsceneOverlay> createState() => _CutsceneOverlayState();
}

class _CutsceneOverlayState extends State<CutsceneOverlay> {
  final FlashLimit _flashes = FlashLimit();

  /// When the last frame was drawn, for a build outside a frame.
  Duration _at = Duration.zero;

  /// The time of the frame being built: the scheduler's, which a test moves
  /// with `pump` as the engine moves it with the display.
  Duration _now() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.idle) {
      _at = binding.currentFrameTimeStamp;
    }
    return _at;
  }

  @override
  Widget build(BuildContext context) {
    final theme = GameUiTheme.of(context);
    final said = widget.subtitle;
    final fade = _flashes.limit(widget.fade.clamp(0.0, 1.0), at: _now());
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        IgnorePointer(
          child: ColoredBox(
            key: const ValueKey<String>('cutscene:fade'),
            color: theme.sheet.withValues(alpha: fade),
          ),
        ),
        if (said != null)
          Positioned(
            left: 48,
            right: 48,
            bottom: 72,
            child: IgnorePointer(
              child: Center(
                child: Semantics(
                  liveRegion: true,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.panel,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Text(
                        said,
                        key: const ValueKey<String>('cutscene:subtitle'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.text, fontSize: 22),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: TextButton(
            key: const ValueKey<String>('cutscene:skip'),
            onPressed: widget.onSkip,
            style: TextButton.styleFrom(
              backgroundColor: theme.panel,
              foregroundColor: theme.text,
            ),
            child: Text(widget.skipHint),
          ),
        ),
      ],
    );
  }
}
