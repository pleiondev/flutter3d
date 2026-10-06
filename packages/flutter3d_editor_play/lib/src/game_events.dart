/// What a running game posted about itself — a level up, the player dead, a
/// pickup taken — as the editor keeps it.
library;

import 'dart:async';

import 'package:vm_service/vm_service.dart';

import 'play_state.dart';
import 'watched.dart';

/// One event a game posted with `flutter3d_game`'s `postGameEvent`.
final class PostedEvent {
  const PostedEvent({
    required this.sequence,
    required this.kind,
    required this.time,
    required this.data,
  });

  /// Its place among everything the game posted while the editor listened,
  /// from 1, with no gaps: the cursor an agent polls with.
  final int sequence;

  /// What happened, **without** the `flutter3d.` every kind is posted under —
  /// `level.loaded`, `player.died` — the name the game wrote at the call.
  /// The prefix is how the editor tells the game's events from everything
  /// else on the stream; once inside it says nothing.
  final String kind;

  /// When the VM stamped it; null from a VM that did not.
  final DateTime? time;

  /// What the game said about it, as it posted it.
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => <String, Object?>{
    'sequence': sequence,
    'kind': kind,
    'time': time?.toUtc().toIso8601String(),
    'data': data,
  };
}

/// The events a game posted, numbered as they arrive and capped at [limit],
/// dropping the oldest, the way the console is.
///
/// One of these per [PlayedGame], kept across its runs: the numbering goes
/// on through a stop and a start, so a cursor taken before the restart still
/// points at what came after it.
final class GameEventLog {
  static const String prefix = 'flutter3d.';
  static const int limit = 2000;

  final Watched<List<PostedEvent>> events = Watched<List<PostedEvent>>(
    const <PostedEvent>[],
  );

  int _last = 0;

  /// Listens to [service]'s `Extension` stream, where `postEvent` goes, and
  /// keeps what [take] keeps. The subscription is the caller's to cancel.
  Future<StreamSubscription<Event>> listenTo(VmService service) async {
    final listening = service.onExtensionEvent.listen(take);
    try {
      await service.streamListen(EventStreams.kExtension);
    } on RPCError {
      // Already listened to on this connection, or a VM without the stream:
      // then there are no events to keep, and nothing else is lost.
    }
    return listening;
  }

  /// Keeps [event] when the game posted it: an `Extension` event whose kind
  /// starts with [prefix]. Flutter's own (`Flutter.Frame`, `Flutter.Navigation`)
  /// and everything else on the stream are left out.
  void take(Event event) {
    final kind = event.extensionKind;
    if (kind == null || !kind.startsWith(prefix)) return;
    events.value = appendCapped(
      events.value,
      PostedEvent(
        sequence: ++_last,
        kind: kind.substring(prefix.length),
        time: switch (event.timestamp) {
          final int stamp => DateTime.fromMillisecondsSinceEpoch(stamp),
          null => null,
        },
        data: event.extensionData?.data ?? const <String, Object?>{},
      ),
      limit,
    );
  }

  Future<void> close() => events.close();
}

/// The events of [events] after the cursor [since], of [kinds] only when it
/// is given, and the cursor to ask with next.
///
/// **The next cursor is the last event kept, not the last one returned**, so
/// a filter that leaves events out does not bring them back on the next
/// call. [missed] counts the events after [since] that the cap dropped
/// before anyone asked; [restarted] is true when [since] is past the last
/// event there is — a cursor from a run that has since been replaced by a
/// new one, numbered from 1 again — and the answer then starts from the
/// beginning rather than waiting for the new run to catch the old one up.
({List<PostedEvent> events, int next, int missed, bool restarted}) eventsSince(
  List<PostedEvent> events,
  int since, {
  Set<String>? kinds,
}) {
  final last = events.isEmpty ? 0 : events.last.sequence;
  final restarted = since > last;
  final from = restarted ? 0 : since;
  final first = events.isEmpty ? from + 1 : events.first.sequence;
  return (
    events: <PostedEvent>[
      for (final event in events)
        if (event.sequence > from &&
            (kinds == null || kinds.contains(event.kind)))
          event,
    ],
    next: events.isEmpty ? from : last,
    missed: first > from + 1 ? first - from - 1 : 0,
    restarted: restarted,
  );
}
