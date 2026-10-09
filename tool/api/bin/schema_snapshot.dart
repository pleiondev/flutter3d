/// Writes and checks `api/<package>.mcp` and `api/<package>.vm` for every
/// published package that offers tools to an agent or a VM service to an
/// editor.
///
/// ```
/// cd tool/api
/// dart run api_snapshot:schema_snapshot                    # check them all
/// dart run api_snapshot:schema_snapshot --update           # rewrite them all
/// dart run api_snapshot:schema_snapshot --update flutter3d_mcp
/// dart run api_snapshot:schema_snapshot --print flutter3d_game
/// dart run api_snapshot:schema_snapshot --diff old.mcp new.mcp
/// dart run api_snapshot:schema_snapshot --update --plugin package:wind#WindPlugin
/// ```
///
/// **A plugin's tools** go to its own `api/<package>.plugin.mcp` with
/// `--plugin package:<package>#<Plugin>`, which installs the plugin into an
/// engine with an empty `McpTools` and writes what it added, by namespace.
/// The snapshot's first line names the plugin, so the check reruns it.
///
/// `--check` is the default, as for `api_snapshot`: it exits 1 when a
/// committed snapshot differs from what the source makes, printing each
/// difference classified by `tool/structure/schema.dart` — and `--brief`
/// makes that one line per file, for the structure rule that runs this.
///
/// **Which packages.** Every published package with a `ToolTableServer`
/// subclass in its `lib/` has an `.mcp`; every one that registers a VM
/// service extension or posts a game event has a `.vm`. A snapshot left
/// behind by a package that no longer offers either is reported, so a
/// surface cannot leave without somebody deciding it may.
///
/// **A plugin's tools are not in any of these.** Each server is built here
/// without `projectTools`, so its `.mcp` lists what the server itself offers;
/// the tools plugins add through `McpTools` are published under the plugin's
/// id and are snapshotted, and versioned, by the package that brings them.
/// `flutter3d_mcp`'s `ProjectMcpServer` is listed over an empty registry
/// for the same reason: its own surface is the server, not the project.
library;

import 'dart:io';

import 'package:api_snapshot/api_snapshot.dart';
import 'package:api_snapshot/live_servers.dart';
import 'package:api_snapshot/schema_snapshot.dart';

import '../../structure/api.dart';
import '../../structure/schema.dart';

const String _usage = '''
Writes and checks api/<package>.mcp and api/<package>.vm: the MCP tools and
the VM service surface of every published package that has them.

  dart run api_snapshot:schema_snapshot [--check] [--brief] [package ...]
  dart run api_snapshot:schema_snapshot --update [package ...]
  dart run api_snapshot:schema_snapshot --print <package>
  dart run api_snapshot:schema_snapshot --diff <old> <new>
  dart run api_snapshot:schema_snapshot [--update] --plugin package:<package>#<Plugin>
''';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(_usage);
    return;
  }
  final pluginAt = args.indexOf('--plugin');
  final pluginText = pluginAt >= 0 && pluginAt + 1 < args.length
      ? args[pluginAt + 1]
      : null;
  final named = <String>[
    for (final (i, a) in args.indexed)
      if (!a.startsWith('--') && (pluginAt < 0 || i != pluginAt + 1)) a,
  ];

  if (args.contains('--diff')) {
    if (named.length != 2) {
      stderr.write(_usage);
      exitCode = 2;
      return;
    }
    stdout.writeln(
      describeSchemaChanges(
        classifySchema(
          File(named[0]).readAsStringSync(),
          File(named[1]).readAsStringSync(),
        ),
      ),
    );
    return;
  }

  final root = repositoryRootFrom(Directory.current);
  final packages = repositoryPackages(root);
  final work = Directory('${root.path}/tool/api/.dart_tool/schema_snapshot');

  if (pluginAt >= 0) {
    final source = pluginText == null ? null : parsePluginSource(pluginText);
    if (source == null || !packages.containsKey(source.package)) {
      stderr.write(
        '--plugin takes package:<package>#<Plugin>, a package of this '
        'workspace\n\n$_usage',
      );
      exitCode = 2;
      return;
    }
    final made = renderPluginMcp(
      source,
      pluginSurfaces(
        source,
        Directory('${work.path}/plugin_${source.package}'),
      ),
    );
    final file = File(
      '${packages[source.package]!.path}/${pluginSnapshotPathOf(source.package)}',
    );
    if (args.contains('--print')) {
      stdout.write(made);
    } else if (args.contains('--update')) {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(made);
      stdout.writeln('wrote ${_where(root, file)}');
    } else if (!file.existsSync() || file.readAsStringSync() != made) {
      stdout.writeln(
        '${source.package}: ${pluginSnapshotPathOf(source.package)} is not '
        'what the plugin adds',
      );
      exitCode = 1;
    }
    return;
  }
  final unknown = named.where((String n) => !packages.containsKey(n));
  if (unknown.isNotEmpty) {
    stderr.writeln('no package named ${unknown.join(', ')}\n\n$_usage');
    exitCode = 2;
    return;
  }
  final wanted = named.isNotEmpty
      ? named
      : (packages.keys.where((String n) => isPublished(packages[n]!)).toList()
          ..sort());
  final update = args.contains('--update');
  final brief = args.contains('--brief');
  final print = args.contains('--print');
  var stale = 0;
  for (final name in wanted) {
    final home = packages[name]!;
    final made = <String, String?>{
      mcpSnapshotPathOf(name): await _mcp(name, home, work),
      vmSnapshotPathOf(name): _vm(name, home),
      // A plugin's tools are checked from the plugin its snapshot names, and
      // left alone by --update without --plugin: which plugin class to build
      // is the snapshot's to say.
      if (_pluginSnapshot(name, home) case final (PluginSource, String) p
          when !update)
        pluginSnapshotPathOf(name): renderPluginMcp(
          p.$1,
          pluginSurfaces(p.$1, Directory('${work.path}/plugin_$name')),
        ),
    };
    for (final MapEntry(key: path, value: current) in made.entries) {
      if (print) {
        if (current != null) stdout.write(current);
        continue;
      }
      final file = File('${home.path}/$path');
      final committed = file.existsSync() ? file.readAsStringSync() : null;
      if (committed == current) continue;
      if (update) {
        if (current == null) {
          file.deleteSync();
          stdout.writeln('removed ${_where(root, file)}');
        } else {
          file
            ..createSync(recursive: true)
            ..writeAsStringSync(current);
          stdout.writeln('wrote ${_where(root, file)}');
        }
        continue;
      }
      stale++;
      if (committed == null || current == null) {
        final what = committed == null
            ? 'there is no $path'
            : '$path is left over: the package offers nothing it lists';
        stdout.writeln(brief ? '$name\t$what' : '$name: $what.');
        continue;
      }
      final changes = classifySchema(committed, current);
      if (brief) {
        final breaking = changes.where((ApiChange c) => c.bump == Bump.major);
        stdout.writeln(
          '$name\t$path is not what the source makes: '
          '${breaking.length} breaking, ${changes.length - breaking.length} '
          'other${changes.isEmpty ? ' (only the text moved)' : ''}',
        );
      } else {
        stdout
          ..writeln('$name: $path is not what the source makes.')
          ..writeln(describeSchemaChanges(changes))
          ..writeln();
      }
    }
  }
  if (stale > 0) {
    if (!brief) {
      stdout.writeln(
        'If a change is deliberate, decide the version it needs — the '
        "package's and, for a server, its schema version — write it in the "
        'CHANGELOG (a break under a "**Breaking:**" entry), and run '
        '`dart run api_snapshot:schema_snapshot --update <package>` in '
        'tool/api.',
      );
    }
    exitCode = 1;
  }
}

/// [package]'s `.mcp`, or null when it has no server.
Future<String?> _mcp(String package, Directory home, Directory work) async {
  final classes = serverClassesIn(home);
  if (classes.isEmpty) return null;
  final List<ServerSurface> servers;
  if (needsFlutter(home)) {
    servers = serversFromSource(
      package,
      home,
      Directory('${work.path}/$package'),
    );
  } else {
    final live = liveServers[package]?.keys.toList() ?? const <String>[];
    final missing = classes.where((String c) => !live.contains(c));
    if (missing.isNotEmpty) {
      throw StateError(
        '$package declares ${missing.join(', ')}, which liveServers in '
        'tool/api/lib/live_servers.dart does not build: add it there, with '
        'a session over an empty document',
      );
    }
    servers = await liveSurfaces(package);
  }
  return renderMcp(package, servers);
}

/// The plugin [package]'s committed `.plugin.mcp` names, with the text.
(PluginSource, String)? _pluginSnapshot(String package, Directory home) {
  final file = File('${home.path}/${pluginSnapshotPathOf(package)}');
  if (!file.existsSync()) return null;
  final text = file.readAsStringSync();
  final source = pluginSourceIn(text);
  return source == null ? null : (source, text);
}

/// [package]'s `.vm`, or null when it registers and posts nothing.
String? _vm(String package, Directory home) {
  final surface = scanVm(home);
  if (surface.extensions.isEmpty && surface.events.isEmpty) return null;
  return renderVm(package, surface);
}

String _where(Directory root, File file) =>
    file.absolute.path.substring(root.absolute.path.length + 1);
