import 'entity_def.dart';

/// A named stream of values, sampled once per fixed step — `edu-00`'s
/// `edu_data_source` (`doc/edu-00-interactive-format.md` §9), read from the
/// side of a running simulation rather than from a controller.
///
/// **Plain Dart, on purpose.** A twin's temperature reading becomes an input
/// to the same fixed step that a joystick axis already is — that is the
/// whole point `edu-00` §9 makes ("значение из источника... становится
/// вводом для этого шага ленты") — and an input this package does not know
/// how to read without a network stack would be an input only half the
/// packages depending on this one could use. `MqttDataSource` and
/// `WebSocketDataSource` are therefore adapters a caller writes against this
/// interface, in whatever package can afford to know about sockets; this
/// package ships the one implementation it can prove without one.
abstract class EduDataSource {
  const EduDataSource();

  /// The payload this source held at [step] — whatever shape the real sensor
  /// sends, read back the same way `edu_data_source.path` already expects
  /// (`sensors.spindle.rpm`, one level deeper than a level's own
  /// `EntityDef.number`/`.vector` read their own properties).
  Object? sample(int step);
}

/// A deterministic source, for demos and tests that must not depend on a
/// broker being reachable.
///
/// `edu-00` §9 names this `kind: "sampler"` for exactly this reason: a
/// station's dashboard in `tpl-04` has to draw *something* before a real
/// factory is wired up, and a test that branches a run at step 50 has to
/// reach the same value twice, on two different machines, forever.
final class SamplerDataSource extends EduDataSource {
  const SamplerDataSource(this._sample);

  final Object? Function(int step) _sample;

  @override
  Object? sample(int step) => _sample(step);
}

/// Every [EduDataSource] a level's `bindings` may name, by [EntityDef.name].
final class DataSourceRegistry {
  DataSourceRegistry(Map<String, EduDataSource> sources)
    : _sources = Map<String, EduDataSource>.of(sources);

  final Map<String, EduDataSource> _sources;

  EduDataSource? operator [](String name) => _sources[name];

  /// Swaps in a different source under the same name — the whole of a
  /// "what if": everything that reads [name] from here on samples
  /// [replacement] instead, and nothing before this call is touched, because
  /// nothing before this call is stored here at all — only read once, by the
  /// step it was read for, into whatever [DataSourceTrace] recorded it.
  void replace(String name, EduDataSource replacement) {
    _sources[name] = replacement;
  }
}

/// One `edu_step`'s worth of resolved bindings — `target` path to the value
/// [DataSourceRegistry] held for it at [step].
///
/// `target` is `сущность.путь-свойства`, per `edu-00` §9 — this function
/// does not apply it to anything. What a `сущность.свойство` path means (a
/// material field, a transform) is the host's decision, same as
/// `edu-00` §9 already says: this only answers "what value", not "written
/// where".
Map<String, Object?> resolveBindings(
  EntityDef step,
  int atStep,
  DataSourceRegistry sources,
) {
  final rawBindings = step.properties['bindings'];
  if (rawBindings is! List) return const <String, Object?>{};

  final resolved = <String, Object?>{};
  for (final entry in rawBindings) {
    if (entry is! Map) continue;
    final sourceName = entry['source'];
    final path = entry['path'];
    final target = entry['target'];
    if (sourceName is! String || path is! String || target is! String) {
      continue;
    }
    final source = sources[sourceName];
    if (source == null) continue;
    resolved[target] = _lookupPath(source.sample(atStep), path);
  }
  return resolved;
}

/// A dot-separated path into whatever a source's payload holds — the same
/// notation `edu-00` §9 names for `path` (`sensors.spindle.rpm`), one level
/// deeper than `EntityDef.number`/`.vector` already read their own flat
/// properties.
Object? _lookupPath(Object? root, String path) {
  Object? at = root;
  for (final segment in path.split('.')) {
    if (at is Map) {
      at = at[segment];
    } else {
      return null;
    }
  }
  return at;
}
