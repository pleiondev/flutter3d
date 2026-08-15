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
}
