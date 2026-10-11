/// The editor's [EditorHintRegistry]: the hints plugins give for their
/// components, entity kinds and lit models, and what the inspector, the
/// palette and the material panel make of them.
library;

import 'package:flutter3d_core/formats.dart'
    show
        ColorHint,
        EnumHint,
        EnumHintValue,
        MaterialHint,
        MaterialHintKind,
        RangeHint,
        TextureHint;
import 'package:flutter3d_plugin_api/editor.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The hints an editor's inspectors are built from: the slot a plugin finds
/// with `host.maybeRegistry<EditorHintRegistry>()`, filled by
/// `EditorPieces`, which brings one along as a companion.
///
/// **What is added comes back out in order**: the application's first, then
/// each plugin's in install order, and within one owner as it was added. A
/// plugin's view namespaces what it adds (see [EditorHintRegistry]) and
/// withdraws it when the plugin is switched off.
final class EditorHints extends EditorHintRegistry {
  /// An editor's registry, empty.
  EditorHints() : _store = _HintStore(), _scope = null;

  EditorHints._scoped(EditorHints root, PluginScope scope)
    : _store = root._store,
      _scope = scope;

  final _HintStore _store;
  final PluginScope? _scope;

  String get _owner =>
      _scope == null ? 'the application' : 'plugin "${_scope.manifest.id}"';

  /// [name] as this view publishes it: `<pluginId>.<name>` for a bare name
  /// through a plugin's view, the name itself when it is already under the
  /// plugin's id or comes through the root.
  ///
  /// Throws an [ArgumentError] for an empty name, and for a dotted one under
  /// another id than the plugin's.
  String _published(String name, String what) {
    if (name.isEmpty) throw ArgumentError.value(name, what, 'needs a name');
    final scope = _scope;
    if (scope == null) return name;
    final id = scope.manifest.id;
    if (!name.contains('.')) return '$id.$name';
    if (name.startsWith('$id.')) return name;
    throw ArgumentError.value(
      name,
      what,
      'is under another namespace than plugin "$id"\'s: a plugin\'s '
      '${what}s are `$id.<name>`',
    );
  }

  Registration _add<T>(
    List<_Hinted<T>> into,
    T value,
    String key,
    String Function(T) keyOf,
    String what,
  ) {
    for (final existing in into) {
      if (keyOf(existing.value) != key) continue;
      throw ArgumentError.value(
        key,
        what,
        'the $what "$key" is already hinted, by ${existing.owner}',
      );
    }
    final added = _Hinted<T>(value, _owner, _scope, _store.sequence++);
    into.add(added);
    _store.changed();
    final registration = Registration(() {
      if (into.remove(added)) _store.changed();
    });
    _scope?.track(registration);
    return registration;
  }

  @override
  Registration addComponent(ComponentHints hints) {
    final id = _published(hints.id, 'component');
    return _add(
      _store.components,
      id == hints.id
          ? hints
          : ComponentHints(
              id: id,
              title: hints.title,
              fields: hints.fields,
              entityTypes: hints.entityTypes,
            ),
      id,
      (ComponentHints c) => c.id,
      'component',
    );
  }

  @override
  Registration addEntityKind(EntityKindHints hints) {
    if (hints.type.isEmpty) {
      throw ArgumentError.value(hints.type, 'type', 'needs a name');
    }
    return _add(
      _store.entityKinds,
      hints,
      hints.type,
      (EntityKindHints k) => k.type,
      'entity kind',
    );
  }

  @override
  Registration addMaterial(MaterialHints hints) {
    final model = _published(hints.model, 'model');
    return _add(
      _store.materials,
      model == hints.model
          ? hints
          : MaterialHints(model: model, fields: hints.fields),
      model,
      (MaterialHints m) => m.model,
      'model',
    );
  }

  @override
  List<ComponentHints> get components => _store.ordered(_store.components);

  @override
  List<EntityKindHints> get entityKinds => _store.ordered(_store.entityKinds);

  @override
  List<MaterialHints> get materials => _store.ordered(_store.materials);

  /// The hints of the entity type [type], or null.
  EntityKindHints? entityKind(String type) =>
      entityKinds.where((EntityKindHints k) => k.type == type).firstOrNull;

  /// The hints of the component [id], or null.
  ComponentHints? component(String id) =>
      components.where((ComponentHints c) => c.id == id).firstOrNull;

  /// The hints of the lit model [model], or null.
  MaterialHints? material(String model) =>
      materials.where((MaterialHints m) => m.model == model).firstOrNull;

  /// The components an entity of [type] shows: those that name the type,
  /// then those its kind's hints name, each once, in order.
  List<ComponentHints> componentsOf(String type) {
    final named = entityKind(type)?.components ?? const <String>{};
    return <ComponentHints>[
      for (final component in components)
        if (component.entityTypes.contains(type) ||
            named.contains(component.id))
          component,
    ];
  }

  /// Calls [onChange] whenever hints are added or withdrawn, until the
  /// registration it returns is cancelled. Not tracked by a plugin's scope.
  Registration listen(void Function() onChange) {
    final entry = _Listener(onChange);
    _store.listeners.add(entry);
    return Registration(() => _store.listeners.remove(entry));
  }

  @override
  EditorHints forPlugin(PluginScope scope) => EditorHints._scoped(this, scope);
}

/// [hint] as the material panel's control, or null for a field it shows
/// as plain text: a number without both ends, a toggle, a vector.
///
/// The material panel reads `flutter3d_core`'s [MaterialHint], which came
/// first; a plugin's lit model describes its parameters in the same
/// [FieldHint] its components use, and this is the crossing.
MaterialHint? materialHintOf(FieldHint hint) {
  final MaterialHintKind? kind = switch (hint.kind) {
    FieldKind.number || FieldKind.integer
        when hint.min != null && hint.max != null =>
      RangeHint(hint.min!, hint.max!, step: hint.step),
    FieldKind.color => ColorHint(
      channels: switch (hint.defaultValue) {
        final List<Object?> list when list.length == 4 => 4,
        _ => 3,
      },
    ),
    FieldKind.choice => EnumHint(<EnumHintValue>[
      for (final choice in hint.choices) EnumHintValue(choice),
    ]),
    FieldKind.asset =>
      hint.suffixes.isEmpty
          ? const TextureHint()
          : TextureHint(extensions: hint.suffixes),
    _ => null,
  };
  return kind == null
      ? null
      : MaterialHint(kind, label: hint.label, help: hint.help);
}

final class _Hinted<T> {
  _Hinted(this.value, this.owner, this.scope, this.sequence);

  final T value;
  final String owner;
  final PluginScope? scope;
  final int sequence;

  int get rank => scope?.rank ?? -1;
}

final class _Listener {
  _Listener(this.onChange);

  final void Function() onChange;
}

final class _HintStore {
  final List<_Hinted<ComponentHints>> components = <_Hinted<ComponentHints>>[];
  final List<_Hinted<EntityKindHints>> entityKinds =
      <_Hinted<EntityKindHints>>[];
  final List<_Hinted<MaterialHints>> materials = <_Hinted<MaterialHints>>[];
  final List<_Listener> listeners = <_Listener>[];
  int sequence = 0;

  /// The values of [added] by rank, read now, then by sequence.
  List<T> ordered<T>(List<_Hinted<T>> added) => List<T>.unmodifiable(<T>[
    for (final hinted
        in List<_Hinted<T>>.of(added)..sort((_Hinted<T> a, _Hinted<T> b) {
          final byRank = a.rank.compareTo(b.rank);
          return byRank != 0 ? byRank : a.sequence.compareTo(b.sequence);
        }))
      hinted.value,
  ]);

  void changed() {
    for (final listener in List<_Listener>.of(listeners)) {
      listener.onChange();
    }
  }
}
