/// What the renderer is told about a thing it has to draw.
///
/// `SpawnContext.onMonsterSpawned` has a test; `onFixture` has never had one,
/// and it is the hook that carries everything scenery. Its defaults are the
/// interesting part — a level that says nothing about a torch's size still has
/// to produce a drawable — and so is `Fixture.position`, whose doc names the
/// whole reason the class exists: *"Follows the collider when there is one,
/// because that keeps moving after this is reported — which is the whole point
/// of a lift."*
library;

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A context that keeps what it was told, which is all a test needs.
({SpawnContext context, List<Fixture> seen}) _context() {
  final seen = <Fixture>[];
  final world = CollisionWorld();
  return (
    context: SpawnContext(
      world: world,
      actors: ActorSystem(world: world),
      mechanisms: MechanismWorld(world),
      onFixture: seen.add,
    ),
    seen: seen,
  );
}

EntityDef _entity(Map<String, Object?> properties, {Vector3? at}) => EntityDef(
      type: 'torch',
      position: at ?? Vector3.zero(),
      properties: properties,
    );

void main() {
  test('a level that says nothing still produces a drawable fixture', () {
    // Every default in one place. A missing size is one metre and a missing
    // material is `default`, because the alternative is a renderer handed a
    // zero-sized box or a null name — both of which draw nothing and neither
    // of which says why.
    final (:context, :seen) = _context();
    context.reveal(_entity(<String, Object?>{}));

    expect(seen, hasLength(1));
    expect(seen.single.size, Vector3.all(1.0));
    expect(seen.single.material, 'default');
    expect(seen.single.collider, isNull);
    expect(seen.single.mechanism, isNull);
  });

  test('what the document says wins over the default', () {
    final (:context, :seen) = _context();
    context.reveal(_entity(<String, Object?>{
      'size': <double>[2.0, 3.0, 4.0],
      'material': 'iron',
    }));

    expect(seen.single.size, Vector3(2.0, 3.0, 4.0));
    expect(seen.single.material, 'iron');
  });

  test('and what the caller passes wins over the document', () {
    // A kind that knows better than the document — a lift sized from its brush
    // rather than from a property somebody forgot to set.
    final (:context, :seen) = _context();
    context.reveal(
      _entity(<String, Object?>{'size': <double>[2.0, 2.0, 2.0]}),
      size: Vector3(9.0, 9.0, 9.0),
    );

    expect(seen.single.size, Vector3(9.0, 9.0, 9.0));
  });

  test('a fixture with a collider follows it, which is the point', () {
    // The assertion the whole class exists for. A lift reports its fixture once,
    // at spawn, and then travels for the rest of the level; a fixture holding
    // the position it was born at draws the lift in the floor it started in.
    final (:context, :seen) = _context();
    final collider = Collider(
      shape: CollisionBox(Vector3(1.0, 1.0, 1.0)),
      position: Vector3(0.0, 0.0, 0.0),
      kind: ColliderKind.kinematic,
    );
    context.reveal(_entity(<String, Object?>{}), collider: collider);

    expect(seen.single.position, Vector3.zero());

    collider.position.setValues(0.0, 4.0, 0.0);

    expect(seen.single.position, Vector3(0.0, 4.0, 0.0),
        reason: 'the fixture kept the position it was reported at, so anything '
            'that moves is drawn where it used to be');
  });

  test('a fixture with no collider keeps the place it was given', () {
    // Scenery. A torch bracket has no body — giving it one so this field could
    // be non-null would put shapes in the broadphase that nothing tests, and a
    // player catching on the wall decoration.
    final (:context, :seen) = _context();
    context.reveal(_entity(<String, Object?>{}, at: Vector3(1.0, 2.0, 3.0)));

    expect(seen.single.position, Vector3(1.0, 2.0, 3.0));
  });

  test('a fixture copies the place it is given', () {
    // Built directly rather than through `reveal`, and that is the point: the
    // first version of this test went through `reveal` and passed with
    // `Fixture`'s own `.clone()` deleted, because `EntityDef` already copies
    // its position in its constructor. It was asserting somebody else's
    // guarantee.
    //
    // `Fixture`'s copy is still worth having: it is handed `entity.position`,
    // a vector the entity owns and could hand to something else that moves it.
    final live = Vector3(1.0, 2.0, 3.0);
    final fixture = Fixture(
      entity: _entity(<String, Object?>{}),
      at: live,
      size: Vector3.all(1.0),
      material: 'default',
    );

    live.setValues(50.0, 50.0, 50.0);

    expect(fixture.position, Vector3(1.0, 2.0, 3.0));
  });

  test('a context with no hook reveals nothing and does not throw', () {
    // `onFixture` is nullable: a headless simulation — a test, a server — has
    // nothing to draw with and must still be able to spawn a level.
    final world = CollisionWorld();
    final context = SpawnContext(
      world: world,
      actors: ActorSystem(world: world),
      mechanisms: MechanismWorld(world),
    );

    expect(() => context.reveal(_entity(<String, Object?>{})), returnsNormally);
  });
}
