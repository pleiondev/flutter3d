import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// Flutter's `FittedBox`, under a prefix: `flutter3d_mesh` declares a type
// of the same name (a collision box fitted to a mesh), and the repository's
// scan of the type names a file uses would read the bare name as that one.
import 'package:flutter/widgets.dart' as widgets;

import 'lab_theme.dart';

/// `edu-04`'s panel of parameters: the one number a student's own tap
/// changes — the pendulum's length. Buttons rather than a slider or a text
/// field, `wg-01`'s own honest limit: only a tap is proven to reach a widget
/// hosted on a `WidgetSurface`, not a drag or a keystroke.
final class PendulumLabPanel extends StatelessWidget {
  /// The panel for the length [lengthMeters] holds, nudged by [step] a tap.
  const PendulumLabPanel({
    super.key,
    required this.lengthMeters,
    required this.onChangeLength,
    this.step = 0.1,
    this.minLength = 0.2,
    this.maxLength = 3.0,
  });

  /// The pendulum's length in metres, as the lab holds it; read to show the
  /// readout, never written here.
  final ValueListenable<double> lengthMeters;

  /// Called with the new length in metres, already clamped to
  /// [minLength]..[maxLength]; the lab sets the simulation from it.
  final ValueChanged<double> onChangeLength;

  /// How far one tap moves the length, in metres.
  final double step;

  /// The shortest length a tap can reach, in metres.
  final double minLength;

  /// The longest length a tap can reach, in metres.
  final double maxLength;

  void _nudge(double by) {
    final next = (lengthMeters.value + by).clamp(minLength, maxLength);
    onChangeLength(next);
  }

  /// **Scaled down to fit, never overflowing.** The panel is drawn into a
  /// texture of a fixed size, so a larger text size has nowhere to grow
  /// into; where a host passes one (a test, or a panel hosted flat), the
  /// whole panel shrinks to fit instead of cutting the readout off. The
  /// student's own text size reaches the slider `PendulumLabControls` puts
  /// on the scene.
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: LabTheme.panel,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: widgets.FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ValueListenableBuilder<double>(
                valueListenable: lengthMeters,
                builder: (context, length, _) => MergeSemantics(
                  child: Column(
                    children: <Widget>[
                      const Text(
                        'STRING LENGTH',
                        semanticsLabel: 'String length',
                        style: TextStyle(
                          color: LabTheme.panelLabel,
                          fontFamily: 'monospace',
                          fontSize: 20.0,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 10.0),
                      Text(
                        '${length.toStringAsFixed(2)} m',
                        style: const TextStyle(
                          color: LabTheme.panelReadout,
                          fontFamily: 'monospace',
                          fontSize: 44.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16.0),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _PanelButton(
                    label: '-',
                    semanticsLabel: 'Shorten the string',
                    onTap: () => _nudge(-step),
                  ),
                  const SizedBox(width: 28.0),
                  _PanelButton(
                    label: '+',
                    semanticsLabel: 'Lengthen the string',
                    onTap: () => _nudge(step),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.label,
    required this.semanticsLabel,
    required this.onTap,
  });

  final String label;

  /// What a screen reader says for [label], a glyph it would read as
  /// "hyphen" or "plus".
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 68.0,
          height: 68.0,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: LabTheme.panelButton,
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: LabTheme.panelButtonText,
              fontSize: 34.0,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
