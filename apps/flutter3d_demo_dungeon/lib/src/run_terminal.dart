import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// `wg-02`: a `WidgetSurface` bolted to a wall of the crypt, showing what
/// [log] has collected — the same lines `FrameEffects.say` already puts on
/// the HUD one at a time, kept here instead of thrown away after three
/// seconds.
///
/// **Not a scrollable list, on purpose.** `wg-01`'s own write-up found that
/// a `Scrollable` inside a `WidgetSurfacePipeline` does not react to a
/// synthetic pointer sequence at all — a real, unfixed limit of this
/// session, not a guess — so a log worth reading here is one that never
/// needs a finger: [log] is already capped at
/// `FrameEffects.logCapacity` lines, and this shows every one of them.
final class RunTerminal extends StatelessWidget {
  const RunTerminal({super.key, required this.log});

  final ValueListenable<List<String>> log;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0B0F0C),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ValueListenableBuilder<List<String>>(
          valueListenable: log,
          builder: (context, lines, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                for (final line in lines)
                  Text(
                    '> $line',
                    style: const TextStyle(
                      color: Color(0xFF6CDB7A),
                      fontFamily: 'monospace',
                      fontSize: 18.0,
                    ),
                  ),
                if (lines.isEmpty)
                  const Text(
                    '> ...',
                    style: TextStyle(
                      color: Color(0xFF3F5C46),
                      fontFamily: 'monospace',
                      fontSize: 18.0,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
