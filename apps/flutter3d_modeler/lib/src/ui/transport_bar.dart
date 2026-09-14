/// `S2`'s own transport bar — screen 07's own row above the timeline: a
/// round play/pause button, the current frame, the `Keys`/`Curves` toggle, a
/// loop switch and a speed control.
///
/// **The play button is drawn, not an [Icon].** The rest of this bar is
/// ordinary text and Material widgets, same as every other panel in this
/// app, but [kTransportBarCanvasKey] captures only the button itself for
/// `transport-bar.png` — the same "no glyph in the golden" rule
/// `timeline_golden_test.dart`'s own doc comment states for
/// [kTimelineCanvasKey], applied to the one part of this bar worth a
/// reference picture: the shape and colour `⌀36 on primaryContainer` names.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' show AnimationWrap;

import '../timeline_playback.dart';

/// Which of [TimelinePanel]/[CurveEditor] the timeline slot shows —
/// screen 07's own `Keys`/`Curves` switch.
enum TimelineEditMode { keys, curves }

/// The captured region of [TransportBar]'s own golden — the play/pause
/// button alone, drawn in vectors.
const Key kTransportBarCanvasKey = ValueKey<String>('transport-bar-canvas');

/// The diameter design gives the play button — `⌀36 on primaryContainer`.
const double kTransportPlayButtonSize = 36.0;

class TransportBar extends StatelessWidget {
  const TransportBar({
    super.key,
    required this.playback,
    required this.frame,
    required this.editMode,
    required this.onPlayPause,
    required this.onEditMode,
    this.onLoopChanged,
    this.onSpeedChanged,
    this.speeds = const <double>[0.25, 0.5, 1.0, 1.5, 2.0],
  });

  /// The cubit's own coarse state — [Playback.isPlaying], [Playback.wrap]
  /// and [Playback.speed] all read from here, never recomputed.
  final Playback playback;

  /// The playhead, in whole frames — read from a `ValueNotifier<int>`
  /// through a `ValueListenableBuilder` at the call site, not held here:
  /// this widget only draws whatever frame it was given.
  final int frame;

  final TimelineEditMode editMode;
  final ValueChanged<TimelineEditMode> onEditMode;

  final VoidCallback onPlayPause;

  /// The loop toggle — on for [AnimationWrap.loop], off for
  /// [AnimationWrap.once]. Null disables the control rather than guessing a
  /// caller wants [AnimationWrap.pingPong] silently dropped.
  final ValueChanged<bool>? onLoopChanged;

  final ValueChanged<double>? onSpeedChanged;

  /// The speed control's own menu. [Playback.speed] must be one of these —
  /// or the dropdown that shows it — for [DropdownButton] to have a row to
  /// point at; a speed set by anything else in this value's absence simply
  /// shows no current selection rather than throwing.
  final List<double> speeds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        _PlayPauseButton(
          playing: playback.isPlaying,
          onPressed: onPlayPause,
          background: theme.colorScheme.primaryContainer,
          foreground: theme.colorScheme.onPrimaryContainer,
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 36,
          child: Text(
            '$frame',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 12),
        SegmentedButton<TimelineEditMode>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<TimelineEditMode>>[
            ButtonSegment<TimelineEditMode>(
              value: TimelineEditMode.keys,
              label: Text('Keys'),
            ),
            ButtonSegment<TimelineEditMode>(
              value: TimelineEditMode.curves,
              label: Text('Curves'),
            ),
          ],
          selected: <TimelineEditMode>{editMode},
          onSelectionChanged: (Set<TimelineEditMode> picked) =>
              onEditMode(picked.first),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Loop',
          isSelected: playback.wrap == AnimationWrap.loop,
          onPressed: onLoopChanged == null
              ? null
              : () => onLoopChanged!(playback.wrap != AnimationWrap.loop),
          icon: const Icon(Icons.repeat),
          selectedIcon: Icon(Icons.repeat, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 4),
        DropdownButton<double>(
          value: speeds.contains(playback.speed) ? playback.speed : null,
          hint: Text('${playback.speed}x'),
          underline: const SizedBox.shrink(),
          onChanged: onSpeedChanged == null
              ? null
              : (double? value) {
                  if (value != null) onSpeedChanged!(value);
                },
          items: <DropdownMenuItem<double>>[
            for (final double speed in speeds)
              DropdownMenuItem<double>(value: speed, child: Text('${speed}x')),
          ],
        ),
      ],
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.playing,
    required this.onPressed,
    required this.background,
    required this.foreground,
  });

  final bool playing;
  final VoidCallback onPressed;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Semantics(
    label: playing ? 'Pause' : 'Play',
    button: true,
    child: MergeSemantics(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: RepaintBoundary(
            key: kTransportBarCanvasKey,
            child: CustomPaint(
              size: const Size.square(kTransportPlayButtonSize),
              painter: _PlayPauseButtonPainter(
                playing: playing,
                background: background,
                foreground: foreground,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The button's own shape and glyph — a filled circle plus a triangle or two
/// bars, drawn entirely in vectors so [kTransportBarCanvasKey]'s own golden
/// never depends on which font the machine running the test has installed.
class _PlayPauseButtonPainter extends CustomPainter {
  const _PlayPauseButtonPainter({
    required this.playing,
    required this.background,
    required this.foreground,
  });

  final bool playing;
  final Color background;
  final Color foreground;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius, Paint()..color = background);

    final glyph = Paint()..color = foreground;
    if (playing) {
      const barWidth = 3.5;
      const gap = 4.0;
      final barHeight = radius * 0.9;
      for (final dx in <double>[-gap, gap]) {
        canvas.drawRect(
          Rect.fromCenter(
            center: center.translate(dx, 0),
            width: barWidth,
            height: barHeight,
          ),
          glyph,
        );
      }
    } else {
      final path = Path()
        ..moveTo(center.dx - radius * 0.35, center.dy - radius * 0.5)
        ..lineTo(center.dx - radius * 0.35, center.dy + radius * 0.5)
        ..lineTo(center.dx + radius * 0.55, center.dy)
        ..close();
      canvas.drawPath(path, glyph);
    }
  }

  @override
  bool shouldRepaint(covariant _PlayPauseButtonPainter oldDelegate) =>
      oldDelegate.playing != playing ||
      oldDelegate.background != background ||
      oldDelegate.foreground != foreground;
}
