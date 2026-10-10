/// Events spoken to a screen reader: a view plugin, said once, quiet for a
/// while after.
///
///     flutter test test/spoken_events_test.dart
///
/// The bus here is a stand-in that keeps each frame subscription and hands
/// it events by hand, with the step each one came from, so the rate limit
/// is checked against steps the test chooses.
library;

import 'package:flutter3d_game_ui/access.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Hurt extends BusEvent {
  const _Hurt(this.amount);

  final double amount;

  @override
  String get name => 'test.hurt';
}

final class _Found extends BusEvent {
  const _Found();

  @override
  String get name => 'test.found';
}

/// A bus that only remembers who subscribed to what, on which channel.
final class _Events extends EventRegistry {
  final Map<String, void Function(BusEvent event, int step)> frame =
      <String, void Function(BusEvent event, int step)>{};
  final List<String> step = <String>[];

  @override
  List<EventDeclaration> get declared => const <EventDeclaration>[];

  @override
  Registration declare<T extends BusEvent>(
    String name, {
    BusChannel channel = BusChannel.step,
    String? description,
    EventCodec<T>? codec,
  }) => Registration(() {});

  @override
  Registration onFrame<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) {
    frame[label] = (BusEvent event, int step) {
      if (event is T) {
        handler(
          Delivered<T>(
            event: event,
            channel: BusChannel.frame,
            step: step,
            sequence: 0,
            resimulated: false,
          ),
        );
      }
    };
    return Registration(() => frame.remove(label));
  }

  @override
  Registration onStep<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) {
    step.add(label);
    return Registration(() {});
  }

  @override
  void publish(BusEvent event) {}

  @override
  EventRegistry forPlugin(PluginScope scope) => this;

  /// Hands [event] to every frame subscriber, as published at [at].
  void show(BusEvent event, int at) {
    for (final handler in frame.values) {
      handler(event, at);
    }
  }
}

final class _Host extends PluginHost {
  _Host(this.manifest);

  @override
  final PluginManifest manifest;

  @override
  final _Events events = _Events();

  @override
  PluginApiVersion get apiVersion => PluginApiVersion.current;

  @override
  String? get backend => null;

  @override
  LoopRegistry get loop => throw StateError('a spoken table needs no loop');

  @override
  R registry<R extends PluginRegistry>() => throw StateError('$R');

  @override
  R? maybeRegistry<R extends PluginRegistry>() => null;
}

void main() {
  final table = <Spoken<BusEvent>>[
    Spoken<_Hurt>((_Hurt hurt) => hurt.amount < 1.0 ? null : 'Hurt.'),
    Spoken<_Found>((_) => 'You found a secret.'),
  ];

  ({SpokenEvents plugin, _Events events, List<String> said}) installed({
    int quietSteps = 60,
  }) {
    final said = <String>[];
    final plugin = SpokenEvents(
      table,
      announce: said.add,
      quietSteps: quietSteps,
    );
    final host = _Host(plugin.manifest);
    plugin.install(host);
    return (plugin: plugin, events: host.events, said: said);
  }

  test('a view plugin on plugin API 1.0, on the frame channel only', () {
    final it = installed();
    final manifest = it.plugin.manifest;
    expect(manifest.idProblem, isNull);
    expect(manifest.id, startsWith('flutter3d_addon_access.'));
    // Mutation: leave `touches` at its default — the plugin claims the
    // simulation and is written into every replay.
    expect(manifest.touches, PluginTouches.view);
    expect(manifest.apiVersion, const PluginApiVersion(1, 0));
    // Mutation: subscribe with `onStep` — the sentences would be said again
    // on every rollback.
    expect(it.events.step, isEmpty);
    expect(it.events.frame, hasLength(2));
  });

  test('each event type is said in its own sentence', () {
    final it = installed();
    it.events
      ..show(const _Hurt(5.0), 10)
      ..show(const _Found(), 10);
    expect(it.said, <String>['Hurt.', 'You found a secret.']);
  });

  test('a row may decline an event of its type', () {
    final it = installed();
    // Mutation: say every event of the type — a scratch is announced.
    it.events.show(const _Hurt(0.5), 10);
    expect(it.said, isEmpty);
  });

  test('the same sentence waits out its quiet steps; another does not', () {
    final it = installed(quietSteps: 60);
    it.events
      ..show(const _Hurt(5.0), 100)
      ..show(const _Hurt(5.0), 101)
      ..show(const _Found(), 102)
      ..show(const _Hurt(5.0), 159);
    // Mutation: drop the rate limit — four sentences, three of them `Hurt.`.
    expect(it.said, <String>['Hurt.', 'You found a secret.']);
    // Sixty steps on, it is said again.
    it.events.show(const _Hurt(5.0), 160);
    // Mutation: count the quiet from the last time it was *heard* rather
    // than said — a hurt every step is never said again.
    expect(it.said.last, 'Hurt.');
    expect(it.said, hasLength(3));
  });

  test('a step from before the last sentence is not held back', () {
    final it = installed();
    it.events
      ..show(const _Hurt(5.0), 500)
      // A scrub back: the steps run from earlier again.
      ..show(const _Hurt(5.0), 20);
    // Mutation: compare without `step >= last` — a rewound run stays quiet
    // for good, since every step is behind the last one said.
    expect(it.said, <String>['Hurt.', 'Hurt.']);
  });

  test('uninstalling forgets what was said', () {
    final it = installed();
    it.events.show(const _Found(), 10);
    it.plugin.uninstall(_Host(it.plugin.manifest));
    it.events.show(const _Found(), 11);
    // Mutation: keep `_lastSaid` across a switch — switched back on, the
    // plugin is silent for a minute.
    expect(it.said, <String>['You found a secret.', 'You found a secret.']);
  });
}
