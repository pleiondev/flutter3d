/// What a brush is made of, and which bit it sits on.
///
///     flutter test test/brush_surface_test.dart
///
/// Two words the level format did not have. `material` has always been what a
/// brush *looks* like — it names an entry in the palette and the renderer reads
/// it — and there was no way to say what it *is*. A level wanting stone-looking
/// ice, or a metal grate you fall through, had to choose between the two.
///
/// The engine never compares either to a value. A game reads `surface` and
/// decides what `ice` means, exactly as it decides what a `crate` is.
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Brush _brush({String? surface, int? layer, String material = 'stone'}) => Brush(
      centre: Vector3(0.0, -0.5, 0.0),
      size: Vector3(8.0, 1.0, 8.0),
      material: material,
      surface: surface,
      layer: layer,
    );

void main() {
  group('what it is made of', () {
    test('a brush that says nothing is made of what it looks like', () {
      // Mutation: `String get surface => _surface ?? 'default'`. Every stone
      // floor in every level ever authored starts reporting 'default', and a
      // game keying footsteps off it plays the wrong one everywhere.
      expect(_brush().surface, 'stone');
    });

    test('and one that does keeps looking like itself', () {
      // The separation, in one assertion: ice that is painted as stone.
      //
      // Mutation: make `surface` shadow `material` — the renderer draws ice.
      final brush = _brush(surface: 'ice');
      expect(brush.surface, 'ice');
      expect(brush.material, 'stone');
    });
  });

  group('which bit it sits on', () {
    test('a brush with no layer is on the world layer, as always', () {
      final world = CollisionWorld();
      Level(brushes: <Brush>[_brush()]).addTo(world);

      final hit = SweepHit();
      final found = world.sweep(
        CollisionBox(Vector3.all(0.4)),
        Vector3(0.0, 3.0, 0.0),
        Vector3(0.0, -6.0, 0.0),
        hit,
      );
      expect(found, isTrue);
      expect(hit.collider!.layer, CollisionLayers.world);
    });

    test('a brush with a layer is on it, and a sweep can skip it', () {
      // Mutation: drop `brush.layer ??` from `LevelCollision.addTo`. The
      // authored bit is silently ignored, every brush is on the world layer,
      // and a one-way platform is an ordinary floor.
      const int grate = 1 << 6;
      final world = CollisionWorld();
      Level(brushes: <Brush>[_brush(layer: grate)]).addTo(world);

      final hit = SweepHit();
      expect(hit.collider, isNull);

      final blocked = world.sweep(
        CollisionBox(Vector3.all(0.4)),
        Vector3(0.0, 3.0, 0.0),
        Vector3(0.0, -6.0, 0.0),
        hit,
      );
      expect(blocked, isTrue, reason: 'it is still solid to anybody');
      expect(hit.collider!.layer, grate);

      final ignored = world.sweep(
        CollisionBox(Vector3.all(0.4)),
        Vector3(0.0, 3.0, 0.0),
        Vector3(0.0, -6.0, 0.0),
        SweepHit(),
        mask: ~grate,
      );
      expect(ignored, isFalse, reason: 'a body that skips that bit fell through');
    });
  });

  group('the document', () {
    test('a brush that says neither writes neither', () {
      // The compatibility guard, and the reason both keys are conditional: a
      // committed level round-trips byte for byte or every level file in the
      // repository changes the day this lands.
      //
      // Mutation: always emit 'surface' — the two maps stop matching.
      final json = _brush().toJson();
      expect(json.containsKey('surface'), isFalse);
      expect(json.containsKey('layer'), isFalse);

      final again = Brush.fromJson(json).toJson();
      expect(again, json);
    });

    test('and one that says both comes back with both', () {
      final json = _brush(surface: 'ice', layer: 64).toJson();
      final read = Brush.fromJson(json);

      expect(read.surface, 'ice');
      expect(read.material, 'stone');
      expect(read.layer, 64);
      expect(read.toJson(), json);
    });

    test('a layer written as a whole number in a hand-typed file is read', () {
      // JSON has one number type and a person types `64`, not `64.0`.
      final read = Brush.fromJson(<String, Object?>{
        'at': <double>[0.0, 0.0, 0.0],
        'size': <double>[1.0, 1.0, 1.0],
        'layer': 64.0,
      });
      expect(read.layer, 64);
    });
  });

  group('a brush that does not cast a shadow', () {
    // **A fence is not architecture.** A boundary wall exists so the level
    // cannot be walked out of. The teaching level's are sixteen metres tall —
    // raised from six when an autopilot climbed a chimney and walked off the
    // top of the world — and at this game's sun they lay a hard-edged band of
    // shade across a third of a twenty-two metre level: measured at eight per
    // cent of a frame, and read by a player as a shadow following them, because
    // they walk along it.
    //
    // Steepening the sun removes it and costs more than it saves — the same
    // frame goes from 23.8% dark to 29.4%, because a sun overhead lights
    // vertical surfaces edge-on. The wall was never what should have been
    // lighting the level.

    test('says so in its document, and only when it is unusual', () {
      // Mutation: write the flag unconditionally. Every brush in every level
      // grows a line saying the obvious, and two hundred and fifty of them is
      // a diff nobody reads.
      final fence = Brush(
        centre: Vector3.zero(),
        size: Vector3.all(1.0),
        castsShadow: false,
      );
      expect(fence.toJson()['castsShadow'], false);

      final wall = Brush(centre: Vector3.zero(), size: Vector3.all(1.0));
      expect(wall.toJson().containsKey('castsShadow'), isFalse);
      expect(wall.castsShadow, isTrue, reason: 'the default moved');
    });

    test('and comes back from one', () {
      final read = Brush.fromJson(<String, Object?>{
        'at': <double>[0.0, 0.0, 0.0],
        'size': <double>[1.0, 1.0, 1.0],
        'castsShadow': false,
      });

      expect(read.castsShadow, isFalse);
    });

    test('is batched apart from one that does', () {
      // **Why the surfaces are keyed by this as well as by material.** Brushes
      // are batched so a level of two hundred and fifty is a handful of draws,
      // and a batch is the smallest thing that can be left out of the shadow
      // pass — so a fence and a wall of the same stone have to stop sharing
      // one.
      //
      // Mutation: key the builders by material alone. The two collapse into a
      // single surface and the fence starts casting again, along with the wall.
      final level = Level(brushes: <Brush>[
        Brush(centre: Vector3(0.0, 0.0, 0.0), size: Vector3.all(2.0)),
        Brush(
          centre: Vector3(8.0, 0.0, 0.0),
          size: Vector3.all(2.0),
          castsShadow: false,
        ),
      ]);

      final surfaces = const BrushGeometry().build(level);

      expect(surfaces, hasLength(2),
          reason: 'same material, different answer, and they were batched '
              'together anyway');
      expect(surfaces.map((BrushSurface s) => s.castsShadow),
          containsAll(<bool>[true, false]));
    });

    test('and a level with no fences batches exactly as it always did', () {
      // The compatibility half: the split must cost nothing to every level
      // that does not use it.
      final level = Level(brushes: <Brush>[
        Brush(centre: Vector3(0.0, 0.0, 0.0), size: Vector3.all(2.0)),
        Brush(centre: Vector3(8.0, 0.0, 0.0), size: Vector3.all(2.0)),
      ]);

      expect(const BrushGeometry().build(level), hasLength(1));
    });
  });
}
