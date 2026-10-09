import 'package:flutter/material.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show SaveRecord;

import '../l10n/game_localizations.dart';
import '../theme/game_ui_theme.dart';
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

  @override
  void initState() {
    super.initState();
    // The answers are read from storage when the consents are made; until
    // they are, both switches read off, and they move when the read lands.
    widget.consents.ready.then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _answer(Future<bool> Function() write) async {
    final answering = write();
    // The switch moves at once — the answer holds for this session whether
    // or not it is kept — and the line under it says if it was not.
    setState(() {});
    final kept = await answering;
    if (!mounted) return;
    setState(() => _notKept = !kept);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final consents = widget.consents;
    final words = Flutter3dGameLocalizations.of(context);
    final theme = GameUiTheme.of(context);
    final faint = TextStyle(color: theme.faint, fontSize: 12);
    final hasServer = consents.sync != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SettingsHeading(words.yourData),
        const SizedBox(height: 8),
        KeyedSubtree(
          key: const ValueKey<String>('privacy:cloud'),
          child: hasServer
              ? SettingsSwitchRow(
                  label: words.cloudSaves,
                  on: consents.hasCloudConsent,
                  onChanged: (bool yes) =>
                      _answer(() => consents.answerCloud(granted: yes)),
                )
              : SettingsSwitchRow(
                  label: words.cloudSaves,
                  on: false,
                  onChanged: _nothing,
                ),
        ),
        Text(
          hasServer ? words.cloudSavesExplained : words.noSaveServer,
          style: faint,
        ),
        const SizedBox(height: 8),
        KeyedSubtree(
          key: const ValueKey<String>('privacy:telemetry'),
          child: SettingsSwitchRow(
            label: words.sendMyRuns,
            on: consents.sendsRuns,
            onChanged: (bool yes) =>
                _answer(() => consents.answerTelemetry(granted: yes)),
          ),
        ),
        Text(words.sendMyRunsExplained, style: faint),
        if (_notKept)
          Text(
            words.answerNotKept,
            style: TextStyle(color: theme.error, fontSize: 12),
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
      builder: (BuildContext context) {
        final words = Flutter3dGameLocalizations.of(context);
        return AlertDialog(
          title: Text(words.whichRun),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(asked.message),
              const SizedBox(height: 12),
              _RunLine(label: words.onThisDevice, run: asked.local),
              _RunLine(label: words.inTheCloud, run: asked.remote),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(words.later),
            ),
            TextButton(
              key: const ValueKey<String>('run:remote'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(words.theClouds),
            ),
            FilledButton(
              key: const ValueKey<String>('run:local'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(words.thisDevices),
            ),
          ],
        );
      },
    );

class _RunLine extends StatelessWidget {
  const _RunLine({required this.label, required this.run});

  final String label;
  final SaveRecord? run;

  @override
  Widget build(BuildContext context) => Text(
    Flutter3dGameLocalizations.of(context).runLine(
      label,
      level: run?.level.split('/').last,
      played: switch (run) {
        final SaveRecord run => _played(run.step),
        null => null,
      },
    ),
  );

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
