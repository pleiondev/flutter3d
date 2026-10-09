import 'package:flutter3d_audio_core/flutter3d_audio_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart' show BusEvent;

/// What one cue of a [CueSheet] makes of an event of type [T]: the sounds it
/// adds to [out].
typedef Cue<T extends BusEvent> = void Function(T event, List<Heard> out);

/// Sounds keyed by event type: a game's own sheet of what each event sounds
/// like.
///
/// **The game decides; this only keeps the decisions in one place.** A cue is
/// registered for an event class and is handed every event of that class and
/// its subclasses, in the order the events happened; an event no cue names is
/// silence. Within one event, cues run in registration order, so a sheet
/// written as a list sounds the way a `switch` over the events did.
///
/// **Deciding, not playing.** What a step sounds like is a fact about the
/// simulation and can be asserted with no device — which is how both games
/// that split this out found real silence: six sounds missing from one bank,
/// four weapons sharing two sounds in the other. Playing is a
/// `SoundtrackPlugin`'s or the game's own.
///
/// ```dart
/// final cues = CueSheet()
///   ..on<Jumped>((e, out) => out.add(Heard(Sounds.jump, e.at)))
///   ..on<DoorLocked>((e, out) => out.add(Heard(Sounds.locked, e.at)));
/// for (final heard in cues.listen(events)) scene.play(heard.sound, heard.at);
/// ```
final class CueSheet {
  final List<_Row> _rows = <_Row>[];

  /// Adds [cue] for every event that is a [T].
  void on<T extends BusEvent>(Cue<T> cue) {
    _rows.add(
      _Row(T, (BusEvent event, List<Heard> out) {
        if (event is T) cue(event, out);
      }),
    );
  }

  /// The event types this sheet has a cue for, in registration order.
  List<Type> get types => <Type>[for (final row in _rows) row.type];

  /// Adds what [events] sound like to [out].
  void hear(Iterable<BusEvent> events, List<Heard> out) {
    for (final event in events) {
      for (final row in _rows) {
        row.apply(event, out);
      }
    }
  }

  /// What [events] sound like.
  List<Heard> listen(Iterable<BusEvent> events) {
    final out = <Heard>[];
    hear(events, out);
    return out;
  }
}

final class _Row {
  const _Row(this.type, this.apply);

  final Type type;
  final void Function(BusEvent event, List<Heard> out) apply;
}
