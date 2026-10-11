part of 'engine_loop.dart';

/// The loop's fields: `EngineLoop.fields`, and `host.registry<FieldRegistry>()`
/// for a plugin.
///
/// A host field's values are made here when it is declared, every value
/// nought. It joins the loop's snapshots under `field:<id>` once a running
/// subsystem writes it ([_LoopSubsystems.register]), so a rollback, a replay
/// and the double-step check carry it, and a field whose solver a profile
/// leaves off is no part of the state: the default simulation digests as it
/// did. One that a frame or a sound reads is copied at the end of every
/// step, after the publish phase, into what [published] answers.
final class _LoopFields extends FieldRegistry {
  _LoopFields(this._loop)
    : _scope = null,
      _fields = <FieldDeclaration>[],
      _host = <String, HostField>{},
      _published = <String, HostField>{};

  _LoopFields._scoped(_LoopFields of, PluginScope scope)
    : _loop = of._loop,
      _scope = scope,
      _fields = of._fields,
      _host = of._host,
      _published = of._published;

  final EngineLoop _loop;
  final PluginScope? _scope;
  final List<FieldDeclaration> _fields;
  final Map<String, HostField> _host;
  final Map<String, HostField> _published;

  @override
  Registration declare(FieldDeclaration field) {
    if (field.problem case final problem?) {
      throw ArgumentError.value(field.id, 'field', problem);
    }
    if (_scope case final scope? when !_inNamespace(field.id, scope)) {
      throw ArgumentError.value(
        field.id,
        'field',
        'plugin "${scope.manifest.id}" declares fields under its own id, as '
            '"${scope.manifest.id}.<name>"',
      );
    }
    if (declarationOf(field.id) != null) {
      throw ArgumentError.value(
        field.id,
        'field',
        'a field "${field.id}" is already declared',
      );
    }
    _fields.add(field);
    if (field.residence == FieldResidence.host) {
      final values = _host[field.id] = HostField(field);
      if (field.readers.any((r) => r.side != FieldSide.simulation)) {
        _published[field.id] = values.copy();
      }
    }
    final registration = Registration(() {
      _fields.remove(field);
      _host.remove(field.id);
      _published.remove(field.id);
    });
    _scope?.track(registration);
    return registration;
  }

  @override
  List<FieldDeclaration> get declared =>
      List<FieldDeclaration>.unmodifiable(_fields);

  @override
  HostField? hostField(String id) => _host[id];

  @override
  HostField? published(String id) => _published[id]?.readOnly;

  /// Copies every published host field from what the step left.
  void _publishAfterStep() {
    if (_published.isEmpty) return;
    for (final MapEntry(:key, :value) in _published.entries) {
      value.copyFrom(_host[key]!);
    }
  }

  @override
  FieldRegistry forPlugin(PluginScope scope) =>
      _LoopFields._scoped(this, scope);
}

/// The loop's subsystems: `EngineLoop.subsystems`, and
/// `host.registry<SubsystemRegistry>()` for a plugin.
final class _LoopSubsystems extends SubsystemRegistry {
  _LoopSubsystems(this._loop)
    : _scope = null,
      _declared = <SubsystemDeclaration>[],
      _running = <SubsystemDeclaration>[];

  _LoopSubsystems._scoped(_LoopSubsystems of, PluginScope scope)
    : _loop = of._loop,
      _scope = scope,
      _declared = of._declared,
      _running = of._running;

  final EngineLoop _loop;
  final PluginScope? _scope;
  final List<SubsystemDeclaration> _declared;
  final List<SubsystemDeclaration> _running;

  @override
  Registration register(Subsystem subsystem) {
    final declaration = subsystem.declaration;
    final id = declaration.id;
    if (declaration.problem case final problem?) {
      throw ArgumentError.value(id, 'subsystem', problem);
    }
    if (_scope case final scope? when !_inNamespace(id, scope)) {
      throw ArgumentError.value(
        id,
        'subsystem',
        'plugin "${scope.manifest.id}" registers subsystems under its own '
            'id, as "${scope.manifest.id}.<name>"',
      );
    }
    if (_declared.any((d) => d.id == id)) {
      throw ArgumentError.value(
        id,
        'subsystem',
        'a subsystem "$id" is already registered',
      );
    }
    final fields = _loop._fields;
    for (final name in <String>[
      ...declaration.readsFields,
      ...declaration.writesFields,
    ]) {
      final field = fields.declarationOf(name);
      final problem = switch (field) {
        null => 'names the field "$name", which nobody declared',
        _ when field.residence != FieldResidence.host =>
          'names the field "$name", which is held in '
              '${field.residence.name}; a subsystem steps host memory',
        _
            when declaration.writesFields.contains(name) &&
                field.writer != FieldAccess.simulation(id) =>
          'writes the field "$name", whose writer is '
              '${field.writer.side.name} "${field.writer.step}"',
        _ => null,
      };
      if (problem != null) {
        throw ArgumentError.value(id, 'subsystem', 'subsystem "$id" $problem');
      }
    }
    final running = declaration.runsUnder(_loop.profile);
    final held = <Registration>[];
    if (running) {
      final context = _SubsystemContext(_loop, declaration);
      void step(LoopContext loop) => subsystem.step(context..loop = loop);
      final loop = switch (_scope) {
        null => _loop,
        final scope => _loop.forPlugin(scope),
      };
      // The scoped loop refuses a step system to a plugin that touches only
      // the view, before anything here has changed.
      held.add(
        loop.addSystem(
          id,
          declaration.phase,
          step,
          after: declaration.after,
          before: declaration.before,
        ),
      );
      // What it writes is the simulation's state from now on: snapshotted,
      // restored and digested with the world.
      for (final name in declaration.writesFields) {
        held.add(_loop.snapshots.add(fields._host[name]!.snapshotPart));
      }
      _running.add(declaration);
    }
    _declared.add(declaration);
    final registration = Registration(() {
      for (final each in held.reversed) {
        each.cancel();
      }
      _declared.remove(declaration);
      _running.remove(declaration);
    });
    _scope?.track(registration);
    return registration;
  }

  @override
  List<SubsystemDeclaration> get declared =>
      List<SubsystemDeclaration>.unmodifiable(_declared);

  @override
  List<SubsystemDeclaration> get running =>
      List<SubsystemDeclaration>.unmodifiable(_running);

  @override
  SubsystemRegistry forPlugin(PluginScope scope) =>
      _LoopSubsystems._scoped(this, scope);
}

bool _inNamespace(String id, PluginScope scope) =>
    id.startsWith('${scope.manifest.id}.');

/// What a subsystem is handed: the step's numbers from the loop's context,
/// and the host fields it declared, read-only where it only reads.
final class _SubsystemContext extends SubsystemContext {
  _SubsystemContext(this._engine, this.declaration);

  final EngineLoop _engine;

  /// The loop's context for the system running now.
  late LoopContext loop;

  @override
  final SubsystemDeclaration declaration;

  @override
  int get step => loop.step;

  /// One fixed step, in seconds.
  @override
  double get dt => loop.dt;

  @override
  bool get isResimulated => loop.isResimulated;

  @override
  SimulationProfile get profile => _engine.profile;

  @override
  SimWorld get world => loop.world;

  @override
  void publish(BusEvent event) => loop.publish(event);

  @override
  HostField field(String id) {
    final values = _engine._fields.hostField(id);
    if (values != null) {
      if (declaration.writesFields.contains(id)) return values;
      if (declaration.readsFields.contains(id)) return values.readOnly;
    }
    throw StateError(
      'subsystem "${declaration.id}" asked for the field "$id", which it '
      'declared neither among what it reads nor among what it writes',
    );
  }
}
