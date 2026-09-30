/// `HR5`'s panel: the project running, its console, and the four things
/// done to it — start, hot reload, hot restart, stop — plus the timeline of
/// the game it started.
library;

import 'package:flutter/material.dart';

import 'flutter_run.dart';

/// Shows [run] and drives it.
///
/// **A view of the run, not its owner.** The editor keeps [run] for as long
/// as the project is open, so closing this screen leaves the game running and
/// opening it again finds the same console — the way a terminal tab with
/// `flutter run` in it would behave.
final class PlayScreen extends StatelessWidget {
  const PlayScreen({super.key, required this.run, required this.onTimeline});

  final FlutterRun run;

  /// Opens the timeline panel on the running game's VM service.
  final void Function(String vmService) onTimeline;

  static const Color _background = Color(0xFF14161A);
  static const Color _text = Color(0xFFE6EAF0);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PlayState>(
    valueListenable: run.state,
    builder: (BuildContext context, PlayState state, _) {
      final running = state is PlayRunning;
      final going = state is PlayStarting || running;
      return Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          title: Text(run.projectRoot, overflow: TextOverflow.ellipsis),
          actions: <Widget>[
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
              onPressed: running ? run.hotReload : null,
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
                PlayRunning(:final vmService) => () => onTimeline(vmService),
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
              child: ValueListenableBuilder<List<String>>(
                valueListenable: run.console,
                // Reversed, so the newest line sits at the bottom and the list
                // stays there as lines arrive, as a terminal does.
                builder: (BuildContext context, List<String> lines, _) =>
                    ListView.builder(
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
                    ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
