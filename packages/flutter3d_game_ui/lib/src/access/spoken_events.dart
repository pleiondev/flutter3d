import 'dart:ui' show FlutterView;

import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter/widgets.dart'
    show BuildContext, Directionality, TextDirection, View, WidgetsBinding;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// Where a sentence goes to be read out.
typedef Announce = void Function(String sentence);

/// One row of a [SpokenEvents] table: an event type, and what is said when
/// one arrives.
///
/// [say] answers null for an event of the type that is not worth a sentence
/// — a scratch, a door that was already open — so one row can cover a type
/// and still be choosy about it.
final class Spoken<T extends BusEvent> {
  const Spoken(this.say);

  final String? Function(T event) say;

  Registration _listen(
    EventRegistry events,
    String label,
    void Function(String? sentence, int step) heard,
  ) => events.onFrame<T>(
    label,
    (Delivered<T> delivered) => heard(say(delivered.event), delivered.step),
  );
}

/// Events spoken to a screen reader: what happened in the game, said aloud
/// through the platform's own reader as it happens.
///
/// **A view plugin on the bus's frame channel.** It reads events after the
/// frame's steps, once each, with a step run again on a rollback reconciled
/// rather than said twice, and it writes nothing back: a sighted player's
/// game is the same frame for frame with it installed. It is not written
/// into a replay.
///
/// **Through Flutter's semantics, not a voice of its own.** A sentence is an
/// announcement on the view ([SemanticsService.sendAnnouncement]), so it is
/// read by whatever the player already uses — VoiceOver, TalkBack, Narrator,
/// Orca — in their voice and at their rate, and goes nowhere when nothing is
/// listening.
///
/// **Rate-limited by step, not by clock.** The same sentence is not said
/// again within [quietSteps] steps of the last time, so a hurt that lands
/// every step of a fire is one sentence, not sixty a second. A different
/// sentence is said at once. Steps rather than seconds, so the limit is the
/// same on a replay and needs no clock.
///
/// ```dart
/// final loop = EngineLoop(
///   input: input,
///   plugins: <Flutter3dPlugin>[
///     genre,
///     SpokenEvents(<Spoken<BusEvent>>[
///       Spoken<PlayerDied>((_) => 'You died.'),
///       Spoken<SecretFound>((_) => 'You found a secret.'),
///     ]),
///   ],
/// );
/// ```
final class SpokenEvents extends Flutter3dPlugin {
  SpokenEvents(
    List<Spoken<BusEvent>> table, {
    Announce? announce,
    this.quietSteps = 60,
    this.id = 'flutter3d_addon_access.spoken_events',
  }) : table = List<Spoken<BusEvent>>.unmodifiable(table),
       _announce = announce ?? announceToImplicitView();

  /// The rows, in the order their subscriptions are made.
  final List<Spoken<BusEvent>> table;

  /// How many steps the same sentence stays unsaid after it is said.
  final int quietSteps;

  /// The plugin's id: the default, or another for a second table in one
  /// engine.
  final String id;

  final Announce _announce;

  final Map<String, int> _lastSaid = <String, int>{};

  @override
  PluginManifest get manifest => PluginManifest(
    id: id,
    apiVersion: const PluginApiVersion(1, 0),
    touches: PluginTouches.view,
    description: 'What happens in the game, said to a screen reader.',
  );

  @override
  void install(PluginHost host) {
    for (var i = 0; i < table.length; i++) {
      table[i]._listen(host.events, '$id.$i', _heard);
    }
  }

  @override
  void uninstall(PluginHost host) => _lastSaid.clear();

  void _heard(String? sentence, int step) {
    if (sentence == null || sentence.isEmpty) return;
    final last = _lastSaid[sentence];
    if (last != null && step >= last && step - last < quietSteps) return;
    _lastSaid[sentence] = step;
    _announce(sentence);
  }
}

/// An [Announce] that speaks on [view], as a polite announcement in
/// [direction] — the platform's own when not given, see
/// [platformTextDirection].
Announce announceTo(FlutterView view, {TextDirection? direction}) =>
    (String sentence) => SemanticsService.sendAnnouncement(
      view,
      sentence,
      direction ?? platformTextDirection(),
    );

/// An [Announce] that speaks on the view [context] is in, in the direction
/// its text runs there — the ambient [Directionality], which is the one the
/// app already lays its words out in.
///
/// Read once, when this is called: the announcement itself happens later,
/// outside any build, where there is no context to ask.
Announce announceIn(BuildContext context) => announceTo(
  View.of(context),
  direction: Directionality.maybeOf(context) ?? platformTextDirection(),
);

/// An [Announce] that speaks on the application's implicit view, looked up
/// each time; with none (a multi-view embedding) it says nothing. The
/// default of [SpokenEvents], for a game with one window.
///
/// [direction] is the platform's own by default, read at each announcement
/// — see [platformTextDirection] — rather than left to right: a sentence in
/// Arabic or Hebrew read as left to right is read in the wrong order. A game
/// that lays its text out in another direction than the platform's builds
/// its [Announce] with [announceIn] instead.
Announce announceToImplicitView({TextDirection? direction}) =>
    (String sentence) {
      final view = WidgetsBinding.instance.platformDispatcher.implicitView;
      if (view != null) {
        SemanticsService.sendAnnouncement(
          view,
          sentence,
          direction ?? platformTextDirection(),
        );
      }
    };

/// The direction text runs in the platform's own language: right to left
/// for the scripts written that way, left to right for everything else.
TextDirection platformTextDirection() =>
    _rightToLeft.contains(
      WidgetsBinding.instance.platformDispatcher.locale.languageCode,
    )
    ? TextDirection.rtl
    : TextDirection.ltr;

/// The languages whose script runs right to left.
const Set<String> _rightToLeft = <String>{
  'ar',
  'dv',
  'fa',
  'he',
  'iw',
  'ku',
  'ps',
  'sd',
  'ug',
  'ur',
  'yi',
};
