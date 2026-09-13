import 'package:flutter3d_sim/flutter3d_sim.dart';

/// One `edu_step`'s claim on an entity's property, per
/// `doc/edu-00-interactive-format.md` §9: `target` names it, `source` and
/// `path` say where the value comes from.
final class ActiveBinding {
  const ActiveBinding({
    required this.stepName,
    required this.source,
    required this.path,
  });

  /// The `edu_step` entity that declared this binding.
  final String stepName;

  /// The `edu_data_source` entity named as `bindings[].source`.
  final String source;

  /// The dotted path into that source's own payload.
  final String path;
}

/// Every binding any `edu_step` in [level] declares, keyed by its own
/// `target` — `сущность.путь-свойства`, per `edu-00` §9.
///
/// **What this is for.** The inspector reads a property to decide what
/// widget to draw for it (`_TextField`, `_SliderField`, `_ReadOnly`, ...);
/// a property this map names is one whose value comes from `edu-05` at
/// runtime rather than from whoever is editing the document, which is the
/// fact an inspector needs before it can decide to draw it read-only with a
/// caption naming the source, instead of a field someone can type into that
/// a live run would overwrite on its next step anyway. Wiring that choice
/// into `editor_inspector.dart`'s own field dispatch is not done here — this
/// is the lookup a caller doing so would read from, kept independent of any
/// widget so it can be proven with a plain `Level`, the same reason
/// `HeatmapLayout` (`ai-02`) was kept out of its `CustomPaint`.
///
/// A level with more than one `edu_step` naming the same `target` keeps the
/// **last** one a scan of [Level.entities] reaches — the same "last one
/// wins" a plain `Map` already gives for a duplicate key, not a rule this
/// function adds on top.
Map<String, ActiveBinding> bindingsInLevel(Level level) {
  final result = <String, ActiveBinding>{};
  for (final entity in level.entities) {
    if (entity.type != 'edu_step') continue;
    final rawBindings = entity.properties['bindings'];
    if (rawBindings is! List) continue;
    for (final entry in rawBindings) {
      if (entry is! Map) continue;
      final source = entry['source'];
      final path = entry['path'];
      final target = entry['target'];
      if (source is! String || path is! String || target is! String) {
        continue;
      }
      result[target] = ActiveBinding(
        stepName: entity.name ?? entity.type,
        source: source,
        path: path,
      );
    }
  }
  return result;
}
