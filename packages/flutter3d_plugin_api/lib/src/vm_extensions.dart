/// The engine's VM service extensions: one door they are registered through,
/// the `ext.flutter3d.version` extension that lists them, and the namespace a
/// plugin's extensions go under.
library;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';

import 'registration.dart';

/// What answers a VM service extension: the method's name and its
/// parameters, every one a string, as `dart:developer` hands them over.
typedef VmExtensionHandler =
    Future<developer.ServiceExtensionResponse> Function(
      String method,
      Map<String, String> parameters,
    );

/// The version of the `ext.flutter3d.*` surface: the names, the parameters
/// each reads and the keys each answers with, as `api/<package>.vm`
/// snapshots them. Announced by `ext.flutter3d.version`.
///
/// It moves by the rule a tool server's schema version does: a new extension
/// or a new optional parameter is a minor, a removed extension or a removed
/// result key a major.
const String vmSchemaVersion = '1.0.0';

/// The extension that answers `{"schemaVersion": …, "extensions": […],
/// "aliases": {…}}`: [vmSchemaVersion], the name of every `ext.flutter3d.*`
/// extension this isolate registered through [registerFlutter3dExtension]
/// and has on now, sorted, and each old name still answering for a renamed
/// one, old name to current.
const String vmVersionExtension = 'ext.flutter3d.version';

/// Every extension registered through [registerFlutter3dExtension] in this
/// isolate, to the handler answering it now (null while switched off).
///
/// **Per isolate, as `dart:developer`'s own table is.** The VM service has one
/// set of extension names per isolate, and a name cannot be registered twice
/// or taken back; this mirrors that table so `ext.flutter3d.version` can list
/// it and a plugin switched off and on again can answer under the name it
/// already holds.
final Map<String, VmExtensionHandler?> _registered =
    <String, VmExtensionHandler?>{};

/// Every old name registered for a renamed extension in this isolate, to the
/// current name it answers for. Like [_registered], it only grows: the VM
/// service cannot forget a name.
final Map<String, String> _aliases = <String, String>{};

/// Whether [name] is an engine extension's name a caller may register:
/// `ext.flutter3d.` and more, and not [vmVersionExtension].
void _checkName(String name, String argument) {
  if (!name.startsWith('ext.flutter3d.') || name == vmVersionExtension) {
    throw ArgumentError.value(
      name,
      argument,
      'an engine extension is named ext.flutter3d.<area>.<verb>, and '
      '$vmVersionExtension is the engine\'s own',
    );
  }
}

/// Registers [name], an `ext.flutter3d.*` extension, to be answered by
/// [handler], and lists it in `ext.flutter3d.version`.
///
/// **[answers] are the keys of the JSON object [handler] answers with**, the
/// optional ones included: what `api/<package>.vm` snapshots as the
/// extension's `->` line, so a key dropped from an answer is a break the
/// structure check names. Nothing reads it at run time; it is declared here,
/// beside the handler, because an answer built by a `toJson()` or a helper
/// cannot be read off the source.
///
/// **[aliases] are old names of an extension that was renamed.** Each is
/// registered too, answers exactly as [name] does, and is listed under
/// `aliases` in `ext.flutter3d.version`, until the next major removes it
/// (CONTRIBUTING.md, "Tools for agents are a contract too": a rename keeps
/// the old name as an alias). An alias follows [name] on and off.
///
/// **The one door for the engine's extensions.** It is
/// `dart:developer`'s `registerExtension` with two things added: the name is
/// held to the `ext.flutter3d.` prefix, and the first call registers
/// [vmVersionExtension], so a tool attached to a running game asks one
/// extension what the others are and which schema they speak.
///
/// Registering a name twice throws an [ArgumentError], as `dart:developer`
/// does. Returns the [Registration] that switches it off: the VM service
/// cannot forget a name, so a switched-off extension answers an error saying
/// so until it is registered again.
Registration registerFlutter3dExtension(
  String name,
  VmExtensionHandler handler, {
  Set<String> answers = const <String>{},
  List<String> aliases = const <String>[],
}) {
  _checkName(name, 'name');
  if (_registered[name] != null) {
    throw ArgumentError.value(name, 'name', 'is already registered');
  }
  for (final alias in aliases) {
    _checkName(alias, 'aliases');
    final held = _aliases[alias];
    if (alias == name ||
        _registered.containsKey(alias) ||
        (held != null && held != name)) {
      throw ArgumentError.value(
        alias,
        'aliases',
        'is already an extension\'s name or another extension\'s alias',
      );
    }
  }
  if (_registered.isEmpty) {
    // Spelled out rather than [vmVersionExtension], so the snapshot of this
    // package lists it.
    developer.registerExtension(
      'ext.flutter3d.version',
      (String method, Map<String, String> parameters) async =>
          developer.ServiceExtensionResponse.result(
            jsonEncode(<String, Object?>{
              'schemaVersion': vmSchemaVersion,
              'extensions': <String>[
                for (final MapEntry(:key, :value) in _registered.entries)
                  if (value != null) key,
              ]..sort(),
              'aliases': <String, String>{
                for (final old in _aliases.keys.toList()..sort())
                  if (_registered[_aliases[old]] != null) old: _aliases[old]!,
              },
            }),
          ),
    );
  }
  final known = _registered.containsKey(name);
  _registered[name] = handler;
  if (!known) developer.registerExtension(name, _dispatchTo(name));
  for (final alias in aliases) {
    if (_aliases.containsKey(alias)) continue;
    _aliases[alias] = name;
    developer.registerExtension(alias, _dispatchTo(name));
  }
  return Registration(() {
    if (identical(_registered[name], handler)) _registered[name] = null;
  });
}

/// What the VM service calls for [name], or for an old name of it: the
/// handler registered under [name] now, or an error while it is off.
VmExtensionHandler _dispatchTo(String name) =>
    (String method, Map<String, String> parameters) async {
      final current = _registered[name];
      if (current == null) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          '$name is switched off: the plugin that registered it is off',
        );
      }
      return current(method, parameters);
    };

/// The engine's VM service extensions, as a registry plugins add theirs to.
///
/// **A plugin's extensions are `ext.flutter3d.<pluginId>.<verb>`.** Through
/// the view [forPlugin] hands a plugin, [register] takes the verb and puts
/// the plugin's id in front, so a plugin's extension never takes a name the
/// engine may want in a later minor, and switching the plugin off switches
/// its extensions off.
base class VmExtensions extends PluginRegistry {
  /// The application's view: it names its extensions in full.
  VmExtensions() : _scope = null;

  VmExtensions._scoped(this._scope);

  final PluginScope? _scope;

  /// The name [verb] is registered under through this view.
  String nameOf(String verb) {
    final scope = _scope;
    return scope == null ? verb : 'ext.flutter3d.${scope.manifest.id}.$verb';
  }

  /// Registers [verb] — a full `ext.flutter3d.*` name through the
  /// application's view, the plugin's own verb through a plugin's — to be
  /// answered by [handler], with the keys it [answers] with and the old
  /// names it keeps as [aliases] (verbs too, through a plugin's view), as
  /// [registerFlutter3dExtension] describes.
  Registration register(
    String verb,
    VmExtensionHandler handler, {
    Set<String> answers = const <String>{},
    List<String> aliases = const <String>[],
  }) {
    final scope = _scope;
    for (final word in <String>[verb, ...aliases]) {
      if (scope != null && !RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(word)) {
        throw ArgumentError.value(
          word,
          'verb',
          'plugin "${scope.manifest.id}" names a verb, one word; its '
              'extension is ext.flutter3d.${scope.manifest.id}.<verb>',
        );
      }
    }
    final registration = registerFlutter3dExtension(
      nameOf(verb),
      handler,
      answers: answers,
      aliases: <String>[for (final alias in aliases) nameOf(alias)],
    );
    scope?.track(registration);
    return registration;
  }

  @override
  VmExtensions forPlugin(PluginScope scope) => VmExtensions._scoped(scope);
}
