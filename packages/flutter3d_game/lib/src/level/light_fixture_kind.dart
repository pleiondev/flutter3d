import 'package:vector_math/vector_math.dart';

import '../world/light_fixture.dart';
import 'entity_def.dart';
import 'entity_kind.dart';
import 'level_issue.dart';
import 'spawn_context.dart';

/// Anything that gives off light and can be seen doing it.
///
/// One class for the three, because a torch, a lamp and a stained window
/// differ in what they look like and how they flicker — and both of those are
/// data. What they *do* is identical: own a light, and vary it.
/// A named kind of light, described by data rather than by a subclass.
///
/// It was abstract, with `TorchKind`, `LampKind` and `WindowKind` overriding
/// two getters each. Its own doc already said why that was one step too far:
/// *"a torch, a lamp and a stained window differ in what they look like and
/// how they flicker — and both of those are data"*. The abstraction was right
/// and only the instances were in the wrong package, so the three subclasses
/// are gone and a game names its own:
///
/// ```dart
/// LightFixtureKind('torch',
///     defaultBehaviour: const FlameFlicker(),
///     defaultSize: Vector3(0.22, 0.5, 0.22));
/// ```
final class LightFixtureKind extends EntityKind {
  LightFixtureKind(
    super.type, {
    required this.defaultBehaviour,
    required Vector3 defaultSize,
  }) : defaultSize = defaultSize.clone();

  /// How this kind behaves when the document does not say.
  final LightBehaviour defaultBehaviour;

  final Vector3 defaultSize;

  @override
  void validate(EntityDef entity, LevelScope scope, List<LevelIssue> out) {
    final light = entity.string('light');
    if (light == null) return;
    for (final candidate in scope.level.lights) {
      if (candidate.name == light) return;
    }
    out.add(
      LevelIssue(
        LevelIssueSeverity.error,
        'drives the light "$light", which this level does not define',
        where: scope.describe(entity),
      ),
    );
  }

  @override
  void spawn(EntityDef entity, SpawnContext context) {
    final fixture = context.mechanisms.add(
      LightFixture(
        name: entity.name,
        light: entity.string('light'),
        behaviour: _behaviourFor(entity),
        // From the position, so a row of torches never pulses in unison and
        // an author never has to remember to stagger them by hand.
        seed: entity.number('phase') ??
            (entity.position.x * 0.37 + entity.position.z * 0.11) % 1.0,
        enabled: entity.flag('on', orElse: true),
      ),
    );
    // No collider: this is something to look at, not something to walk into.
    context.reveal(
      entity,
      mechanism: fixture,
      size: entity.vector('size') ?? defaultSize,
    );
  }

  LightBehaviour _behaviourFor(EntityDef entity) {
    // A swell rather than a flicker: something magical rather than burning.
    // `PulseLight` was written with the other two and then had no way into a
    // level at all — no property reached it, so nothing in any game could ever
    // be one. Checked before `flicker` because a lamp that asks for both is
    // asking for the slower of the two.
    final swell = entity.number('pulse');
    if (swell != null) {
      return swell <= 0.0
          ? const SteadyLight()
          : PulseLight(depth: swell, period: entity.number('period') ?? 3.5);
    }

    final depth = entity.number('flicker');
    if (depth == null) return defaultBehaviour;
    if (depth <= 0.0) return const SteadyLight();
    return FlameFlicker(depth: depth, rate: entity.number('rate') ?? 7.0);
  }
}
