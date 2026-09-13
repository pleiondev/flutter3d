import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'timeline_client.dart';

/// `rp-02`'s panel: pause, step, preview a rewind and release, against a
/// game already running and already connected — [client] is the connection,
/// made before this screen exists, so a failed connection is a failed
/// dialog and never a half-drawn panel.
///
/// **Polls rather than streams.** The VM service extensions this talks to
/// answer a question when asked; nothing on the other end pushes a state
/// change unprompted, and adding a stream on top would be an event source
/// this screen would have to invent and the running game would have to
/// carry a listener for, for a panel that is opened at most as often as
/// somebody drags a slider. Every button here refreshes [_paused] and
/// [_history] itself when it has reason to think either changed.
final class TimelineAttachScreen extends StatefulWidget {
  const TimelineAttachScreen({super.key, required this.client});

  final TimelineClient client;

  @override
  State<TimelineAttachScreen> createState() => _TimelineAttachScreenState();
}

final class _TimelineAttachScreenState extends State<TimelineAttachScreen> {
  bool _paused = false;
  List<String> _history = const <String>[];
  TimelinePreview? _preview;
  String? _said;
  final _secondsAgo = TextEditingController(text: '3.0');

  /// `rp-06`'s strip. Null before the first load and whenever the running
  /// game registered no `StepTimeTrace` — both draw as "no data" rather than
  /// as an error, since neither is one.
  StepCosts? _frameTimes;

  /// `rp-04`. Only ever set while a save is in flight, so the button can
  /// disable itself and nobody double-taps a file picker.
  bool _savingBugReport = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _secondsAgo.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final paused = await widget.client.status();
    final history = await widget.client.history();
    // `frameTimes` is optional on the other end — a game that registered no
    // `StepTimeTrace` throws here, and that is silence, not a failure to
    // report through `_said`.
    StepCosts? frameTimes;
    try {
      frameTimes = await widget.client.frameTimes();
    } catch (_) {
      frameTimes = null;
    }
    if (!mounted) return;
    setState(() {
      _paused = paused;
      _history = history;
      _frameTimes = frameTimes;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      setState(() => _said = '$error');
    }
  }

  Future<void> _saveBugReport() async {
    setState(() => _savingBugReport = true);
    try {
      final report = await widget.client.bugReport();
      final location = await getSaveLocation(
        suggestedName: 'bugreport.json',
        acceptedTypeGroups: const <XTypeGroup>[
          XTypeGroup(label: 'bug reports', extensions: <String>['json']),
        ],
      );
      if (location == null) return;
      // Sync: this is a JSON bug report, a few kilobytes at most — not the
      // kind of write async I/O exists to keep off a frame.
      File(location.path).writeAsStringSync(jsonEncode(report));
    } catch (error) {
      if (mounted) setState(() => _said = '$error');
    } finally {
      if (mounted) setState(() => _savingBugReport = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attach: timeline')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FilledButton(
                  onPressed: () =>
                      _run(_paused ? widget.client.resume : widget.client.pause),
                  child: Text(_paused ? 'Resume' : 'Pause'),
                ),
                const SizedBox(width: 8.0),
                OutlinedButton(
                  onPressed: _paused ? () => _run(widget.client.stepOnce) : null,
                  child: const Text('Step'),
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            Row(
              children: [
                SizedBox(
                  width: 96.0,
                  child: TextField(
                    controller: _secondsAgo,
                    decoration: const InputDecoration(labelText: 'Seconds ago'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                OutlinedButton(
                  onPressed: () async {
                    final seconds = double.tryParse(_secondsAgo.text);
                    if (seconds == null) return;
                    final preview = await widget.client.preview(seconds);
                    if (!mounted) return;
                    setState(() => _preview = preview);
                  },
                  child: const Text('Preview'),
                ),
                const SizedBox(width: 16.0),
                Text(
                  switch (_preview) {
                    null => '',
                    (found: false, step: _) => 'not far enough back',
                    (found: true, step: final step) => 'at step $step',
                  },
                ),
              ],
            ),
            const SizedBox(height: 8.0),
            FilledButton.tonal(
              onPressed: _preview?.step == null
                  ? null
                  : () => _run(() async {
                      await widget.client.releaseAtStep(_preview!.step!);
                      _preview = null;
                    }),
              child: const Text('Release here'),
            ),
            if (_said != null) ...[
              const SizedBox(height: 8.0),
              Text(_said!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16.0),
            Row(
              children: [
                const Text('Frame times'),
                const SizedBox(width: 8.0),
                OutlinedButton(
                  onPressed: _savingBugReport ? null : _saveBugReport,
                  child: const Text('Save bug report'),
                ),
              ],
            ),
            const SizedBox(height: 4.0),
            _FrameTimeStrip(
              costs: _frameTimes,
              onTapStep: (step) =>
                  _run(() async => widget.client.releaseAtStep(step)),
            ),
            const SizedBox(height: 16.0),
            const Text('History'),
            Expanded(
              child: ListView(
                children: [for (final line in _history) Text(line)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `rp-06`'s strip: one bar per step `ext.flutter3d.timeline.frameTimes`
/// reported, tall as its cost was relative to the worst step in the trace.
/// Tapping a bar jumps the timeline there — the same
/// [TimelineClient.releaseAtStep] the "Release here" button already uses,
/// so a slow step found by eye is a rewind away rather than a number to
/// copy into the "seconds ago" field.
final class _FrameTimeStrip extends StatelessWidget {
  const _FrameTimeStrip({required this.costs, required this.onTapStep});

  final StepCosts? costs;
  final ValueChanged<int> onTapStep;

  static const double _height = 40.0;

  @override
  Widget build(BuildContext context) {
    final costs = this.costs;
    if (costs == null || costs.steps.isEmpty) {
      return const SizedBox(
        height: _height,
        child: Center(child: Text('no frame times yet', style: TextStyle(fontSize: 12))),
      );
    }
    final worst = costs.millis.fold<double>(0.0, (a, b) => a > b ? a : b);
    return SizedBox(
      height: _height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < costs.steps.length; i++)
            GestureDetector(
              key: ValueKey<int>(costs.steps[i]),
              onTap: () => onTapStep(costs.steps[i]),
              child: Tooltip(
                message: 'step ${costs.steps[i]}: ${costs.millis[i].toStringAsFixed(2)}ms',
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 3.0,
                    margin: const EdgeInsets.symmetric(horizontal: 0.5),
                    height: worst <= 0
                        ? 2.0
                        : (_height * costs.millis[i] / worst).clamp(2.0, _height),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
