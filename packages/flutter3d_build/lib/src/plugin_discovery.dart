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
/// **An application picks which of them it installs.** Depending on a
/// package installs every plugin it marks, and `flutter3d_post` marks
/// twenty-three. The application's own pubspec narrows that under the same
/// key, with an allow list, a deny list, or both:
///
/// ```yaml
/// flutter3d_plugins:
///   include: [flutter3d_post]               # only these, if given
///   exclude:
///     - flutter3d_post/motion.dart          # a whole library
///     - flutter3d_post/style.dart#ToonLightingAddon   # one class
/// ```
///
/// Each entry is a [PluginSelector]: a package, a library in it, or one
/// class of a library. `include` is applied first, then `exclude`. An entry
/// that matches nothing any dependency declares is reported in
/// [PluginDiscovery.warnings], since a misspelt exclusion would otherwise
/// leave the plugin installed without a word. What was left out is in
/// [PluginDiscovery.excluded].
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
import 'package:yaml/yaml.dart';

/// One plugin class a dependency declares.
final class DiscoveredPlugin {
  const DiscoveredPlugin({
    required this.package,
    required this.import,
    required this.className,
  });

  /// The package that declares it.
  final String package;

  /// The `package:` import the class is reached through.
  final String import;

  /// The class, constructed with no arguments.
  final String className;

  @override
  String toString() => '$import#$className';
}

/// Thrown when discovery cannot say what the plugins are: no package
/// config, a marker that cannot be read. The message names the file.
final class PluginDiscoveryException extends PluginException {
  const PluginDiscoveryException(super.message);

  @override
  String toString() => 'PluginDiscoveryException: $message';
}

/// The pubspec key a package declares its plugins under.
const String pluginMarkerKey = 'flutter3d_plugins';

/// The key plugins were declared under before 1.0, as `flutter3d: plugin:`.
///
/// Still read, with a warning, so a plugin published against 0.8 keeps
/// being discovered. The pubspec's word, not the API's: the constant was
/// public until 1.0.0-rc.1.
const String _legacyPluginMarkerKey = 'flutter3d';

/// What [discoverPlugins] found, and every file it read to find it.
final class PluginDiscovery {
  const PluginDiscovery({
    required this.plugins,
    required this.readFiles,
    this.warnings = const <String>[],
    this.excluded = const <DiscoveredPlugin>[],
  });

  /// The plugins, by package name and then in the order each pubspec lists
  /// them, after the application's `include` and `exclude`.
  final List<DiscoveredPlugin> plugins;

  /// What the dependencies declare that the application's `include` or
  /// `exclude` left out, in the same order.
  final List<DiscoveredPlugin> excluded;

  /// The package config, the package graph when there is one, and each
  /// pubspec read: what a build hook declares as its dependencies.
  final List<String> readFiles;

  /// What a person should change, one sentence each: a dependency that
  /// still marks its plugins with the pre-1.0 `flutter3d: plugin:` key, or
  /// an `include` or `exclude` entry that matches nothing.
  final List<String> warnings;
}

/// One entry of an application's `flutter3d_plugins: include:` or
/// `exclude:` list: a package, a library of it, or one class of a library.
///
/// Written `flutter3d_post`, `flutter3d_post/motion.dart` or
/// `flutter3d_post/motion.dart#MotionBlurAddon`; a leading `package:` is
/// allowed. A library is named as the marker imports it, relative to the
/// package's `lib/`.
final class PluginSelector {
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

  final String package;

  /// The library relative to the package's `lib/`, or null for the whole
  /// package.
  final String? library;

  /// The class, or null for every class of [library].
  final String? className;

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

/// What an application's own pubspec keeps of its dependencies' plugins:
/// the [plugins] its `include` and `exclude` admit, the rest as
/// `excluded`, and a warning for each entry that matched nothing.
({
  List<DiscoveredPlugin> kept,
  List<DiscoveredPlugin> excluded,
  List<String> warnings,
})
selectPlugins(
  List<DiscoveredPlugin> plugins, {
  List<PluginSelector>? include,
  List<PluginSelector> exclude = const <PluginSelector>[],
}) {
  bool admitted(DiscoveredPlugin p) =>
      (include == null || include.any((s) => s.matches(p))) &&
      !exclude.any((s) => s.matches(p));
  String unmatched(String list, PluginSelector s) =>
      '`$pluginMarkerKey: $list:` names $s, which no dependency declares; '
      'check the spelling against the package\'s `$pluginMarkerKey: plugin:` '
      'marker.';
  return (
    kept: <DiscoveredPlugin>[
      for (final p in plugins)
        if (admitted(p)) p,
    ],
    excluded: <DiscoveredPlugin>[
      for (final p in plugins)
        if (!admitted(p)) p,
    ],
    warnings: <String>[
      for (final s in include ?? const <PluginSelector>[])
        if (!plugins.any(s.matches)) unmatched('include', s),
      for (final s in exclude)
        if (!plugins.any(s.matches)) unmatched('exclude', s),
    ],
  );
}

/// The `include` and `exclude` lists of [app]'s `flutter3d_plugins:` key.
/// `include` is null when the pubspec gives none, which admits everything.
({List<PluginSelector>? include, List<PluginSelector> exclude}) _appSelection(
  Map<Object?, Object?> app,
  String source,
) {
  final section = app[pluginMarkerKey];
  List<PluginSelector>? read(String key) {
    final value = section is Map ? section[key] : null;
    return switch (value) {
      null => null,
      final String one => <PluginSelector>[
        PluginSelector.parse(one, source: source),
      ],
      final List<Object?> many => <PluginSelector>[
        for (final entry in many)
          entry is String
              ? PluginSelector.parse(entry, source: source)
              : throw PluginDiscoveryException(
                  '$source: `$pluginMarkerKey: $key:` is a list of strings',
                ),
      ],
      _ => throw PluginDiscoveryException(
        '$source: `$pluginMarkerKey: $key:` is a list of strings',
      ),
    };
  }

  return (
    include: read('include'),
    exclude: read('exclude') ?? const <PluginSelector>[],
  );
}

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
  for (final package in reached.toList()..sort()) {
    if (!roots.containsKey(package)) continue;
    final pubspec = pubspecOf(package);
    final value = switch (markerOf(pubspec)) {
      (final Object value, legacy: false) => value,
      (final Object value, legacy: true) => () {
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
    include: selection.include,
    exclude: selection.exclude,
  );
  return PluginDiscovery(
    plugins: selected.kept,
    readFiles: read,
    warnings: <String>[...warnings, ...selected.warnings],
    excluded: selected.excluded,
  );
}

/// What [pubspec] declares as its plugins, the `plugin:` under
/// [pluginMarkerKey] or, from before 1.0, under `flutter3d:`, and whether it
/// was the old key. Null when it declares none. The new key wins when a
/// pubspec has both.
(Object, {bool legacy})? markerOf(Map<Object?, Object?> pubspec) => switch ((
  pubspec[pluginMarkerKey],
  pubspec[_legacyPluginMarkerKey],
)) {
  ({'plugin': final Object value}, _) => (value, legacy: false),
  (_, {'plugin': final Object value}) => (value, legacy: true),
  _ => null,
};

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
/// A getter rather than a list, so each engine gets plugins of its own:
/// two engines in one process — an editor and the game it plays — must not
/// share a plugin's state.
String renderPluginsFile(List<DiscoveredPlugin> plugins) {
  final imports = <String>[];
  for (final plugin in plugins) {
    if (!imports.contains(plugin.import)) imports.add(plugin.import);
  }
  final buffer = StringBuffer()
    ..writeln('// Generated by flutter3d_build from the `flutter3d_plugins:`')
    ..writeln('// markers of this package\'s dependencies. Do not edit:')
    ..writeln('// `dart run flutter3d_build:plugins` and every build write it')
    ..writeln('// again. Pass a list of your own to the engine to override it.')
    ..writeln()
    ..writeln(
      "import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';",
    );
  for (var i = 0; i < imports.length; i++) {
    buffer.writeln("import '${imports[i]}' as p$i;");
  }
  buffer
    ..writeln()
    ..writeln('/// The plugins this package\'s dependencies declare, made')
    ..writeln('/// afresh on each read.')
    ..writeln(
      'List<Flutter3dPlugin> get installedPlugins => <Flutter3dPlugin>[',
    );
  for (final plugin in plugins) {
    buffer.writeln(
      '  p${imports.indexOf(plugin.import)}.${plugin.className}(),',
    );
  }
  buffer.writeln('];');
  return buffer.toString();
}

/// What [writeDiscoveredPlugins] did.
final class PluginsFileReport {
  const PluginsFileReport({
    required this.path,
    required this.written,
    required this.discovery,
  });

  final String path;

  /// Whether the file was written; false when it already said this, or
  /// when there was nothing to say and no file to keep current.
  final bool written;

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
  } on YamlException catch (error) {
    throw PluginDiscoveryException('${file.path}: ${error.message}');
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
  } on FormatException catch (error) {
    throw PluginDiscoveryException('${config.path}: ${error.message}');
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
