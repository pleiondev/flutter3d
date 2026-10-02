/// `HR5`'s panel: the game being played, its console, and the four things
/// done to it — start, hot reload, hot restart, stop — plus its timeline and,
/// for a game the editor started, the device it runs on.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_editor_play/attach.dart';

/// Shows [session] and drives it.
///
/// **A view of the session, not its owner.** The editor keeps [session] for
/// as long as the project is open, so closing this screen leaves the game
/// running and opening it again finds the same console — the way a terminal
/// tab with `flutter run` in it would behave.
///
/// **No `dart:io` here.** The same panel shows a game the editor attached to
/// by its VM service address, which is the only Play a browser has; what
/// needs a process — the device picker — comes in as [picker] from a file
/// that is allowed one.
final class PlayScreen extends StatefulWidget {
  const PlayScreen({
    super.key,
    required this.session,
    required this.onTimeline,
    this.picker,
  });

  final PlayedGame session;

  /// Opens the timeline panel on the running game's VM service.
  final void Function(String vmService) onTimeline;

  /// What chooses the device the next run starts on, enabled between runs;
  /// none for a game somebody else started.
  final Widget Function({required bool enabled})? picker;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  static const Color _background = Color(0xFF14161A);
  static const Color _text = Color(0xFFE6EAF0);

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final owns = session.ownsTheGame;
    return StreamBuilder<PlayState>(
      stream: session.state.changes,
      initialData: session.state.value,
      builder: (BuildContext context, _) {
        final state = session.state.value;
        final running = state is PlayRunning;
        final going = state is PlayStarting || running;
        return Scaffold(
          backgroundColor: _background,
          appBar: AppBar(
            title: Text(session.title, overflow: TextOverflow.ellipsis),
            actions: <Widget>[
              ?widget.picker?.call(enabled: !going),
              IconButton(
                key: const ValueKey<String>('play.start'),
                icon: Icon(switch ((going, owns)) {
                  (true, true) => Icons.stop,
                  (true, false) => Icons.link_off,
                  (false, true) => Icons.play_arrow,
                  (false, false) => Icons.link,
                }),
                tooltip: switch ((going, owns)) {
                  (true, true) => 'Stop',
                  (true, false) => 'Detach (the game keeps running)',
                  (false, true) => 'Run the project',
                  (false, false) => 'Attach again',
                },
                onPressed: going ? session.stop : session.start,
              ),
              IconButton(
                key: const ValueKey<String>('play.reload'),
                icon: const Icon(Icons.bolt),
                tooltip: 'Hot reload',
                onPressed: running ? session.hotSwap : null,
              ),
              IconButton(
                key: const ValueKey<String>('play.restart'),
                icon: const Icon(Icons.restart_alt),
                tooltip: 'Hot restart',
                onPressed: running ? session.hotRestart : null,
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
                    PlayIdle() => owns ? 'Not running' : 'Not attached',
                    PlayStarting(:final message) => message,
                    PlayRunning(:final vmService) =>
                      owns ? 'Running, $vmService' : 'Attached, $vmService',
                    PlayStopped(:final String reason) => reason,
                    PlayStopped(:final exitCode) => 'Stopped ($exitCode)',
                  },
                  key: const ValueKey<String>('play.status'),
                  style: const TextStyle(color: _text),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<String>>(
                  stream: session.console.changes,
                  initialData: session.console.value,
                  // Reversed, so the newest line sits at the bottom and the
                  // list stays there as lines arrive, as a terminal does.
                  builder: (BuildContext context, _) {
                    final lines = session.console.value;
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
}
