import 'package:flutter/material.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

/// `rp-04`: the landing page for a `.f3drun` that arrived by file
/// association or by a drag into the browser window, rather than by
/// attaching to a game that is still running (`TimelineAttachScreen`,
/// `rp-02`).
///
/// **Not a scrubber.** Stepping through a saved run needs the genre's own
/// simulation to replay it — the same reason `flutter3d_net`'s `diff`
/// (`net-04`) and `flutter3d_testing`'s `replayGolden` (`rp-05`) both take a
/// step callback from their caller rather than owning one. This editor
/// knows no genre, so it says what the file claims — level, hash, build,
/// how long, how many checkpoints — rather than pretending to play it.
final class RunInfoScreen extends StatelessWidget {
  const RunInfoScreen({super.key, required this.run, this.sourceDescription});

  final Demo run;

  /// Where this file came from — a path, "dropped file", whatever the
  /// caller knows — shown as a subtitle, not part of the run's own data.
  final String? sourceDescription;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Run report')),
    body: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (sourceDescription != null) ...<Widget>[
            Text(
              sourceDescription!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12.0),
          ],
          _row('Level', run.level),
          _row('Level hash', run.levelHash),
          _row('Build', run.buildStamp),
          _row('Platform', run.platform ?? '(not recorded)'),
          _row('Recorded by', run.recordedBy ?? '(not recorded)'),
          _row('Steps', '${run.tape.frames.length}'),
          _row('Checkpoints', '${run.checkpoints.steps.length}'),
        ],
      ),
    ),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8.0),
    child: Row(
      children: <Widget>[
        SizedBox(
          width: 120.0,
          child: Text(label, style: const TextStyle(color: Colors.white54)),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
