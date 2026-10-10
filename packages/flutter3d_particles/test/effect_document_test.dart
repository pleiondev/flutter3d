/// `.f3dfx`, the effect document, and `ParticleEffects`, which installs it.
///
///     dart test test/effect_document_test.dart
///
/// The v1 fixture is `test/fixtures/v1/blast.f3dfx`, minted when the format
/// was: every key version 1 has is in it, and it must keep reading for as
/// long as 1.x does (decision 8 of `tasks/1.0-stability.md`).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show PlacedEvent;
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

EffectDocument _fixture() => EffectDocument.parse(
  File('test/fixtures/v1/blast.f3dfx').readAsStringSync(),
  from: 'blast.f3dfx',
);

/// [effect] burst once at the origin and stepped [seconds], as the bytes a
/// mesh draw would read: position, colour and size of every live particle.
Float32List _burstAndRun(
  ParticleEffect effect, {
  double seconds = 0.5,
  double gravity = 9.81,
}) {
  final system = ParticleSystem(capacity: 512, seed: 7)..gravity = gravity;
  system.burst(effect, Vector3(0.0, 1.0, 0.0), direction: Vector3(0, 1, 0));
  // A frame at a time: one `advance` takes at most eight sub-steps.
  for (var t = 0.0; t < seconds; t += 1.0 / 60.0) {
    system.advance(1.0 / 60.0);
  }
  final out = Float32List(512 * ParticleSystem.floatsPerInstance);
  final count = system.writeInstances(out);
  return Float32List.sublistView(
    out,
    0,
    count * ParticleSystem.floatsPerInstance,
  );
}

Matcher _refusal(String saying) => throwsA(
  isA<EffectFormatException>().having(
    (e) => e.message,
    'message',
    contains(saying),
  ),
);

Map<String, Object?> _one(Map<String, Object?> effect) => <String, Object?>{
  'f3dfx': 1,
  'effects': <Object?>[
    <String, Object?>{
      'name': 'puff',
      'lifetime': 1.0,
      'size': 0.1,
      'color': <double>[1.0, 1.0, 1.0],
      'emitter': <String, Object?>{'shape': 'sphere'},
      ...effect,
    },
  ],
};

/// What the bus does with a frame subscription, and nothing else.
final class _Bus extends EventRegistry {
  final List<(String, EventHandler<BusEvent>)> frame =
      <(String, EventHandler<BusEvent>)>[];

  void show(BusEvent event) {
    for (final (_, handler) in List.of(frame)) {
      handler(
        Delivered<BusEvent>(
          event: event,
          channel: BusChannel.frame,
          step: 0,
          sequence: 0,
          resimulated: false,
        ),
      );
    }
  }

  @override
  Registration declare<T extends BusEvent>(
    String name, {
    BusChannel channel = BusChannel.step,
    String? description,
    EventCodec<T>? codec,
  }) => Registration(() {});

  @override
  Registration onStep<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => Registration(() {});

  @override
  Registration onFrame<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) {
    final entry = (label, handler as EventHandler<BusEvent>);
    frame.add(entry);
    return Registration(() => frame.remove(entry));
  }

  @override
  void publish(BusEvent event) => show(event);

  @override
  List<EventDeclaration> get declared => const <EventDeclaration>[];

  @override
  EventRegistry forPlugin(PluginScope scope) => this;
}

final class _Blast extends BusEvent implements PlacedEvent {
  _Blast(this.at);

  @override
  final Vector3 at;

  @override
  Vector3? get direction => null;

  @override
  String get name => 'elements.exploded';
}

final class _Named extends BusEvent {
  const _Named(this.name);

  @override
  final String name;
}

final class _Scope extends PluginScope {
  final List<Registration> tracked = <Registration>[];

  @override
  PluginManifest get manifest => const PluginManifest(
    id: 'fireworks',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.view,
  );

  @override
  int get rank => 0;

  @override
  void track(Registration registration) => tracked.add(registration);
}

void main() {
  group('the document', () {
    test('the v1 fixture reads, every key in its place', () {
      // Mutation: drop a key from the reader, or read a default where the
      // document says something. The fixture holds every key version 1 has.
      final document = _fixture();
      expect(document.effects.map((e) => e.name), <String>[
        'core',
        'debris',
        'smoke',
        'glow',
      ]);

      final core = document['core']!;
      expect(core.description, contains('bright core'));
      expect(core.effect.count, 90);
      expect(core.effect.lifetime.min, 0.25);
      expect(core.effect.lifetime.max, 0.6);
      expect(core.effect.emitter, isA<SphereEmitter>());
      expect(core.effect.affectors.map((a) => a.runtimeType), <Type>[
        ParticleDrag,
        ParticleGravity,
        ParticleColorOverLife,
        ParticleSizeOverLife,
        ParticleFade,
      ]);
      expect(core.render.drawing, EffectDrawing.billboard);
      expect(core.render.blend, EffectBlend.additive);
      expect(core.render.texture, 'spark.png');
      expect(core.render.flipbook!.frameCount, 14);
      expect(core.render.softness, 0.3);
      expect(core.triggers.single.event, 'elements.exploded');
      expect(core.triggers.single.spawn, EffectSpawn.burst);

      final debris = document['debris']!;
      expect(debris.effect.lifetime.min, debris.effect.lifetime.max);
      expect(debris.effect.color.w, 1.0, reason: 'RGB alone is opaque');
      expect(debris.render.drawing, EffectDrawing.mesh);
      expect(debris.render.blend, EffectBlend.darkening);
      expect(debris.render.mesh, 'chip');
      expect(
        (debris.effect.affectors.first as ParticleGravity).acceleration,
        isNull,
        reason: 'a gravity with no acceleration is the world\'s',
      );
      expect(debris.effect.affectors[1], isA<ParticlePlaneCollision>());
      expect(debris.effect.affectors.last, isA<ParticleSpin>());
      expect(
        (debris.effect.affectors.last as ParticleSpin).randomizeStart,
        isFalse,
      );
      expect(debris.effect.affectors, hasLength(3), reason: 'depth is not one');
      expect(debris.unsupported.single, contains('depth'));
      expect(debris.triggers.single.direction, Vector3(0.0, 1.0, 0.0));

      final smoke = document['smoke']!;
      expect(smoke.rate, 34.0);
      expect(smoke.effect.emitter, isA<BoxEmitter>());
      expect(smoke.render.drawing, EffectDrawing.sixWay);
      expect(smoke.render.blend, EffectBlend.over);
      expect(smoke.render.sheet!.negative, 'smoke_lbf.png');
      expect(smoke.triggers.single.spawn, EffectSpawn.timed);
      expect(smoke.triggers.single.seconds, 0.85);

      final glow = document['glow']!;
      expect(glow.effect.emitter, isA<DriftEmitter>());
      expect(glow.effect.affectors.single, isA<ParticleColorGradient>());
      final gradient =
          (glow.effect.affectors.single as ParticleColorGradient).gradient;
      expect(gradient.keys.map((k) => k.ease.name), <String>[
        'smooth',
        'step',
        'linear',
      ]);
      expect(glow.triggers.single.at, Vector3(0.0, 2.0, 0.0));
      expect(glow.triggers.single.perSecond, 60.0);
    });

    test('what this build does not know is kept and written back', () {
      // Mutation: build `toJson` from the known keys alone. A tool that reads
      // a document and writes it back strips a later minor's keys.
      final document = _fixture();
      expect(document.extra, <String, Object?>{'author': 'flutter3d fixtures'});
      final again = EffectDocument.fromJson(document.toJson());
      expect(jsonEncode(again.toJson()), jsonEncode(document.toJson()));
      expect(
        (again.toJson()['effects']! as List<Object?>).first,
        containsPair('editor', <String, Object?>{'colour': 'orange'}),
      );
    });

    test('a document from a newer engine is refused, saying which', () {
      // Mutation: gate on equality with the version this build writes. Every
      // older document would be refused too; this one is refused for being
      // newer, and says so.
      expect(
        () => EffectDocument.fromJson(<String, Object?>{
          'f3dfx': EffectDocument.formatVersion + 1,
          'effects': <Object?>[],
        }),
        // The format's own sentence (`FormatSpec.open`): "… is newer than
        // this build reads (2): update flutter3d to open it".
        _refusal('newer than this build reads'),
      );
      expect(
        () => EffectDocument.parse('{"effects": []}'),
        _refusal('has no version in it'),
      );
      expect(() => EffectDocument.parse('[1]'), _refusal('not a JSON object'));
    });

    test('each mistake is named, with the effect it is in', () {
      expect(
        () => EffectDocument.fromJson(
          _one(<String, Object?>{
            'affectors': <Object?>[
              <String, Object?>{'type': 'vortex'},
            ],
          }),
        ),
        _refusal('effect "puff": the affector "type" is vortex'),
      );
      expect(
        () => EffectDocument.fromJson(
          _one(<String, Object?>{
            'render': <String, Object?>{'blend': 'darkening'},
          }),
        ),
        _refusal('a billboard is drawn additive, not darkening'),
      );
      expect(
        () => EffectDocument.fromJson(
          _one(<String, Object?>{
            'render': <String, Object?>{
              'flipbook': <String, Object?>{'columns': 2, 'rows': 2},
            },
          }),
        ),
        _refusal('a "flipbook" is a grid of a "texture"'),
      );
      expect(
        () => EffectDocument.fromJson(
          _one(<String, Object?>{
            'render': <String, Object?>{
              'drawing': 'mesh',
              'mesh': 'chip',
              'softness': 0.2,
            },
          }),
        ),
        _refusal('soft particles are billboards and sheets'),
      );
      expect(
        () => EffectDocument.fromJson(
          _one(<String, Object?>{
            'affectors': <Object?>[
              <String, Object?>{
                'type': 'sizeCurve',
                'keys': <Object?>[
                  <String, Object?>{'at': 0.5, 'value': 1.0},
                  <String, Object?>{'at': 0.2, 'value': 2.0},
                ],
              },
            ],
          }),
        ),
        _refusal('ordered by "at"'),
      );
      expect(
        () => EffectDocument.fromJson(
          _one(<String, Object?>{
            'on': <Object?>[
              <String, Object?>{'event': 'boom', 'emit': 'timed'},
            ],
          }),
        ),
        _refusal('says for how many "seconds"'),
      );
      expect(
        () => EffectDocument.fromJson(
          _one(<String, Object?>{
            'size': <double>[2.0, 1.0],
          }),
        ),
        _refusal('write the smaller first'),
      );
      expect(
        () => EffectDocument.fromJson(<String, Object?>{
          'f3dfx': 1,
          'effects': <Object?>[
            ..._one(const <String, Object?>{})['effects']! as List<Object?>,
            ..._one(const <String, Object?>{})['effects']! as List<Object?>,
          ],
        }),
        _refusal('two effects are called "puff"'),
      );
    });

    test('a game\'s own words are read through its vocabulary', () {
      // Mutation: ignore the vocabulary. A document naming a game's affector
      // is refused, or loses it.
      final vocabulary = EffectVocabulary(
        affectors: <String, EffectAffectorReader>{
          'vortex': (json) =>
              ParticleWind(Vector3((json['pull']! as num).toDouble(), 0, 0)),
        },
        eases: const <KeyEase>[KeyEase('late', _late)],
      );
      final document = EffectDocument.fromJson(
        _one(<String, Object?>{
          'affectors': <Object?>[
            <String, Object?>{'type': 'vortex', 'pull': 2.0},
            <String, Object?>{
              'type': 'sizeCurve',
              'keys': <Object?>[
                <String, Object?>{'at': 0.0, 'value': 1.0, 'ease': 'late'},
                <String, Object?>{'at': 1.0, 'value': 0.0},
              ],
            },
          ],
        }),
        vocabulary: vocabulary,
      );
      final affectors = document.effects.single.effect.affectors;
      expect(affectors.first, isA<ParticleWind>());
      expect(
        (affectors.last as ParticleSizeCurve).curve.keys.first.ease.name,
        'late',
      );
    });

    test(
      'an effect read is the effect written in Dart, particle for particle',
      () {
        // Mutation: read a default for any key, or reorder the affectors. The
        // fixture's core and the same effect in Dart are one simulation.
        final dart = ParticleEffect(
          count: 90,
          emitter: const SphereEmitter(
            speed: Range(4.0, 16.0),
            radius: Range(0.0, 0.4),
          ),
          lifetime: const Range(0.25, 0.6),
          size: const Range(0.35, 0.9),
          color: Vector4(3.2, 1.5, 0.45, 1.0),
          affectors: <ParticleAffector>[
            const ParticleDrag(6.0),
            const ParticleGravity(-3.0),
            ParticleColorOverLife(
              Vector4(3.2, 1.5, 0.45, 1.0),
              Vector4(0.6, 0.15, 0.05, 1.0),
            ),
            const ParticleSizeOverLife(from: 0.7, to: 1.6),
            const ParticleFade(startsAt: 0.35),
          ],
        );
        final read = _burstAndRun(_fixture()['core']!.effect);
        expect(read, isNotEmpty);
        expect(read, _burstAndRun(dart));
      },
    );
  });

  group('a floor', () {
    test('stops a fall, and bounces it by the fraction asked', () {
      // Mutation: test the position after the move, or forget the bounce. A
      // particle falling onto the floor sinks through it or lands dead.
      const floor = ParticlePlaneCollision(
        height: 1.0,
        bounce: 0.5,
        friction: 0.25,
      );
      final particle = Particle()
        ..position.setValues(0.0, 1.01, 0.0)
        ..velocity.setValues(2.0, -4.0, 0.0);
      floor.apply(particle, 0.01);
      expect(particle.velocity.y, 2.0);
      expect(particle.velocity.x, 1.5);

      final rising = Particle()
        ..position.setValues(0.0, 0.5, 0.0)
        ..velocity.setValues(0.0, 3.0, 0.0);
      floor.apply(rising, 0.01);
      expect(rising.position.y, 1.0, reason: 'below the floor is put on it');
      expect(rising.velocity.y, 3.0, reason: 'a rise is left alone');
    });

    test('keeps a whole effect above it', () {
      final effect = EffectDocument.fromJson(
        _one(<String, Object?>{
          'count': 40,
          'emitter': <String, Object?>{
            'shape': 'sphere',
            'speed': <double>[2, 5],
          },
          'affectors': <Object?>[
            <String, Object?>{'type': 'gravity'},
            <String, Object?>{'type': 'collide', 'height': 0.5},
          ],
        }),
      ).effects.single.effect;
      final out = _burstAndRun(effect, seconds: 0.9);
      for (var i = 1; i < out.length; i += ParticleSystem.floatsPerInstance) {
        expect(out[i], greaterThanOrEqualTo(0.5 - 1e-3));
      }
    });
  });

  group('ParticleEffects', () {
    test('a trigger goes off where its event happened', () {
      // Mutation: drop the subscription, or place the burst at the origin.
      final bus = _Bus();
      final effects = ParticleEffects(ParticleSystem(capacity: 1024, seed: 1));
      effects.addDocument(_fixture(), events: bus);
      expect(effects.names, <String>['core', 'debris', 'smoke', 'glow']);
      expect(effects.unsupported.keys, <String>['debris']);

      bus.show(_Blast(Vector3(5.0, 0.0, 5.0)));
      expect(effects.system.aliveCount, 90 + 12, reason: 'core and debris');
      final center = Vector3.zero();
      effects.system.boundsInto(center);
      expect(center.x, closeTo(5.0, 1.0));

      // The smoke is a timed rate: nothing until the system steps.
      effects.system.advance(0.5);
      expect(effects.triggerCounts, (fired: 3, unplaced: 0));
    });

    test(
      'an event with no place goes off at its trigger\'s, or not at all',
      () {
        final bus = _Bus();
        final effects = ParticleEffects(
          ParticleSystem(capacity: 1024, seed: 1),
        );
        effects.addDocument(_fixture(), events: bus);
        bus.show(const _Named('elements.exploded'));
        expect(effects.triggerCounts, (fired: 0, unplaced: 3));
        bus.show(const _Named('beacon.lit'));
        expect(effects.triggerCounts, (fired: 1, unplaced: 3));
        effects.system.advance(0.5);
        expect(effects.system.aliveCount, greaterThan(0));
      },
    );

    test('a placer places what the event class does not', () {
      final bus = _Bus();
      final effects = ParticleEffects(ParticleSystem(capacity: 1024, seed: 1));
      effects.addDocument(
        _fixture(),
        events: bus,
        place: (event) => (at: Vector3(1.0, 2.0, 3.0), direction: null),
      );
      bus.show(const _Named('elements.exploded'));
      expect(effects.triggerCounts.unplaced, 0);
      expect(effects.system.aliveCount, 102);
    });

    test('a plugin\'s effects are its own, and leave with it', () {
      // Mutation: file a plugin's effect under its bare name, or leave its
      // subscription behind when it is switched off.
      final bus = _Bus();
      final scope = _Scope();
      final effects = ParticleEffects(ParticleSystem(capacity: 1024, seed: 1));
      final view = effects.forPlugin(scope);
      view.addDocument(
        _fixture(),
        events: bus,
        eventName: (event) => event == 'beacon.lit' ? 'fireworks.lit' : event,
      );
      expect(effects.names.first, 'fireworks.core');
      expect(effects['fireworks.glow'], isNotNull);
      bus.show(const _Named('fireworks.lit'));
      expect(effects.triggerCounts.fired, 1);

      expect(
        () => view.add(_fixture()['core']!),
        throwsA(isA<ArgumentError>()),
        reason: 'a name is unique in one engine',
      );

      for (final registration in scope.tracked) {
        registration.cancel();
      }
      expect(effects.names, isEmpty);
      expect(bus.frame, isEmpty);
    });

    test('burst and emit start an effect by name', () {
      final effects = ParticleEffects(ParticleSystem(capacity: 1024, seed: 1));
      effects.addDocument(_fixture());
      expect(effects.burst('core', Vector3.zero()), 90);
      effects.system.clear();
      final key = Object();
      for (var frame = 0; frame < 30; frame++) {
        effects.emit(key, 'smoke', Vector3.zero());
        effects.system.advance(1.0 / 60.0);
      }
      // The document's 34 a second for half a second, none old enough to die.
      expect(effects.system.aliveCount, inInclusiveRange(16, 17));
      expect(
        () => effects.emit(key, 'core', Vector3.zero()),
        throwsA(isA<ArgumentError>()),
        reason: 'the core gives no rate',
      );
      expect(
        () => effects.burst('nothing', Vector3.zero()),
        throwsArgumentError,
      );
    });

    test('a look per pool, when the application asks for one', () {
      final pools = <String, ParticleSystem>{};
      final effects = ParticleEffects(
        ParticleSystem(capacity: 16),
        systemFor: (render) =>
            pools.putIfAbsent(render.key, () => ParticleSystem(capacity: 256)),
      );
      effects.addDocument(_fixture());
      expect(effects.looks, hasLength(4));
      expect(pools, hasLength(4));
      expect(effects.systemOf('core'), isNot(same(effects.system)));
    });
  });
}

double _late(double t) => t * t * t;
