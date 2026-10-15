import 'package:flutter3d_foundation/flutter3d_foundation.dart';

import 'changes.dart';
import 'events.dart';
import 'host.dart';
import 'loop.dart';
import 'manifest.dart';
import 'order.dart';
import 'plugin_group.dart';
import 'registration.dart';
import 'simulation_profile.dart';
import 'version.dart';

/// Where one plugin stands.
final class PluginStatus {
  const PluginStatus({
    required this.manifest,
    required this.enabled,
    this.reason,
    this.error,
  });

  final PluginManifest manifest;
  final bool enabled;

  /// Why it is off when the engine switched it off itself — a backend it
  /// does not run on, a dependency that is off, an `install` or a `ready`
  /// that threw. Null when it is on, or when it was switched off by
  /// request.
  final String? reason;

  /// What its `install` or `ready` threw, when that is why it is off; null
  /// otherwise.
  final Object? error;

  String get id => manifest.id;

  @override
  String toString() =>
      '${manifest.id}: ${enabled ? 'on' : 'off'}'
      '${reason == null ? '' : ' ($reason)'}';
}

/// The plugins of one engine: checked, ordered, installed, and switched on
/// and off at step boundaries.
///
/// **The plugin host.** The loop owns one and calls [applyPending] at every
/// step boundary; nothing else installs or removes a plugin, so no plugin
/// arrives or leaves in the middle of a step.
///
/// ## What it checks before anything is installed
///
/// * every id is well formed and unique;
/// * every plugin's API version is one this engine provides
///   ([PluginApiVersion.refusalOn] says why not);
/// * every dependency is among the plugins, and the dependencies have no
///   cycle — a [ConstraintCycleException] names the plugins in it;
/// * every dependency's [PluginManifest.version] is in the range its
///   dependent names ([PluginDependency.refusalOf] says why not).
///
/// ## Order
///
/// Plugins install in dependency order, and where dependencies leave a
/// choice, in the order they were given (or last [reorder]ed into). The
/// order is also each plugin's rank, which breaks ties between registrations
/// in every registry.
///
/// ## Switching at run time
///
/// [enable], [disable] and [reorder] are checked when they are asked for —
/// a disable that would strand an enabled dependent throws then, naming it —
/// and carried out at the next step boundary, where they are journalled.
/// [schedule] hands a replay the journal of a recorded run, and the same
/// changes are made at the same steps.
final class PluginManager {
  PluginManager({
    required this.loop,
    required this.events,
    Iterable<PluginRegistry> registries = const <PluginRegistry>[],
    this.backend,
    this.apiVersion = PluginApiVersion.current,
    this.profile = SimulationProfile.deterministic,
  }) : _registries = List<PluginRegistry>.unmodifiable(registries);

  /// What the engine's simulation promises about its numbers, handed to
  /// every plugin as `PluginHost.profile`.
  final SimulationProfile profile;

  final LoopRegistry loop;
  final EventRegistry events;

  /// The engine's registries beyond the loop and the bus, found by type.
  final List<PluginRegistry> _registries;

  /// The graphics backend, matched against each manifest's backends.
  final String? backend;

  /// The API this engine provides.
  final PluginApiVersion apiVersion;

  final Map<String, _Entry> _entries = <String, _Entry>{};

  /// Install order, dependencies first.
  List<String> _order = const <String>[];

  /// The order asked for, which [_order] keeps wherever dependencies allow.
  List<String> _preferred = const <String>[];

  /// What was asked for since the last boundary, as the changes it will
  /// be, at a step filled in when it is made.
  final List<PluginChange> _requests = <PluginChange>[];
  final List<PluginChange> _scheduled = <PluginChange>[];
  final List<PluginChange> _journal = <PluginChange>[];

  /// The plugins in install order.
  List<String> get order => List<String>.unmodifiable(_order);

  /// Every plugin's status, in install order.
  List<PluginStatus> get statuses => <PluginStatus>[
    for (final id in _order) _entries[id]!.status,
  ];

  /// Every enabled plugin that touches the simulation, by id, with its own
  /// simulation number: `SimulationVersion.plugins` for this engine.
  Map<String, int> get simulationVersions => <String, int>{
    for (final id in _order)
      if (_entries[id]!.enabled &&
          _entries[id]!.plugin.manifest.touches.simulates)
        id: _entries[id]!.plugin.manifest.simulationVersion,
  };

  /// Whether [id] is installed and on.
  bool isEnabled(String id) => _entries[id]?.enabled ?? false;

  /// Whether anything is waiting for the next step boundary.
  bool get hasPending => _requests.isNotEmpty || _scheduled.isNotEmpty;

  /// Every change applied since the engine started, oldest first.
  List<PluginChange> get journal => List<PluginChange>.unmodifiable(_journal);

  /// The plugins' whole state as a change at [step]: what a recording that
  /// begins mid-run writes first.
  PluginsSet stateAt(int step) => PluginsSet(
    step: step,
    order: order,
    enabled: <String>[
      for (final id in _order)
        if (_entries[id]!.enabled) id,
    ],
    affectsSimulation: _entries.values.any(
      (e) => e.plugin.manifest.touches.simulates,
    ),
  );

  /// Installs [group]'s plugins, in its order, as [installAll] does.
  void installGroup(PluginGroup group) => installAll(group.plugins);

  /// Checks [plugins] and installs every one that can run, in dependency
  /// order. Once, before the first step.
  ///
  /// **One plugin that throws does not stop the rest.** The checks come
  /// first and refuse the whole set — an id that is not one, two plugins
  /// with one id (a [NameTakenException]), an API version or a dependency's
  /// version this engine cannot meet — since nothing is installed yet and
  /// the set itself is wrong. Then each plugin installs in turn; one whose
  /// `install` throws is left off, what it registered withdrawn, with
  /// `PluginStatus.reason` saying what it threw, and so is every plugin
  /// that depends on it, with a reason naming it. The others install.
  void installAll(Iterable<Flutter3dPlugin> plugins) {
    if (_entries.isNotEmpty) {
      throw StateError('installAll runs once, before the first step');
    }
    final given = List<Flutter3dPlugin>.of(plugins);
    for (final plugin in given) {
      final manifest = plugin.manifest;
      final problem = manifest.idProblem;
      if (problem != null) throw PluginException(problem);
      final earlier = _entries[manifest.id];
      if (earlier != null) {
        throw NameTakenException(
          manifest.id,
          what: 'the plugin id',
          owner: '${earlier.plugin.runtimeType}',
          detail:
              '${plugin.runtimeType} asks for it too, and an id is unique '
              'among the plugins of one engine',
        );
      }
      final refusal = manifest.apiVersion.refusalOn(apiVersion);
      if (refusal != null) {
        throw PluginException(
          'plugin "${manifest.id}" cannot be installed: $refusal',
        );
      }
      _entries[manifest.id] = _Entry(this, plugin);
    }
    _preferred = <String>[for (final plugin in given) plugin.manifest.id];
    _order = _sorted(_preferred);
    for (final id in _order) {
      final manifest = _entries[id]!.plugin.manifest;
      for (final dependency in manifest.dependencies) {
        final refusal = dependency.refusalOf(
          _entries[dependency.id]!.plugin.manifest.version,
        );
        if (refusal != null) {
          throw PluginException('plugin "$id" cannot be installed: $refusal');
        }
      }
    }
    for (final id in _order) {
      final entry = _entries[id]!;
      final manifest = entry.plugin.manifest;
      if (!manifest.runsOn(backend)) {
        entry.reason =
            'it runs on ${manifest.backends.join(', ')} and this engine '
            'draws with $backend';
        continue;
      }
      _installUnlessBroken(entry);
    }
  }

  /// Installs [entry] unless a dependency of it is off, and leaves it off
  /// with the reason when its `install` throws: what [installAll] and a
  /// switch at a step boundary both do, so neither takes the rest down.
  void _installUnlessBroken(_Entry entry) {
    final manifest = entry.plugin.manifest;
    final off = manifest.dependencyIds
        .where((d) => !_entries[d]!.enabled)
        .toList();
    if (off.isNotEmpty) {
      entry
        ..reason = 'it depends on ${_quoted(off)}, which is off'
        ..error = null;
      return;
    }
    try {
      entry.install();
    } on Object catch (error) {
      entry
        ..reason = 'its install threw: $error'
        ..error = error;
    }
  }

  /// Completes once the `ready` of every plugin installed so far has —
  /// `Flutter3dPlugin.ready` — whether it loaded or threw. A plugin whose
  /// `ready` threw is switched off at the next step boundary, with its
  /// dependents; [statuses] says why.
  ///
  /// What a loading screen awaits before the first frame, and a test before
  /// it asserts; the loop never does.
  Future<void> whenReady() async {
    while (_readying.isNotEmpty) {
      await Future.wait(List<Future<void>>.of(_readying));
    }
  }

  /// The `ready`s still running.
  final Set<Future<void>> _readying = <Future<void>>{};

  /// Follows [entry]'s `ready` for [installation]: a throw switches the
  /// plugin off at the next boundary, with every enabled plugin that
  /// depends on it, dependents first.
  void _follow(_Entry entry, _Installation installation, Future<void> ready) {
    late final Future<void> followed;
    followed = ready
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace _) {
            if (!installation.live) return;
            entry
              ..reason = 'its ready threw: $error'
              ..error = error;
            final id = entry.plugin.manifest.id;
            for (final other in _order.reversed) {
              if (other == id || !_willBeOn(other)) continue;
              if (!_dependsOn(other, id)) continue;
              _entries[other]!
                ..reason = 'it depends on "$id", whose ready threw'
                ..error = null;
              _requestOff(other);
            }
            _requestOff(id);
          },
        )
        .whenComplete(() => _readying.remove(followed));
    _readying.add(followed);
  }

  /// Whether [id] depends on [on], directly or through another plugin.
  bool _dependsOn(String id, String on) {
    final direct = _entries[id]!.plugin.manifest.dependencyIds;
    return direct.contains(on) || direct.any((d) => _dependsOn(d, on));
  }

  void _requestOff(String id) => _requests.add(
    PluginDisabled(
      step: 0,
      plugin: id,
      affectsSimulation: _touchesSimulation(<String>[id]),
    ),
  );

  /// Switches [id] on at the next step boundary.
  ///
  /// Throws a [PluginException] now when it cannot be: an unknown id, a
  /// backend it does not run on, a dependency that is off.
  void enable(String id) {
    final entry = _entry(id);
    if (_willBeOn(id)) return;
    final manifest = entry.plugin.manifest;
    if (!manifest.runsOn(backend)) {
      throw PluginException(
        'plugin "$id" runs on ${manifest.backends.join(', ')} and this '
        'engine draws with $backend',
      );
    }
    final off = manifest.dependencyIds.where((d) => !_willBeOn(d)).toList();
    if (off.isNotEmpty) {
      throw PluginException(
        'plugin "$id" depends on ${_quoted(off)}, which is off; enable '
        '${off.length == 1 ? 'it' : 'them'} first',
      );
    }
    _requests.add(
      PluginEnabled(
        step: 0,
        plugin: id,
        affectsSimulation: _touchesSimulation(<String>[id]),
      ),
    );
  }

  /// Switches [id] off at the next step boundary.
  ///
  /// Throws a [PluginException] now when an enabled plugin depends on it,
  /// naming every one.
  void disable(String id) {
    _entry(id);
    if (!_willBeOn(id)) return;
    final dependents = <String>[
      for (final other in _order)
        if (_willBeOn(other) &&
            _entries[other]!.plugin.manifest.dependencyIds.contains(id))
          other,
    ];
    if (dependents.isNotEmpty) {
      throw PluginException(
        'plugin "$id" cannot be switched off while ${_quoted(dependents)} '
        '${dependents.length == 1 ? 'depends' : 'depend'} on it; switch '
        '${dependents.length == 1 ? 'that' : 'those'} off first',
      );
    }
    _requests.add(
      PluginDisabled(
        step: 0,
        plugin: id,
        affectsSimulation: _touchesSimulation(<String>[id]),
      ),
    );
  }

  /// Asks for the install order [preferred] at the next step boundary.
  ///
  /// Dependencies still come first: [preferred] is the order wherever they
  /// leave a choice. Plugins it leaves out keep their places after the ones
  /// it names.
  void reorder(List<String> preferred) {
    for (final id in preferred) {
      _entry(id);
    }
    _requests.add(
      PluginsReordered(
        step: 0,
        order: List<String>.unmodifiable(preferred),
        affectsSimulation: _touchesSimulation(_entries.keys),
      ),
    );
  }

  /// Makes [changes] — a recorded run's journal — at their steps, through
  /// [applyPending], as a replay reaches them.
  ///
  /// Changes at one step are made in the order given, which is the order
  /// they were journalled in.
  void schedule(Iterable<PluginChange> changes) {
    final all = <PluginChange>[..._scheduled, ...changes];
    // `List.sort` is not stable, and two changes at one step — an enable and
    // a reorder — must stay in the order they were made.
    final order = List<int>.generate(all.length, (i) => i)
      ..sort((a, b) {
        final byStep = all[a].step.compareTo(all[b].step);
        return byStep != 0 ? byStep : a.compareTo(b);
      });
    _scheduled
      ..clear()
      ..addAll(<PluginChange>[for (final i in order) all[i]]);
  }

  /// Carries out what is due at the boundary before step [step]: scheduled
  /// changes first, in step order, then what was asked for since the last
  /// boundary, in the order it was asked. Returns what was applied, which
  /// is also added to [journal].
  ///
  /// A scheduled change whose step has already passed is applied now rather
  /// than dropped: late is a divergence the replay will report, dropped
  /// would be one nobody could explain.
  List<PluginChange> applyPending(int step) {
    if (!hasPending) return const <PluginChange>[];
    final applied = <PluginChange>[];
    while (_scheduled.isNotEmpty && _scheduled.first.step <= step) {
      applied.add(_apply(_scheduled.removeAt(0), step));
    }
    final requests = List<PluginChange>.of(_requests);
    _requests.clear();
    for (final request in requests) {
      applied.add(_apply(request, step));
    }
    _journal.addAll(applied);
    return applied;
  }

  PluginChange _apply(PluginChange change, int step) {
    switch (change) {
      case PluginEnabled(:final plugin):
        final entry = _entry(plugin);
        if (!entry.enabled) _installUnlessBroken(entry);
      case PluginDisabled(:final plugin):
        final entry = _entry(plugin);
        if (entry.enabled) entry.uninstall();
      case PluginsReordered(:final order):
        _setOrder(order);
      case PluginsSet(:final order, :final enabled):
        _setOrder(order);
        final on = enabled.toSet();
        // Off first, dependents before what they depend on; then on, in
        // install order, so a dependency is up before what needs it.
        for (final id in _order.reversed) {
          final entry = _entries[id]!;
          if (entry.enabled && !on.contains(id)) entry.uninstall();
        }
        for (final id in _order) {
          final entry = _entries[id]!;
          if (!entry.enabled && on.contains(id)) _installUnlessBroken(entry);
        }
    }
    return change.step == step ? change : change.at(step);
  }

  void _setOrder(List<String> preferred) {
    final named = preferred.where(_entries.containsKey).toList();
    _preferred = <String>[
      ...named,
      for (final id in _preferred)
        if (!named.contains(id)) id,
    ];
    _order = _sorted(_preferred);
  }

  List<String> _sorted(List<String> preferred) => orderByConstraints<String>(
    preferred,
    nameOf: (id) => id,
    after: (id) => _entries[id]!.plugin.manifest.dependencyIds,
    what: 'plugins',
    onUnknown: (id, missing) => throw PluginException(
      'plugin "$id" depends on "$missing", which is not among the plugins '
      'of this engine (${_quoted(preferred)})',
    ),
  );

  bool _touchesSimulation(Iterable<String> ids) =>
      ids.any((id) => _entries[id]?.plugin.manifest.touches.simulates ?? false);

  /// Whether [id] will be on once the pending requests are carried out.
  bool _willBeOn(String id) {
    var on = _entries[id]?.enabled ?? false;
    for (final request in _requests) {
      switch (request) {
        case PluginEnabled(:final plugin) when plugin == id:
          on = true;
        case PluginDisabled(:final plugin) when plugin == id:
          on = false;
        default:
          break;
      }
    }
    return on;
  }

  _Entry _entry(String id) =>
      _entries[id] ??
      (throw PluginException(
        'no plugin is named "$id"; this engine has '
        '${_order.isEmpty ? 'none' : _quoted(_order)}',
      ));

  R? _registry<R extends PluginRegistry>(PluginScope scope) {
    Iterable<PluginRegistry> withCompanions(Iterable<PluginRegistry> of) =>
        of.expand(
          (registry) => <PluginRegistry>[
            registry,
            ...withCompanions(registry.companions),
          ],
        );
    final registry = withCompanions(_registries).whereType<R>().firstOrNull;
    if (registry == null) return null;
    final scoped = registry.forPlugin(scope);
    if (scoped is! R) {
      throw StateError(
        'the $R registry returned a ${scoped.runtimeType} from forPlugin; '
        'a registry must return its own interface type',
      );
    }
    return scoped;
  }

  static String _quoted(Iterable<String> ids) =>
      ids.map((id) => '"$id"').join(', ');
}

/// One plugin, and the installation of it that is on, if any.
final class _Entry {
  _Entry(this._manager, this.plugin);

  final PluginManager _manager;
  final Flutter3dPlugin plugin;

  bool enabled = false;
  String? reason;
  Object? error;
  _Installation? _installation;

  PluginStatus get status => PluginStatus(
    manifest: plugin.manifest,
    enabled: enabled,
    reason: reason,
    error: error,
  );

  /// Installs the plugin, then starts its `ready`. Throws what `install`
  /// throws, with everything it registered withdrawn.
  void install() {
    final installation = _installation = _Installation(this);
    final host = installation.host = _Host(_manager, installation);
    try {
      plugin.install(host);
    } catch (_) {
      installation.end();
      _installation = null;
      rethrow;
    }
    enabled = true;
    reason = null;
    error = null;
    final Future<void> ready;
    try {
      ready = plugin.ready(host);
    } on Object catch (error, stack) {
      _manager._follow(this, installation, Future<void>.error(error, stack));
      return;
    }
    _manager._follow(this, installation, ready);
  }

  void uninstall() {
    final installation = _installation;
    try {
      if (installation != null) plugin.uninstall(installation.host);
    } finally {
      installation?.end();
      _installation = null;
      enabled = false;
    }
  }
}

/// One installation of a plugin: the scope its registrations are filed
/// under, from its `install` until it is switched off.
///
/// **A scope per installation, so a late registration cannot outlive
/// one.** A plugin's `ready` may register after an `await`, and a load it
/// started may finish after the plugin was switched off and on again; a
/// registration tracked by an installation that has ended is cancelled at
/// once, instead of standing in the frame of a plugin that is off or being
/// filed with the next installation's.
final class _Installation extends PluginScope {
  _Installation(this._entry);

  final _Entry _entry;
  late final _Host host;
  final List<Registration> _registrations = <Registration>[];

  /// Whether this installation is still the plugin's.
  bool live = true;

  @override
  PluginManifest get manifest => _entry.plugin.manifest;

  @override
  int get rank => _entry._manager._order.indexOf(manifest.id);

  @override
  void track(Registration registration) {
    if (live) {
      _registrations.add(registration);
    } else {
      registration.cancel();
    }
  }

  /// Withdraws everything this installation registered, newest first.
  void end() {
    live = false;
    for (final registration in _registrations.reversed) {
      registration.cancel();
    }
    _registrations.clear();
  }
}

final class _Host extends PluginHost {
  _Host(this._manager, this._entry);

  final PluginManager _manager;
  final _Installation _entry;

  @override
  PluginManifest get manifest => _entry.manifest;

  @override
  PluginApiVersion get apiVersion => _manager.apiVersion;

  @override
  String? get backend => _manager.backend;

  @override
  SimulationProfile get profile => _manager.profile;

  @override
  late final LoopRegistry loop = _manager.loop.forPlugin(_entry);

  @override
  late final EventRegistry events = _manager.events.forPlugin(_entry);

  @override
  R registry<R extends PluginRegistry>() =>
      _manager._registry<R>(_entry) ??
      (throw StateError(
        'plugin "${manifest.id}" asked for a $R, and this engine has none. '
        'Install the package that provides it, or ask with maybeRegistry '
        'and run without it',
      ));

  @override
  R? maybeRegistry<R extends PluginRegistry>() => _manager._registry<R>(_entry);
}
