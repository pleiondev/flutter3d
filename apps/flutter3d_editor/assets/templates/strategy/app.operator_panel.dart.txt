import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// `wg-02`'s second demo scene: an operator's dashboard, driven by a live
/// [ValueListenable] rather than a fixed string — the shape a `WidgetSurface`
/// bound to `edu-05`'s `SamplerDataSource` sits behind in `tpl-04`'s own
/// `twin.json` (`template_widgets.dart`'s `'twin-dashboard'` entry).
final class OperatorPanel extends StatelessWidget {
  const OperatorPanel({
    super.key,
    required this.label,
    required this.unit,
    required this.value,
  });

  final String label;
  final String unit;
  final ValueListenable<double> value;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF15181C),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF8FA0B3),
                fontFamily: 'monospace',
                fontSize: 13.0,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 6.0),
            ValueListenableBuilder<double>(
              valueListenable: value,
              builder: (context, reading, _) => Text(
                '${reading.toStringAsFixed(1)}$unit',
                style: const TextStyle(
                  color: Color(0xFFE7C46E),
                  fontFamily: 'monospace',
                  fontSize: 32.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
