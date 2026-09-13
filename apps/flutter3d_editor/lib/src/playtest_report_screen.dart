import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'playtest_heatmap_view.dart';
import 'playtest_report.dart';

/// `ai-02`'s screen: open a heatmap `ai-01` wrote, look at where a level
/// swallows a policy that never learns it, and tap a death for the one
/// number worth reading off it — which step, in which run.
final class PlaytestReportScreen extends StatefulWidget {
  const PlaytestReportScreen({super.key, this.initialReport});

  /// A report already loaded, for a caller that opened the file itself —
  /// what every test here hands over, since a real open panel is not
  /// something a widget test can drive.
  final PlaytestReport? initialReport;

  @override
  State<PlaytestReportScreen> createState() => _PlaytestReportScreenState();
}

final class _PlaytestReportScreenState extends State<PlaytestReportScreen> {
  PlaytestReport? _report;
  String? _said;

  @override
  void initState() {
    super.initState();
    _report = widget.initialReport;
  }

  Future<void> _open() async {
    const jsonFiles = XTypeGroup(label: 'playtest reports', extensions: <String>['json']);
    final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[jsonFiles]);
    if (file == null) return;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      setState(() {
        _report = PlaytestReport.fromJson(json);
        _said = null;
      });
    } catch (error) {
      setState(() => _said = 'could not read a playtest report: $error');
    }
  }

  void _onDeathTap(DeathPoint death) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('A death, from ai-01'),
        content: Text(
          'run seed ${death.seed}, step ${death.step}, at '
          '(${death.x.toStringAsFixed(1)}, ${death.z.toStringAsFixed(1)}).\n\n'
          'Scrubbing to this step needs a running instance of the level\'s '
          'own genre — the editor draws where it happened, not what led to '
          'it.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playtest report'),
        actions: <Widget>[
          IconButton(
            onPressed: _open,
            icon: const Icon(Icons.folder_open),
            tooltip: 'Open a heatmap from ai-01',
          ),
        ],
      ),
      body: report == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('No report open.'),
                  if (_said != null) ...<Widget>[
                    const SizedBox(height: 8.0),
                    Text(_said!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            )
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    '${report.totalRuns} runs — ${report.outcomes.entries.map((e) => '${e.key}: ${e.value}').join(', ')}',
                  ),
                ),
                Expanded(
                  child: PlaytestHeatmapView(
                    report: report,
                    onDeathTap: _onDeathTap,
                  ),
                ),
              ],
            ),
    );
  }
}
