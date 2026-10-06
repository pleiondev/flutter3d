import 'package:flutter/material.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show SaveRecord;

import '../cloud/consents.dart';
import '../cloud/save_sync.dart';
import 'settings_panel_controls.dart';

/// The two questions about the player's data, in the settings panel: may the
/// run be kept in the cloud, and may the runs they play be sent to see where
/// levels are hard. Both off until the player turns one on — see
/// [Consents].
///
/// Each says what it does in a line under it, because a switch labelled
/// "Telemetry" is a switch a player cannot answer honestly.
class PrivacySection extends StatefulWidget {
  const PrivacySection({super.key, required this.consents, this.onChanged});

  final Consents consents;

  /// Told after either answer was given, kept or not — a game that syncs
  /// on turning cloud saves on does it here.
  final VoidCallback? onChanged;

  @override
  State<PrivacySection> createState() => _PrivacySectionState();
}

class _PrivacySectionState extends State<PrivacySection> {
  /// Whether the last answer could not be written, which is said rather
  /// than shown as a switch that moved and did not mean it.
  bool _notKept = false;

  void _answer(bool Function() write) {
    final kept = write();
    setState(() => _notKept = !kept);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final consents = widget.consents;
    final faint = TextStyle(
      color: Colors.white.withValues(alpha: 0.6),
      fontSize: 12,
    );
    final hasServer = consents.sync != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SettingsHeading('Your data'),
        const SizedBox(height: 8),
        KeyedSubtree(
          key: const ValueKey<String>('privacy:cloud'),
          child: hasServer
              ? SettingsSwitchRow(
                  label: 'Cloud saves',
                  on: consents.cloud,
                  onChanged: (bool yes) =>
                      _answer(() => consents.answerCloud(yes)),
                )
              : const SettingsSwitchRow(
                  label: 'Cloud saves',
                  on: false,
                  onChanged: _nothing,
                ),
        ),
        Text(
          hasServer
              ? 'Keeps your run on the save server too, so another device '
                    'can carry on from it.'
              : 'This build has no save server; your run stays on this '
                    'device.',
          style: faint,
        ),
        const SizedBox(height: 8),
        KeyedSubtree(
          key: const ValueKey<String>('privacy:telemetry'),
          child: SettingsSwitchRow(
            label: 'Send my runs',
            on: consents.sendsRuns,
            onChanged: (bool yes) =>
                _answer(() => consents.answerTelemetry(yes)),
          ),
        ),
        Text(
          'Sends what you pressed in each level you finish, with no name, '
          'so the makers can see where levels are too hard.',
          style: faint,
        ),
        if (_notKept)
          const Text(
            'That answer could not be saved on this device.',
            style: TextStyle(color: Color(0xFFFF8A80), fontSize: 12),
          ),
      ],
    );
  }
}

void _nothing(bool _) {}

/// Asks which of two runs to keep when this device and the cloud each have
/// one, equally far along — [SyncOutcome.ask] — and answers whether to keep
/// this device's, or null when the player put the question off.
Future<bool?> askWhichRun(BuildContext context, SyncReport asked) =>
    showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Which run do you want?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(asked.message),
            const SizedBox(height: 12),
            _RunLine(label: 'On this device', run: asked.local),
            _RunLine(label: 'In the cloud', run: asked.remote),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Later'),
          ),
          TextButton(
            key: const ValueKey<String>('run:remote'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('The cloud\'s'),
          ),
          FilledButton(
            key: const ValueKey<String>('run:local'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('This device\'s'),
          ),
        ],
      ),
    );

class _RunLine extends StatelessWidget {
  const _RunLine({required this.label, required this.run});

  final String label;
  final SaveRecord? run;

  @override
  Widget build(BuildContext context) => Text(switch (run) {
    null => '$label: none',
    final SaveRecord run =>
      '$label: ${run.level.split('/').last}, '
          '${_played(run.step)} in',
  });

  /// A step count as the time it was played for, at sixty a second.
  static String _played(int step) {
    final seconds = step ~/ 60;
    return seconds < 60
        ? '${seconds}s'
        : '${seconds ~/ 60}m${(seconds % 60).toString().padLeft(2, '0')}s';
  }
}

/// Brings [sync]'s two copies of the run together before it begins, and
/// asks the player which to keep when the two are different runs equally
/// far along. Answers what happened, in a sentence, or null when there is
/// no cloud to sync with — a [GameCloud] with no server has no `sync`. Nothing is sent unless the player turned cloud
/// saves on — see [SaveSync].
///
/// **Before `begin`**, so the run that begins is the one that was kept: a
/// download under a run already playing is overwritten by its next
/// autosave.
Future<String?> syncBeforeBegin(BuildContext context, SaveSync? sync) async {
  if (sync == null) return null;
  final report = await sync.sync();
  if (report.outcome != SyncOutcome.ask || !context.mounted) {
    return report.message;
  }
  final keepLocal = await askWhichRun(context, report);
  if (keepLocal == null) return report.message;
  return (await sync.settle(report, keepLocal: keepLocal)).message;
}
