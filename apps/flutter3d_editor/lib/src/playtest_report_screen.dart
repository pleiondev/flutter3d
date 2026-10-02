import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'playtest_heatmap_view.dart';
import 'playtest_report.dart';
import 'telemetry_fetch.dart';

/// `ai-02`'s screen: open a heatmap `ai-01` wrote, look at where a level
/// swallows a policy that never learns it, and tap a death for the one
/// number worth reading off it — which step, in which run.
///
/// N7 draws real players here too: the same report, fetched from a telemetry
/// server that played their runs again.
final class PlaytestReportScreen extends StatefulWidget {
  const PlaytestReportScreen({
    super.key,
    this.initialReport,
    this.levelHash,
    this.get = getText,
  });

  /// A report already loaded, for a caller that opened the file itself —
  /// what every test here hands over, since a real open panel is not
  /// something a widget test can drive.
  final PlaytestReport? initialReport;

  /// The open level's digest, offered when asking a telemetry server for its
  /// heatmap.
  final String? levelHash;

  final TextGet get;

  @override
  State<PlaytestReportScreen> createState() => _PlaytestReportScreenState();
}

final class _PlaytestReportScreenState extends State<PlaytestReportScreen> {
  PlaytestReport? _report;
  String? _said;

  /// Whether [_report] is players' runs rather than a playtest's: a marker
  /// is then a run id on the server, not a seed to play again.
  bool _fromTelemetry = false;

  final TextEditingController _server = TextEditingController(
    text: 'http://localhost:8794',
  );
  late final TextEditingController _level = TextEditingController(
    text: widget.levelHash ?? '',
  );

  @override
  void initState() {
    super.initState();
    _report = widget.initialReport;
  }

  @override
  void dispose() {
    _server.dispose();
    _level.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    const jsonFiles = XTypeGroup(
      label: 'playtest reports',
      extensions: <String>['json'],
    );
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[jsonFiles],
    );
    if (file == null) return;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      setState(() {
        _report = PlaytestReport.fromJson(json);
        _fromTelemetry = false;
        _said = null;
      });
    } catch (error) {
      setState(() => _said = 'could not read a playtest report: $error');
    }
  }

  Future<void> _fetch() async {
    final asked = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Telemetry heatmap'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              key: const ValueKey<String>('telemetry-server'),
              controller: _server,
              decoration: const InputDecoration(labelText: 'Server'),
            ),
            TextField(
              key: const ValueKey<String>('telemetry-level'),
              controller: _level,
              decoration: const InputDecoration(labelText: 'Level digest'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Fetch'),
          ),
        ],
      ),
    );
    if (asked != true || !mounted) return;
    final server = Uri.tryParse(_server.text.trim());
    if (server == null || !server.hasScheme) {
      setState(() => _said = '"${_server.text}" is not a server address');
      return;
    }
    final fetched = await fetchTelemetryHeatmap(
      server: server,
      levelHash: _level.text.trim(),
      get: widget.get,
    );
    if (!mounted) return;
    setState(() {
      _said = fetched.says;
      if (fetched.report case final report?) {
        _report = report;
        _fromTelemetry = true;
      }
    });
  }

  void _onDeathTap(DeathPoint death) {
    final where =
        '(${death.x.toStringAsFixed(1)}, ${death.z.toStringAsFixed(1)})';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _fromTelemetry ? 'A run lost, from telemetry' : 'A death, from ai-01',
        ),
        content: Text(
          _fromTelemetry
              ? 'run ${death.seed} on the server, step ${death.step}, at '
                    '$where.\n\nThe server keeps where the run went, not '
                    'what was pressed, so it cannot be played here.'
              : 'run seed ${death.seed}, step ${death.step}, at $where.\n\n'
                    'Scrubbing to this step needs a running instance of the '
                    'level\'s own genre — the editor draws where it happened, '
                    'not what led to it.',
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
    final said = _said;
    final error = TextStyle(color: Theme.of(context).colorScheme.error);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playtest report'),
        actions: <Widget>[
          IconButton(
            onPressed: _fetch,
            icon: const Icon(Icons.cloud_download),
            tooltip: 'Fetch players\' heatmap from a telemetry server',
          ),
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
                  if (said != null) ...<Widget>[
                    const SizedBox(height: 8.0),
                    Text(said, style: error),
                  ],
                ],
              ),
            )
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    '${_fromTelemetry ? 'Players: ' : ''}'
                    '${report.totalRuns} runs — ${report.outcomes.entries.map((e) => '${e.key}: ${e.value}').join(', ')}',
                  ),
                ),
                if (said != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(said),
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
