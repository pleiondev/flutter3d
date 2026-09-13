import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// `edu-04`'s panel of parameters: the one number a student's own tap
/// changes — the pendulum's length. Buttons rather than a slider or a text
/// field, `wg-01`'s own honest limit: only a tap is proven to reach a widget
/// hosted on a `WidgetSurface`, not a drag or a keystroke.
final class PendulumLabPanel extends StatelessWidget {
  const PendulumLabPanel({
    super.key,
    required this.lengthMeters,
    required this.onChangeLength,
    this.step = 0.1,
    this.minLength = 0.2,
    this.maxLength = 3.0,
  });

  final ValueListenable<double> lengthMeters;
  final ValueChanged<double> onChangeLength;
  final double step;
  final double minLength;
  final double maxLength;

  void _nudge(double by) {
    final next = (lengthMeters.value + by).clamp(minLength, maxLength);
    onChangeLength(next);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF15181C),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'STRING LENGTH',
              style: TextStyle(
                color: Color(0xFF8FA0B3),
                fontFamily: 'monospace',
                fontSize: 20.0,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 10.0),
            ValueListenableBuilder<double>(
              valueListenable: lengthMeters,
              builder: (context, length, _) => Text(
                '${length.toStringAsFixed(2)} m',
                style: const TextStyle(
                  color: Color(0xFFE7C46E),
                  fontFamily: 'monospace',
                  fontSize: 44.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _PanelButton(label: '-', onTap: () => _nudge(-step)),
                const SizedBox(width: 28.0),
                _PanelButton(label: '+', onTap: () => _nudge(step)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _PanelButton extends StatelessWidget {
  const _PanelButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 68.0,
        height: 68.0,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF283040),
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFE6EAF0),
            fontSize: 34.0,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
