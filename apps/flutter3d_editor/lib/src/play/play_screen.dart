/// `HR5`'s panel: the project running, its console, and the four things
/// done to it — start, hot reload, hot restart, stop — plus the timeline of
/// the game it started and the device it runs on.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_play/flutter3d_editor_play.dart';

/// Shows [run] and drives it.
///
/// **A view of the run, not its owner.** The editor keeps [run] for as long
/// as the project is open, so closing this screen leaves the game running and
/// opening it again finds the same console — the way a terminal tab with
/// `flutter run` in it would behave.
final class PlayScreen extends StatefulWidget {
  const PlayScreen({
    super.key,
    required this.run,
    required this.onTimeline,
    this.devices = flutterDevices,
  });

  final FlutterRun run;

  /// Opens the timeline panel on the running game's VM service.
  final void Function(String vmService) onTimeline;

  /// What the device picker offers; `flutter devices --machine` by default.
  final Future<List<FlutterDevice>> Function() devices;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  static const Color _background = Color(0xFF14161A);
  static const Color _text = Color(0xFFE6EAF0);

  /// Asked once per opening of the panel: the tool takes a second or two to
  /// answer, and a phone plugged in afterwards is found by opening it again.
  late final Future<List<FlutterDevice>> _devices = widget.devices();

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    return StreamBuilder<PlayState>(
      stream: run.state.changes,
      initialData: run.state.value,
      builder: (BuildContext context, _) {
        final state = run.state.value;
        final running = state is PlayRunning;
        final going = state is PlayStarting || running;
        return Scaffold(
          backgroundColor: _background,
          appBar: AppBar(
            title: Text(run.projectRoot, overflow: TextOverflow.ellipsis),
            actions: <Widget>[
              _picker(enabled: !going),
              IconButton(
                key: const ValueKey<String>('play.start'),
                icon: Icon(going ? Icons.stop : Icons.play_arrow),
                tooltip: going ? 'Stop' : 'Run the project',
                onPressed: going ? run.stop : run.start,
              ),
              IconButton(
                key: const ValueKey<String>('play.reload'),
                icon: const Icon(Icons.bolt),
                tooltip: 'Hot reload',
                onPressed: running ? run.hotSwap : null,
              ),
              IconButton(
                key: const ValueKey<String>('play.restart'),
                icon: const Icon(Icons.restart_alt),
                tooltip: 'Hot restart',
                onPressed: running ? run.hotRestart : null,
              ),
              IconButton(
                key: const ValueKey<String>('play.timeline'),
                icon: const Icon(Icons.podcasts),
                tooltip: 'Timeline',
                onPressed: switch (state) {
                  PlayRunning(:final vmService) => () => widget.onTimeline(
                    vmService,
                  ),
                  _ => null,
                },
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Text(
                  switch (state) {
                    PlayIdle() => 'Not running',
                    PlayStarting(:final message) => message,
                    PlayRunning(:final vmService) => 'Running, $vmService',
                    PlayStopped(:final exitCode) => 'Stopped ($exitCode)',
                  },
                  key: const ValueKey<String>('play.status'),
                  style: const TextStyle(color: _text),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<String>>(
                  stream: run.console.changes,
                  initialData: run.console.value,
                  // Reversed, so the newest line sits at the bottom and the
                  // list stays there as lines arrive, as a terminal does.
                  builder: (BuildContext context, _) {
                    final lines = run.console.value;
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: lines.length,
                      itemBuilder: (BuildContext context, int index) =>
                          SelectableText(
                            lines[lines.length - 1 - index],
                            style: const TextStyle(
                              color: _text,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Which device the next run starts on. Held still while a run is going:
  /// the device is `flutter run`'s argument, and changing it means a new run.
  Widget _picker({required bool enabled}) => FutureBuilder<List<FlutterDevice>>(
    future: _devices,
    builder: (BuildContext context, AsyncSnapshot<List<FlutterDevice>> it) {
      final devices = it.data ?? const <FlutterDevice>[];
      final chosen = widget.run.device;
      return DropdownButton<String?>(
        key: const ValueKey<String>('play.device'),
        value: devices.any((d) => d.id == chosen) ? chosen : null,
        dropdownColor: _background,
        style: const TextStyle(color: _text, fontSize: 13),
        underline: const SizedBox.shrink(),
        hint: Text(
          it.hasError ? 'devices unavailable' : 'default device',
          style: const TextStyle(color: _text, fontSize: 13),
        ),
        items: <DropdownMenuItem<String?>>[
          const DropdownMenuItem<String?>(child: Text('default device')),
          for (final device in devices)
            DropdownMenuItem<String?>(
              value: device.id,
              child: Text(device.name),
            ),
        ],
        onChanged: enabled
            ? (String? id) => setState(() => widget.run.device = id)
            : null,
      );
    },
  );
}
