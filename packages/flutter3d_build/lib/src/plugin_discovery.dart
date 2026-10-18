/// Plugin discovery: which of an application's dependencies are flutter3d
/// plugins, written into `lib/plugins.g.dart`.
///
/// A package marks itself in its pubspec, under [pluginMarkerKey]:
///
/// ```yaml
/// flutter3d_plugins:
///   plugin: package:trails/trails.dart#TrailsPlugin
/// ```
///
/// — an import, `#`, and a class with an unnamed constructor that takes
/// nothing. The import may be written relative to the package's `lib/`
/// (`trails.dart#TrailsPlugin`), and a package with more than one plugin
/// gives a list.
///
/// **A package of several libraries marks each one.** `flutter3d_post` is
/// six families of effects, a library each, and listing thirty
/// `<import>#<Class>` lines repeats six imports five times over. So the
/// marker may also be a map, from a library to the class or the list of
/// classes it declares:
///
/// ```yaml
/// flutter3d_plugins:
///   plugin:
///     light.dart: [BloomAddon, LensFlareAddon]
///     shading.dart: AmbientOcclusionAddon
/// ```
///
/// All three forms read into the same [DiscoveredPlugin]s, in the order the
/// pubspec writes them, so a package moving from one to another changes
/// nothing in `plugins.g.dart`.
///
/// **The key was `flutter3d: plugin:` before 1.0** (decision D of
/// `tasks/1.0-arch-review.md`): a top-level key named like a package drew a
/// warning from `pub publish`. Only the key moved; what is under it, `plugin:`
/// and the keys the plugin catalogue reads, is the same. The old key is still
/// read, with a warning in [PluginDiscovery.warnings], until 2.0.
///
/// **The project's list is a plugin group.** Depending on a package
/// installs every plugin it marks, and `flutter3d_post` marks twenty-three.
/// `lib/plugins.g.dart` holds them as a `PluginGroup`, and the application's
/// own pubspec adjusts it under the same key with the group's three words,
/// applied in this order:
///
/// ```yaml
/// flutter3d_plugins:
///   without:
///     - flutter3d_post/motion.dart          # a whole library
///     - flutter3d_post/style.dart#ToonLightingAddon   # one class
///   set:                                    # constructed with arguments
///     flutter3d_post/light.dart#BloomAddon: "threshold: 1.2"
///   with:                                   # one no dependency marks
///     - package:my_game/trails.dart#TrailsPlugin
/// ```
///
/// A `without` entry is a [PluginSelector]: a package, a library in it, or
/// one class of a library. A `set` key and a `with` entry name one class;
/// `set` constructs it with the arguments written (in place, or at the end
/// when the group does not hold it, as `PluginGroup.set` does), and `with`
/// adds it at the end. A `without` entry that matches nothing any dependency
/// declares, and a `with` entry the group already holds, are reported in
/// [PluginDiscovery.warnings]: a misspelt exclusion would otherwise leave
/// the plugin installed without a word. What was left out is in
/// [PluginDiscovery.excluded]. Code adjusts the generated group the same
/// way (`installedPlugins.without<FogAddon>()`).
///
/// **Run by the build hook and by a command.** `buildAssets` calls
/// [writeDiscoveredPlugins] on every build, declaring the package graph and
/// every pubspec it read as dependencies so a new plugin dependency reruns
/// it. `dart run flutter3d_build:plugins` does the same by hand, for the
/// first time — before any build, so the file exists when the analyzer and
/// an editor first look — and for a project that does not use the hook.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginException;
import 'package:flutter3d_shaders/flutter3d_shaders.dart' show ShaderStageNeed;
import 'package:yaml/yaml.dart';

/// One plugin class a dependency declares.
final class DiscoveredPlugin {
  /// The class [className] of [package], reached through [import] and
  /// constructed with [arguments]; no arguments by default.
  const DiscoveredPlugin({
    required this.package,
    required this.import,
    required this.className,
    this.arguments = '',
  });

  /// The package that declares it.
  final String package;

  /// The `package:` import the class is reached through.
  final String import;

  /// The class.
  final String className;

  /// What goes between the constructor's parentheses in `plugins.g.dart`:
  /// empty for a plugin taken as its package marks it, the text of the
  /// project's `set:` for one it configures (`threshold: 1.2`).
  final String arguments;

  /// This plugin constructed with [arguments].
  DiscoveredPlugin withArguments(String arguments) => DiscoveredPlugin(
    package: package,
    import: import,
    className: className,
    arguments: arguments,
  );

  @override
  String toString() => '$import#$className';
}

/// Thrown when discovery cannot say what the plugins are: no package
/// config, a marker that cannot be read. The message names the file.
final class PluginDiscoveryException extends PluginException {
  /// The failure [message], naming the file discovery could not read.
  const PluginDiscoveryException(super.message);

  @override
  String toString() => 'PluginDiscoveryException: $message';
}

/// The pubspec key a package declares its plugins under.
const String pluginMarkerKey = 'flutter3d_plugins';

/// The pubspec key a graphics backend from outside the engine declares its
/// material compiler under, so a project's build compiles for it (D26):
///
/// ```yaml
/// flutter3d_backend:
///   backend: acme_vk          # the device's backendId
///   section: acme_vk          # its compiler's bundleSection
///   compiler: bin/material_compiler.dart
/// ```
///
/// `compiler` is a Dart file in the package that runs the compiler with
/// `runMaterialCompiler` from `package:flutter3d_shaders/compile.dart`;
/// `examples/flutter3d_backend_null` is the reference.
const String backendMarkerKey = 'flutter3d_backend';

/// A dependency that is a graphics backend from outside the engine with a
/// material compiler: what its pubspec's [backendMarkerKey] says.
final class BackendCompilerPackage {
  /// The package [name] at [root], compiling [backend]'s [section] with the
  /// Dart file [compiler].
  const BackendCompilerPackage({
    required this.name,
    required this.root,
    required this.backend,
    required this.section,
    required this.compiler,
    required this.packageConfig,
  });

  /// The package's name.
  final String name;

  /// Its root directory, as the package config resolves it.
  final String root;

  /// The backend's id, `MaterialCompiler.backend`.
  final String backend;

  /// The section its compiler writes, `MaterialCompiler.bundleSection`.
  final String section;

  /// The compiler's Dart file, relative to [root].
  final String compiler;

  /// The package config the project resolved, which the compiler runs
  /// against.
  final String packageConfig;

  @override
  String toString() => '$name ($backend)';
}

/// What [pubspec], of [package] at [root], says under [backendMarkerKey],
/// or null when it says nothing. Throws a [PluginDiscoveryException] naming
/// the package for a marker without its three strings.
BackendCompilerPackage? backendCompilerOf(
  String package,
  Map<Object?, Object?> pubspec, {
  required String root,
  required String packageConfig,
}) => switch (pubspec[backendMarkerKey]) {
  null => null,
  {
    'backend': final String backend,
    'section': final String section,
    'compiler': final String compiler,
  } =>
    BackendCompilerPackage(
      name: package,
      root: root,
      backend: backend,
      section: section,
      compiler: compiler,
      packageConfig: packageConfig,
    ),
  _ => throw PluginDiscoveryException(
    '$package: `$backendMarkerKey:` names the backend, the section its '
    'compiler writes and the compiler\'s file, as `backend:`, `section:` and '
    '`compiler:`, each a string',
  ),
};

/// The key plugins were declared under before 1.0, as `flutter3d: plugin:`.
///
/// Still read, with a warning, so a plugin published against 0.8 keeps
/// being discovered. The pubspec's word, not the API's: the constant was
/// public until 1.0.0-rc.1.
const String _legacyPluginMarkerKey = 'flutter3d';

/// What [discoverPlugins] found, and every file it read to find it.
final class PluginDiscovery {
  /// The [plugins] found and the [readFiles] read; every other list empty
  /// unless given.
  const PluginDiscovery({
    required this.plugins,
    required this.readFiles,
    this.warnings = const <String>[],
    this.excluded = const <DiscoveredPlugin>[],
    this.packages = const <PluginPackage>[],
    this.dependencies = const <String>{},
    this.backendCompilers = const <BackendCompilerPackage>[],
  });

  /// Every package the application depends on, directly or through another:
  /// what the shader build asks to see whether a backend that loads the
  /// engine's bundle is among them.
  final Set<String> dependencies;

  /// The graphics backends from outside the engine among [dependencies]
  /// that name a material compiler under [backendMarkerKey], by package
  /// name: what the shader build runs for each one's section (D26).
  final List<BackendCompilerPackage> backendCompilers;

  /// The packages at least one of [plugins] comes from, by name: where each
  /// is, for the build that compiles its materials (D19), and the shader
  /// needs it declares (D15).
  final List<PluginPackage> packages;

  /// The plugins, by package name and then in the order each pubspec lists
  /// them, after the application's `without` and `set`, and then what its
  /// `with` and `set` added.
  final List<DiscoveredPlugin> plugins;

  /// What the dependencies declare that the application's `without` left
  /// out, in the same order.
  final List<DiscoveredPlugin> excluded;

  /// The package config, the package graph when there is one, and each
  /// pubspec read: what a build hook declares as its dependencies.
  final List<String> readFiles;

  /// What a person should change, one sentence each: a dependency that
  /// still marks its plugins with the pre-1.0 `flutter3d: plugin:` key, a
  /// `without` entry that matches nothing, a `with` entry the group already
  /// holds, or a key the project's list does not have.
  final List<String> warnings;
}

/// A package that marks plugins the application installs.
///
/// Its pubspec may say which of the engine's shader stages its plugins draw
/// with, beside the marker:
///
/// ```yaml
/// flutter3d_plugins:
///   plugin: style.dart#ToonLightingAddon
///   shaders: [toon]
/// ```
///
/// and the project's bundle carries them whatever the project declares.
final class PluginPackage {
  /// The package [name] at [root], declaring [shaderNeeds]; none by
  /// default.
  const PluginPackage({
    required this.name,
    required this.root,
    this.shaderNeeds = const <String>[],
  });

  /// The package's name.
  final String name;

  /// Its root directory, as the package config resolves it.
  final String root;

  /// The shader needs its `flutter3d_plugins: shaders:` lists.
  final List<String> shaderNeeds;

  @override
  String toString() => name;
}

/// One entry of an application's `flutter3d_plugins: without:` list, or a
/// `with:` entry or `set:` key: a package, a library of it, or one class of
/// a library (`with` and `set` name a class).
///
/// Written `flutter3d_post`, `flutter3d_post/motion.dart` or
/// `flutter3d_post/motion.dart#MotionBlurAddon`; a leading `package:` is
/// allowed. A library is named as the marker imports it, relative to the
/// package's `lib/`.
final class PluginSelector {
  /// The selector of [package], narrowed to [library] and then to
  /// [className] when they are given.
  const PluginSelector({required this.package, this.library, this.className});

  /// Reads [text], or throws a [PluginDiscoveryException] naming [source]
  /// when it is not one of the three forms.
  factory PluginSelector.parse(String text, {String source = 'pubspec'}) {
    final trimmed = text.trim();
    final body = trimmed.startsWith('package:')
        ? trimmed.substring('package:'.length)
        : trimmed;
    final hash = body.indexOf('#');
    final path = hash < 0 ? body : body.substring(0, hash);
    final className = hash < 0 ? null : body.substring(hash + 1);
    final slash = path.indexOf('/');
    final package = slash < 0 ? path : path.substring(0, slash);
    final library = slash < 0 ? null : path.substring(slash + 1);
    final identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');
    final valid =
        RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(package) &&
        (library == null || library.endsWith('.dart')) &&
        (className == null ||
            (library != null && identifier.hasMatch(className)));
    if (!valid) {
      throw PluginDiscoveryException(
        '$source: "$text" is not a plugin selector; write a package '
        '(`flutter3d_post`), a library (`flutter3d_post/motion.dart`) or a '
        'class (`flutter3d_post/motion.dart#MotionBlurAddon`)',
      );
    }
    return PluginSelector(
      package: package,
      library: library,
      className: className,
    );
  }

  /// The package's name, without a leading `package:`.
  final String package;

  /// The library relative to the package's `lib/`, or null for the whole
  /// package.
  final String? library;

  /// The class, or null for every class of [library].
  final String? className;

  /// The plugin a selector of one class names, as `with:` and `set:` add
  /// it. Only for a selector with a [library] and a [className].
  DiscoveredPlugin get plugin => DiscoveredPlugin(
    package: package,
    import: 'package:$package/$library',
    className: className!,
  );

  /// Whether [plugin] is what this names.
  bool matches(DiscoveredPlugin plugin) =>
      plugin.package == package &&
      (library == null || plugin.import == 'package:$package/$library') &&
      (className == null || plugin.className == className);

  @override
  String toString() => <String>[
    package,
    if (library != null) '/$library',
    if (className != null) '#$className',
  ].join();
}

/// What an application's own pubspec makes of its dependencies' plugins,
/// as `PluginGroup` would: [plugins] [without] what its `without:` names,
/// each plugin its `set:` names constructed with the arguments written (in
/// place, or added at the end), then what its `with:` [add]s. The rest are
/// `excluded`, and each `without` entry that matched nothing and each `with`
/// entry the group already held is a warning.
PluginSelection selectPlugins(
  List<DiscoveredPlugin> plugins, {
  List<PluginSelector> without = const <PluginSelector>[],
  Map<PluginSelector, String> set = const <PluginSelector, String>{},
  List<PluginSelector> add = const <PluginSelector>[],
}) {
  bool admitted(DiscoveredPlugin p) => !without.any((s) => s.matches(p));
  final kept = <DiscoveredPlugin>[
    for (final p in plugins)
      if (admitted(p))
        switch (set.entries.where((e) => e.key.matches(p)).firstOrNull) {
          final MapEntry<PluginSelector, String> e => p.withArguments(e.value),
          null => p,
        },
  ];
  final group = <DiscoveredPlugin>[
    ...kept,
    for (final MapEntry(key: selector, value: arguments) in set.entries)
      if (!kept.any(selector.matches)) selector.plugin.withArguments(arguments),
  ];
  return PluginSelection(
    kept: <DiscoveredPlugin>[
      ...group,
      for (final s in add)
        if (!group.any(s.matches)) s.plugin,
    ],
    excluded: <DiscoveredPlugin>[
      for (final p in plugins)
        if (!admitted(p)) p,
    ],
    warnings: <String>[
      for (final s in without)
        if (!plugins.any(s.matches)) _unmatched(s),
      for (final s in add)
        if (group.any(s.matches)) _alreadyHeld(s),
    ],
  );
}

/// What [selectPlugins] answers: the plugins the application's group holds,
/// the ones its `without:` left out, and what it wrote that did nothing.
final class PluginSelection {
  /// The plugins [kept] and [excluded], with the [warnings] about what did
  /// nothing.
  const PluginSelection({
    required this.kept,
    required this.excluded,
    required this.warnings,
  });

  /// The plugins of the group, in order, each with the arguments its
  /// `set:` gave it, then what `with:` added.
  final List<DiscoveredPlugin> kept;

  /// The dependencies' plugins that `without:` left out.
  final List<DiscoveredPlugin> excluded;

  /// A sentence for each `without:` entry that matched nothing and each
  /// `with:` entry the group already held.
  final List<String> warnings;

  @override
  bool operator ==(Object other) =>
      other is PluginSelection &&
      _sameItems(other.kept, kept, _equal) &&
      _sameItems(other.excluded, excluded, _equal) &&
      _sameItems(other.warnings, warnings, _equal);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(kept),
    Object.hashAll(excluded),
    Object.hashAll(warnings),
  );

  @override
  String toString() =>
      'PluginSelection(${kept.length} kept, ${excluded.length} excluded, '
      '${warnings.length} warnings)';
}

bool _equal(Object? a, Object? b) => a == b;

String _unmatched(PluginSelector s) =>
    '`$pluginMarkerKey: without:` names $s, which no dependency declares; '
    'check the spelling against the package\'s `$pluginMarkerKey: plugin:` '
    'marker.';

String _alreadyHeld(PluginSelector s) =>
    '`$pluginMarkerKey: with:` names $s, which the group already holds; '
    '`set:` is the word for constructing it with arguments.';

/// The keys an application's own `flutter3d_plugins:` may have: a plugin
/// group's three words.
const Set<String> _appKeys = <String>{'without', 'with', 'set'};

/// The `without`, `set` and `with` of [app]'s `flutter3d_plugins:` key, and
/// a warning for each other key it has.
({
  List<PluginSelector> without,
  Map<PluginSelector, String> set,
  List<PluginSelector> add,
  List<String> warnings,
})
_appSelection(Map<Object?, Object?> app, String source) {
  final section = app[pluginMarkerKey];
  final written = section is Map ? section : const <Object?, Object?>{};
  Never wrong(String key, String shape) => throw PluginDiscoveryException(
    '$source: `$pluginMarkerKey: $key:` is $shape',
  );
  PluginSelector oneClass(String key, String text) {
    final selector = PluginSelector.parse(text, source: source);
    if (selector.className == null) {
      wrong(
        key,
        'one class of a library per entry, such as '
        '`flutter3d_post/light.dart#BloomAddon`, and "$text" names more',
      );
    }
    return selector;
  }

  List<String> strings(String key) => switch (written[key]) {
    null => const <String>[],
    final String one => <String>[one],
    final List<Object?> many when many.every((e) => e is String) =>
      many.cast<String>(),
    _ => wrong(key, 'a list of strings'),
  };
  final set = switch (written['set']) {
    null => const <Object?, Object?>{},
    final Map<Object?, Object?> map => map,
    _ => wrong('set', 'a map from a class to its constructor\'s arguments'),
  };
  return (
    without: <PluginSelector>[
      for (final text in strings('without'))
        PluginSelector.parse(text, source: source),
    ],
    set: <PluginSelector, String>{
      for (final MapEntry(:key, :value) in set.entries)
        oneClass('set', '$key'): switch (value) {
          null => '',
          final String text => text.trim(),
          final Object other => '$other',
        },
    },
    add: <PluginSelector>[
      for (final text in strings('with')) oneClass('with', text),
    ],
    warnings: <String>[
      for (final key in written.keys)
        if (!_appKeys.contains(key)) _notAKey(source, '$key'),
    ],
  );
}

String _notAKey(String source, String key) =>
    '$source: `$pluginMarkerKey: $key:` is not a key of the project\'s '
    'plugin list, and is ignored. The list is a plugin group: `without:` '
    'takes plugins out, `set:` constructs one with arguments, `with:` adds '
    'one.';

/// The plugins among the dependencies of the application at [appRoot].
///
/// **Its dependencies, not everything resolved beside it.** In a pub
/// workspace one package config lists every package of the workspace, and
/// a plugin another application depends on is not this one's. So the walk
/// starts from the application's own `dependencies` (not its
/// `dev_dependencies`) and follows each package's dependencies — from
/// `.dart_tool/package_graph.json` when pub wrote one, otherwise from each
/// package's pubspec.
PluginDiscovery discoverPlugins(Directory appRoot) {
  final read = <String>[];
  final appPubspec = File('${appRoot.path}/pubspec.yaml');
  final app = _readPubspec(appPubspec);
  read.add(appPubspec.path);
  final appName = app['name'];
  if (appName is! String) {
    throw PluginDiscoveryException('${appPubspec.path} names no package');
  }

  final config = _findPackageConfig(appRoot);
  read.add(config.path);
  final roots = _packageRoots(config);
  final graphFile = File('${config.parent.path}/package_graph.json');
  final graph = graphFile.existsSync() ? _readGraph(graphFile) : null;
  if (graph != null) read.add(graphFile.path);

  final pubspecs = <String, Map<Object?, Object?>>{};
  Map<Object?, Object?> pubspecOf(String package) =>
      pubspecs.putIfAbsent(package, () {
        final root = roots[package];
        if (root == null) return const <Object?, Object?>{};
        final file = File.fromUri(root.resolve('pubspec.yaml'));
        if (!file.existsSync()) return const <Object?, Object?>{};
        read.add(file.path);
        return _readPubspec(file);
      });

  List<String> dependenciesOf(String package) {
    if (graph != null) return graph[package] ?? const <String>[];
    final deps = pubspecOf(package)['dependencies'];
    return deps is Map ? <String>[for (final k in deps.keys) '$k'] : const [];
  }

  final appDeps = app['dependencies'];
  final reached = <String>{};
  final queue = <String>[
    if (appDeps is Map)
      for (final k in appDeps.keys) '$k',
  ]..sort();
  while (queue.isNotEmpty) {
    final package = queue.removeAt(0);
    if (package == appName || !reached.add(package)) continue;
    // A copy: the graph's own lists, or the empty const one, are not ours to
    // reorder.
    queue.addAll([...dependenciesOf(package)]..sort());
  }

  final plugins = <DiscoveredPlugin>[];
  final warnings = <String>[];
  final backendCompilers = <BackendCompilerPackage>[];
  for (final package in reached.toList()..sort()) {
    if (!roots.containsKey(package)) continue;
    final pubspec = pubspecOf(package);
    if (backendCompilerOf(
          package,
          pubspec,
          root: _withoutTrailingSlash(roots[package]!.toFilePath()),
          packageConfig: config.path,
        )
        case final compiler?) {
      backendCompilers.add(compiler);
    }
    final value = switch (markerOf(pubspec)) {
      PluginMarker(:final value, legacy: false) => value,
      PluginMarker(:final value, legacy: true) => () {
        warnings.add(
          '$package declares its plugins under `flutter3d: plugin:`, the '
          'key before 1.0; it is read until 2.0. Move them to '
          '`$pluginMarkerKey:`.',
        );
        return value;
      }(),
      null => null,
    };
    if (value == null) continue;
    for (final entry in markerEntries(package, value)) {
      plugins.add(_parseMarker(package, entry));
    }
  }
  final selection = _appSelection(app, appPubspec.path);
  final selected = selectPlugins(
    plugins,
    without: selection.without,
    set: selection.set,
    add: selection.add,
  );
  final installedFrom = <String>{
    for (final plugin in selected.kept) plugin.package,
  };
  return PluginDiscovery(
    plugins: selected.kept,
    readFiles: read,
    warnings: <String>[
      ...warnings,
      ...selection.warnings,
      ...selected.warnings,
    ],
    excluded: selected.excluded,
    dependencies: Set<String>.unmodifiable(reached),
    backendCompilers: List<BackendCompilerPackage>.unmodifiable(
      backendCompilers,
    ),
    packages: <PluginPackage>[
      for (final package in installedFrom.toList()..sort())
        if (roots[package] case final root?)
          PluginPackage(
            name: package,
            root: _withoutTrailingSlash(root.toFilePath()),
            shaderNeeds: shaderNeedsOf(
              package,
              pubspecOf(package),
              libraries: <String>{
                for (final plugin in selected.kept)
                  if (plugin.package == package)
                    plugin.import.replaceFirst('package:$package/', ''),
              },
            ),
          ),
    ],
  );
}

String _withoutTrailingSlash(String path) =>
    path.length > 1 && path.endsWith('/')
    ? path.substring(0, path.length - 1)
    : path;

/// The shader needs [package]'s pubspec declares under
/// `flutter3d_plugins: shaders:` (D15): the engine's by name, its own by an
/// id-prefixed name. Empty when it declares none.
///
/// A list is the whole package's. A map, like the `plugin:` marker's, is
/// from a library to its needs, and a library counts only when one of the
/// installed plugins comes from it — [libraries], relative to `lib/` — so an
/// application that leaves `style.dart` out does not carry its toon stages.
List<String> shaderNeedsOf(
  String package,
  Map<Object?, Object?> pubspec, {
  Set<String> libraries = const <String>{},
}) {
  Never wrong() => throw PluginDiscoveryException(
    '$package: `$pluginMarkerKey: shaders:` is a list of shader needs, such '
    'as [toon], or a map from a library to such a list',
  );
  List<String> needsIn(Object? list) {
    if (list is! List || list.any((need) => need is! String)) wrong();
    return <String>[
      for (final need in list.cast<String>())
        if (need.contains('.') ||
            ShaderStageNeed.engine.any((known) => known.name == need))
          need
        else
          throw PluginDiscoveryException(
            '$package: "$need" under `$pluginMarkerKey: shaders:` is not a '
            'shader need; the engine\'s are '
            '${ShaderStageNeed.engine.map((n) => n.name).join(', ')}',
          ),
    ];
  }

  final marker = pubspec[pluginMarkerKey];
  return switch (marker is Map ? marker['shaders'] : null) {
    null => const <String>[],
    final List<Object?> list => needsIn(list),
    final Map<Object?, Object?> byLibrary => <String>{
      for (final MapEntry(key: library, value: needs) in byLibrary.entries)
        if (library is! String)
          ...wrong()
        else if (libraries.contains(library))
          ...needsIn(needs),
    }.toList(),
    _ => wrong(),
  };
}

/// What [pubspec] declares as its plugins, the `plugin:` under
/// [pluginMarkerKey] or, from before 1.0, under `flutter3d:`, and whether it
/// was the old key. Null when it declares none. The new key wins when a
/// pubspec has both.
PluginMarker? markerOf(Map<Object?, Object?> pubspec) =>
    switch ((pubspec[pluginMarkerKey], pubspec[_legacyPluginMarkerKey])) {
      ({'plugin': final Object value}, _) => PluginMarker(
        value: value,
        legacy: false,
      ),
      (_, {'plugin': final Object value}) => PluginMarker(
        value: value,
        legacy: true,
      ),
      _ => null,
    };

/// What [markerOf] answers: a pubspec's `plugin:` value, and whether it sat
/// under the key from before 1.0.
final class PluginMarker {
  /// The marker [value], found under the pre-1.0 key when [legacy].
  const PluginMarker({required this.value, required this.legacy});

  /// The `plugin:` value as the pubspec wrote it: one string, a list of
  /// them, or a map from a library to its classes; [markerEntries] reads it.
  final Object value;

  /// Whether it was under `flutter3d: plugin:`, the key before 1.0, rather
  /// than under [pluginMarkerKey].
  final bool legacy;

  @override
  bool operator ==(Object other) =>
      other is PluginMarker &&
      other.legacy == legacy &&
      _sameYaml(other.value, value);

  @override
  int get hashCode => Object.hash(legacy, switch (value) {
    final String one => one,
    final List<Object?> many => many.length,
    final Map<Object?, Object?> byLibrary => byLibrary.length,
    _ => value,
  });

  @override
  String toString() =>
      'PluginMarker($value${legacy ? ', under the key before 1.0' : ''})';
}

/// Whether two values read from YAML hold the same thing, lists and maps
/// compared entry by entry.
bool _sameYaml(Object? a, Object? b) => switch ((a, b)) {
  (final Map<Object?, Object?> a, final Map<Object?, Object?> b) =>
    a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _sameYaml(a[key], b[key])),
  (final List<Object?> a, final List<Object?> b) => _sameItems(a, b, _sameYaml),
  _ => a == b,
};

/// Whether [a] and [b] are as long and [same] holds for each pair in turn.
bool _sameItems<T>(List<T> a, List<T> b, bool Function(T, T) same) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => same(a[i], b[i]));

/// The `<import>#<Class>` entries a `flutter3d_plugins: plugin:` [value] of
/// [package] names, in its order: one string, a list of them, or a map from
/// a library to the class or list of classes it declares.
List<String> markerEntries(String package, Object? value) {
  Never wrong() => throw PluginDiscoveryException(
    '$package: `$pluginMarkerKey: plugin:` is a string or a list of strings, '
    'each '
    '`<import>#<Class>`, or a map from a library to a class or a list of '
    'classes',
  );
  return switch (value) {
    final String one => <String>[one],
    final List<Object?> many => <String>[
      for (final entry in many) entry is String ? entry : wrong(),
    ],
    final Map<Object?, Object?> byLibrary => <String>[
      for (final MapEntry(key: library, value: classes) in byLibrary.entries)
        if (library is! String)
          wrong()
        else
          for (final className in switch (classes) {
            final String one => <String>[one],
            final List<Object?> many => <String>[
              for (final c in many) c is String ? c : wrong(),
            ],
            _ => wrong(),
          })
            '$library#$className',
    ],
    _ => wrong(),
  };
}

DiscoveredPlugin _parseMarker(String package, Object? entry) {
  final text = entry is String ? entry.trim() : '';
  final hash = text.lastIndexOf('#');
  final import = hash < 0 ? '' : text.substring(0, hash);
  final className = hash < 0 ? '' : text.substring(hash + 1);
  if (!import.endsWith('.dart') ||
      !RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(className)) {
    throw PluginDiscoveryException(
      '$package: the plugin marker "$entry" is not `<import>#<Class>`, '
      'such as `package:$package/$package.dart#MyPlugin`',
    );
  }
  final full = import.startsWith('package:')
      ? import
      : 'package:$package/$import';
  if (!full.startsWith('package:$package/')) {
    throw PluginDiscoveryException(
      '$package: the plugin marker imports "$full", which is not in '
      '$package; a package declares only its own plugins',
    );
  }
  return DiscoveredPlugin(package: package, import: full, className: className);
}

/// `lib/plugins.g.dart` for [plugins].
///
/// A `PluginGroup` the code adjusts as any other
/// (`installedPlugins.without<FogAddon>()`), and a getter, so each engine
/// gets plugins of its own: two engines in one process — an editor and the
/// game it plays — must not share a plugin's state.
String renderPluginsFile(List<DiscoveredPlugin> plugins) {
  final imports = <String>[];
  for (final plugin in plugins) {
    if (!imports.contains(plugin.import)) imports.add(plugin.import);
  }
  final buffer = StringBuffer()
    ..writeln('// Generated by flutter3d_build from the `flutter3d_plugins:`')
    ..writeln('// markers of this package\'s dependencies and its own')
    ..writeln('// `flutter3d_plugins:` `without:`, `set:` and `with:`. Do not')
    ..writeln('// edit: `flutter3d plugins` and every build write it again.')
    ..writeln()
    ..writeln(
      "import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';",
    );
  for (var i = 0; i < imports.length; i++) {
    buffer.writeln("import '${imports[i]}' as p$i;");
  }
  buffer
    ..writeln()
    ..writeln('/// The plugins this package\'s dependencies declare, as the')
    ..writeln('/// project\'s pubspec adjusts them, made afresh on each read.')
    ..writeln(
      'PluginGroup get installedPlugins => PluginGroup(<Flutter3dPlugin>[',
    );
  for (final plugin in plugins) {
    buffer.writeln(
      '  p${imports.indexOf(plugin.import)}.${plugin.className}'
      '(${plugin.arguments}),',
    );
  }
  buffer.writeln(']);');
  return buffer.toString();
}

/// What [writeDiscoveredPlugins] did.
final class PluginsFileReport {
  /// The file at [path], [written] or left alone, and the [discovery] it
  /// was rendered from.
  const PluginsFileReport({
    required this.path,
    required this.written,
    required this.discovery,
  });

  /// The application's `lib/plugins.g.dart`, whether or not it exists.
  final String path;

  /// Whether the file was written; false when it already said this, or
  /// when there was nothing to say and no file to keep current.
  final bool written;

  /// What discovery found, including the files a hook declares as
  /// dependencies.
  final PluginDiscovery discovery;
}

/// Discovers [appRoot]'s plugins and writes `lib/plugins.g.dart`.
///
/// **Writes only what changed, and creates the file only when there is
/// something in it** — or when [always] is set, as the command sets it. A
/// build of an application with no plugin dependency leaves its `lib/`
/// alone; one that already has the file keeps it current, emptied if the
/// last plugin went.
PluginsFileReport writeDiscoveredPlugins(
  Directory appRoot, {
  bool always = false,
}) {
  final discovery = discoverPlugins(appRoot);
  final file = File('${appRoot.path}/lib/plugins.g.dart');
  final text = renderPluginsFile(discovery.plugins);
  final exists = file.existsSync();
  if (!exists && discovery.plugins.isEmpty && !always) {
    return PluginsFileReport(
      path: file.path,
      written: false,
      discovery: discovery,
    );
  }
  if (exists && file.readAsStringSync() == text) {
    return PluginsFileReport(
      path: file.path,
      written: false,
      discovery: discovery,
    );
  }
  file
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);
  return PluginsFileReport(
    path: file.path,
    written: true,
    discovery: discovery,
  );
}

Map<Object?, Object?> _readPubspec(File file) {
  if (!file.existsSync()) {
    throw PluginDiscoveryException('there is no ${file.path}');
  }
  final Object? document;
  try {
    document = loadYaml(file.readAsStringSync());
  } on YamlException catch (error, stackTrace) {
    Error.throwWithStackTrace(
      PluginDiscoveryException('${file.path}: ${error.message}'),
      stackTrace,
    );
  }
  return document is Map ? document : const <Object?, Object?>{};
}

File _findPackageConfig(Directory start) {
  var at = start.absolute;
  while (true) {
    final config = File('${at.path}/.dart_tool/package_config.json');
    if (config.existsSync()) return config;
    final parent = at.parent;
    if (parent.path == at.path) {
      throw PluginDiscoveryException(
        'no .dart_tool/package_config.json at or above ${start.path}; run '
        '`dart pub get` first',
      );
    }
    at = parent;
  }
}

/// Each package's root directory, as a directory URI.
Map<String, Uri> _packageRoots(File config) {
  final Object? json;
  try {
    json = jsonDecode(config.readAsStringSync());
  } on FormatException catch (error, stackTrace) {
    Error.throwWithStackTrace(
      PluginDiscoveryException('${config.path}: ${error.message}'),
      stackTrace,
    );
  }
  final packages = json is Map ? json['packages'] : null;
  if (packages is! List) {
    throw PluginDiscoveryException('${config.path} lists no packages');
  }
  final base = config.absolute.uri;
  return <String, Uri>{
    for (final package in packages)
      if (package is Map &&
          package['name'] is String &&
          package['rootUri'] is String)
        package['name'] as String: _directory(
          base.resolve(package['rootUri'] as String),
        ),
  };
}

Uri _directory(Uri uri) =>
    uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');

Map<String, List<String>>? _readGraph(File file) {
  try {
    final json = jsonDecode(file.readAsStringSync());
    final packages = json is Map ? json['packages'] : null;
    if (packages is! List) return null;
    return <String, List<String>>{
      for (final package in packages)
        if (package is Map && package['name'] is String)
          package['name'] as String: <String>[
            for (final d in (package['dependencies'] as List?) ?? const [])
              '$d',
          ],
    };
  } on FormatException {
    // A graph nobody can read is no graph; the pubspecs say the same.
    return null;
  }
}
