import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show BusEvent, DataSection, DataSectionContext, PluginException, PluginHost;
import 'package:vector_math/vector_math.dart';

import 'effect_document.dart';
import 'particle_effects.dart';

/// A data plugin's `effects`: particle effects as `.f3dfx` documents,
/// installed into the engine's [ParticleEffects].
///
/// An entry is `{"source": "blast.f3dfx"}`, a file of the plugin's, or a
/// whole document written in place (`{"f3dfx": 1, "effects": [...]}`). An
/// entry that is neither is kept as written and not loaded, and the install
/// says so in a note: version 1 of the plugin format kept the section unread
/// before effects had a document form, and a document written then still
/// opens.
///
/// **Where an event places its effect.** A trigger naming one of the
/// plugin's own events means the name it is declared under on the bus, and
/// an event one of the plugin's systems published goes off where its first
/// three numbers say, leaning along the next three when it has six; any
/// other event is placed by the trigger's own `at`.
///
/// Registered by the application in the engine's `DataSectionRegistry`.
const DataSection effectsSection = _EffectsSection();

/// The section as read, then as loaded.
final class _Effects {
  const _Effects(this.written, [this.documents = const <EffectDocument>[]]);

  /// What the document has under `effects`, every entry as it was written.
  final List<Object?> written;

  /// The documents [written] names, read; empty until loaded.
  final List<EffectDocument> documents;

  /// How many entries are neither a source nor a document.
  int get kept => written.length - documents.length;
}

final class _EffectsSection extends DataSection {
  const _EffectsSection();

  @override
  String get name => 'effects';

  @override
  Object read(Object? written, DataSectionContext context) => switch (written) {
    null => const _Effects(<Object?>[]),
    final List<Object?> list => _Effects(List<Object?>.unmodifiable(list)),
    _ => throw const EffectFormatException('"effects" is not a list'),
  };

  @override
  Object? write(Object section) => (section as _Effects).written;

  @override
  List<String> resources(Object section) => <String>[
    for (final entry in (section as _Effects).written)
      if (entry case {'source': final String source}) source,
  ];

  /// Every document read before anything is installed: one that does not
  /// read refuses the plugin here, not halfway through an install.
  @override
  Object load(Object section, DataSectionContext context) {
    final written = (section as _Effects).written;
    return _Effects(
      written,
      List<EffectDocument>.unmodifiable(<EffectDocument>[
        for (final (index, entry) in written.indexed)
          ?switch (entry) {
            {'source': final String source} => EffectDocument.parse(
              context.textOf(source),
              from: source,
            ),
            final Map<String, Object?> inline when inline['f3dfx'] != null =>
              EffectDocument.fromJson(
                inline,
                from: '${context.plugin} (effects ${index + 1})',
              ),
            _ => null,
          },
      ]),
    );
  }

  @override
  void install(PluginHost host, Object section, DataSectionContext context) {
    final effects = section as _Effects;
    final kept = effects.kept;
    if (kept > 0) {
      context.note(
        '$kept effect description${kept == 1 ? '' : 's'} kept and not '
        'loaded: an "effects" entry is a "source" .f3dfx file of the '
        'plugin\'s, or a document written in place with "f3dfx" in it',
      );
    }
    if (effects.documents.isEmpty) return;
    if (host.backend == null) {
      context.note('effects not loaded: this engine draws nothing');
      return;
    }
    final registry = host.maybeRegistry<ParticleEffects>();
    if (registry == null) {
      throw PluginException(
        'plugin "${context.plugin}" brings effects '
        '(${effects.documents.expand((d) => d.effects).map((e) => e.name).join(', ')}), '
        'and this engine has no ParticleEffects to add them to; hand one to '
        'the engine among its registries',
      );
    }
    EffectPlace? place(BusEvent event) => switch (context.numbersOf(event)) {
      final List<double> n when n.length >= 3 => (
        at: Vector3(n[0], n[1], n[2]),
        direction: n.length >= 6 ? Vector3(n[3], n[4], n[5]) : null,
      ),
      _ => null,
    };
    for (final document in effects.documents) {
      registry.addDocument(
        document,
        events: host.events,
        place: place,
        eventName: context.eventName,
      );
      for (final effect in document.effects) {
        effect.unsupported.forEach(context.note);
      }
    }
  }
}
