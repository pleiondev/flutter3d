/// Eight slots per draw, and a scene free to carry hundreds of lights.
///
///     flutter test test/light_selection_test.dart
///
/// The eight was never a limit on the scene; it is the length of the arrays the
/// fragment shaders declare, and those are compiled ahead of time. What used to
/// make it a limit on the scene was that one packing served the whole frame, so
/// the ninth lamp in a night map did nothing anywhere. [LightBuffer.gatherNear]
/// asks the question again per object, and the arrays it fills are the same
/// four arrays, in the same layout, read by the same unchanged shaders.
///
/// What is worth pinning here is not that a selection happens — it is what the
/// selection may never do:
///
///   * it may not disagree with the shader. The score is intensity times the
///     glTF attenuation of `surface.glsl`, so a light it drops is one the
///     shader would have computed as dimmer than one it kept;
///   * it may not be undecided. Two lamps that score alike have to resolve the
///     same way every frame, or the picture flickers and no golden reproduces;
///   * it may not change a scene that fits. Every recorded golden was packed by
///     [LightBuffer.gather], and the two routes have to agree byte for byte
///     wherever both apply.
library;

import 'package:flutter3d/src/engine/scene/scene_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A point light at [x] on the X axis.
LightNode _lamp(
  Scene scene, {
  required double x,
  double y = 0.0,
  double range = 0.0,
  double intensity = 1.0,
  required String name,
}) => scene.add(
  LightNode(
    type: LightType.point,
    color: Vector3(1.0, 1.0, 1.0),
    intensity: intensity,
    range: range,
    name: name,
  )..setPosition(x, y, 0.0),
);

/// The names of the lights a buffer packed, in slot order.
List<String?> _names(LightBuffer buffer) => <String?>[
  for (final light in buffer.packed) light.name,
];

void main() {
  group('choosing eight of many', () {
    test('two objects at opposite ends are handed different eights', () {
      // Twenty lamps in a line, and two objects standing at either end of it.
      // The frame-wide packing would give both of them lamps 0 through 7 — the
      // whole point is that the object at x = 19 is nowhere near those.
      final scene = Scene();
      for (var i = 0; i < 20; i++) {
        _lamp(scene, x: i.toDouble(), name: 'lamp$i');
      }

      final buffer = LightBuffer()..collect(scene.lights);
      expect(buffer.candidates, hasLength(20));

      buffer.gatherNear(Vector3(0.0, 0.0, 0.0), 0.5);
      final west = _names(buffer);

      buffer.gatherNear(Vector3(19.0, 0.0, 0.0), 0.5);
      final east = _names(buffer);

      // Mutation: return the frame's packing from `gatherNearFrom` — score
      // every candidate as 1.0, say — and the two lists become identical.
      expect(west, isNot(equals(east)));
      expect(west, hasLength(8));
      expect(east, hasLength(8));
      // Nearest eight to each end, and nothing from the far half in either.
      expect(west, <String>[
        'lamp0',
        'lamp1',
        'lamp2',
        'lamp3',
        'lamp4',
        'lamp5',
        'lamp6',
        'lamp7',
      ]);
      expect(east, <String>[
        'lamp12',
        'lamp13',
        'lamp14',
        'lamp15',
        'lamp16',
        'lamp17',
        'lamp18',
        'lamp19',
      ]);
    });

    test('the chosen eight are packed in scene order, not by strength', () {
      // The order matters beyond tidiness: a light that stays chosen keeps its
      // slot while the set holds, and the slot is what the shadow slot table is
      // written against.
      final scene = Scene();
      for (var i = 0; i < 12; i++) {
        _lamp(scene, x: (11 - i).toDouble(), name: 'lamp$i');
      }

      final buffer = LightBuffer()
        ..collect(scene.lights)
        ..gatherNear(Vector3.zero(), 0.0);

      // Strongest first would be lamp11 (at x = 0) through lamp4; scene order
      // is the reverse of that.
      expect(_names(buffer), <String>[
        'lamp4',
        'lamp5',
        'lamp6',
        'lamp7',
        'lamp8',
        'lamp9',
        'lamp10',
        'lamp11',
      ]);
    });

    test('a scene that fits packs identically through either route', () {
      // The claim every recorded golden rests on. Not "close": the same four
      // arrays, element for element, so adopting per-object selection could not
      // move a picture that never overflowed.
      final scene = Scene();
      scene.add(
        LightNode(type: LightType.directional, name: 'sun')
          ..setLocalForward(Vector3(0.0, -1.0, 0.0)),
      );
      _lamp(scene, x: 2.0, range: 9.0, intensity: 3.0, name: 'lamp');
      _lamp(scene, x: -4.0, y: 1.0, intensity: 0.5, name: 'sconce');

      final byOrder = LightBuffer()..gather(scene.lights);
      final byRelevance = LightBuffer()
        ..collect(scene.lights)
        ..gatherNear(Vector3.zero(), 1.0);

      expect(byRelevance.count, byOrder.count);
      expect(_names(byRelevance), _names(byOrder));
      expect(byRelevance.positions, byOrder.positions);
      expect(byRelevance.colors, byOrder.colors);
      expect(byRelevance.directions, byOrder.directions);
      expect(byRelevance.cones, byOrder.cones);
    });
  });

  group('what the score is', () {
    test('range is measured to the surface of an object, not its centre', () {
      // A floor tile twenty metres across with a lamp standing at its edge. The
      // lamp's range reaches the near edge and falls well short of the centre,
      // so a score read at the centre drops it — which is the version of this
      // that leaves a wide floor unlit beside a lamp that is touching it.
      //
      // Mutation: drop the `- radius` in `_relevance`. The lamp scores zero,
      // the buffer packs nothing, and this goes red.
      final scene = Scene();
      _lamp(scene, x: 12.0, range: 10.0, name: 'edge');

      final buffer = LightBuffer()
        ..collect(scene.lights)
        ..gatherNear(Vector3.zero(), 9.0);

      expect(_names(buffer), <String>['edge']);
    });

    test('an object outside every range is lit by nothing at all', () {
      // Not "lit by the eight least irrelevant". A light whose window has
      // closed contributes exactly zero in the shader, and packing it would
      // spend a slot on black.
      final scene = Scene();
      for (var i = 0; i < 20; i++) {
        _lamp(scene, x: i.toDouble(), range: 4.0, name: 'lamp$i');
      }

      final buffer = LightBuffer()
        ..collect(scene.lights)
        ..gatherNear(Vector3(1000.0, 0.0, 0.0), 1.0);

      expect(buffer.count, 0);
      expect(buffer.packed, isEmpty);
      // Twenty lights the scene holds and this object was told about none:
      // that is the number a caller reports, not a fault.
      expect(buffer.overflow, 20);
    });

    test('a directional light is never outranked by a lamp beside it', () {
      // The sun has no position, so "nearest" says nothing about it, and it is
      // the light the scene is lit by rather than decorated with. Eight lamps
      // pressed against the object still leave it its slot.
      //
      // Mutation: score a directional by intensity instead of infinity. Eight
      // lamps at attenuation 1e4 evict it and the object loses its key light.
      final scene = Scene();
      final sun = scene.add(
        LightNode(type: LightType.directional, intensity: 1.0, name: 'sun'),
      );
      sun.setLocalForward(Vector3(0.0, -1.0, 0.0));
      for (var i = 0; i < 8; i++) {
        _lamp(scene, x: 0.001 * i, intensity: 50.0, name: 'lamp$i');
      }

      final buffer = LightBuffer()
        ..collect(scene.lights)
        ..gatherNear(Vector3.zero(), 0.0);

      expect(buffer.count, 8);
      expect(_names(buffer), contains('sun'));
      expect(_names(buffer).first, 'sun');
    });
  });

  group('deciding the same way twice', () {
    test('a tie goes to the earlier light in scene order', () {
      // Nine lamps, of which the last two are the same distance away with the
      // same strength. One of them has to go, and which one may not depend on
      // anything the frame carries — a flicker here is a light popping in and
      // out as the camera stands still.
      //
      // Mutation: make the eviction comparison `<` instead of `<=`, so an
      // equal score displaces the incumbent. The later lamp wins and this
      // goes red.
      final scene = Scene();
      for (var i = 0; i < 7; i++) {
        _lamp(scene, x: 0.0, y: 1.0 + i * 0.001, name: 'near$i');
      }
      _lamp(scene, x: 5.0, name: 'first');
      _lamp(scene, x: -5.0, name: 'second');

      final buffer = LightBuffer()..collect(scene.lights);

      for (var repeat = 0; repeat < 3; repeat++) {
        buffer.gatherNear(Vector3.zero(), 0.0);
        expect(_names(buffer), contains('first'));
        expect(_names(buffer), isNot(contains('second')));
      }
    });

    test('the answer does not depend on which object was asked before', () {
      final scene = Scene();
      for (var i = 0; i < 30; i++) {
        _lamp(scene, x: i.toDouble(), range: 12.0, name: 'lamp$i');
      }

      final buffer = LightBuffer()..collect(scene.lights);
      buffer.gatherNear(Vector3(4.0, 0.0, 0.0), 1.0);
      final first = _names(buffer);

      buffer.gatherNear(Vector3(25.0, 0.0, 0.0), 1.0);
      buffer.gatherNear(Vector3(4.0, 0.0, 0.0), 1.0);

      expect(_names(buffer), first);
    });
  });

  group('a scene larger than the buffer', () {
    test('two hundred lights do not overrun the arrays', () {
      // The buffer is fixed-size and refilled in place; a selection that wrote
      // past eight slots would corrupt whatever uniform sits beside it, which
      // is the kind of fault that surfaces as a crash in another shader.
      final scene = Scene();
      for (var i = 0; i < 200; i++) {
        _lamp(scene, x: i * 0.5, range: 40.0, name: 'lamp$i');
      }

      final buffer = LightBuffer()..collect(scene.lights);
      expect(buffer.candidates, hasLength(200));

      buffer.gatherNear(Vector3(50.0, 0.0, 0.0), 1.0);
      expect(buffer.count, LightBuffer.maxLights);
      expect(buffer.packed, hasLength(LightBuffer.maxLights));
      expect(buffer.overflow, 192);
      expect(buffer.positions, hasLength(LightBuffer.maxLights * 4));

      // And the frame-wide route survives the same scene, since it is what the
      // shadow atlas is still assigned against.
      buffer.gather(scene.lights);
      expect(buffer.count, LightBuffer.maxLights);
      expect(buffer.overflow, 192);
    });

    test('a light that is off is not a light that lost a slot', () {
      final scene = Scene();
      for (var i = 0; i < 12; i++) {
        _lamp(scene, x: i.toDouble(), name: 'lamp$i')
          ..visible = i.isEven
          ..intensity = i == 0 ? 0.0 : 1.0;
      }

      final buffer = LightBuffer()..collect(scene.lights);
      // Six visible, less the one switched off.
      expect(buffer.candidates, hasLength(5));

      buffer.gatherNear(Vector3.zero(), 0.0);
      expect(buffer.count, 5);
      expect(buffer.overflow, 0);
    });
  });
}
