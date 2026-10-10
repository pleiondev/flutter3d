import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// What an application allows the plugins it loads at run time.
///
/// **Decision 6 of `tasks/0.9-plugins.md`, where it can be kept.** A Dart
/// plugin is compiled in and trusted as any dependency is. A plugin read
/// while the game runs — a `.f3dplugin` document, a Wasm module, a script —
/// gets nothing it is not handed, and what it is handed goes through here:
/// a permission it uses must be declared in its manifest *and* granted by
/// the application. Declared and not granted is a refusal when the plugin
/// is loaded, with the permission named; used and not declared is a refusal
/// at the use.
///
/// ```dart
/// final loader = DataPluginLoader(
///   grants: PluginGrants([PluginPermission.network]),
///   fetch: myFetch,
/// );
/// ```
final class PluginGrants {
  /// Grants [granted]. Not `const`: a permission compares by name, so a set
  /// of them is built at run time.
  PluginGrants(Iterable<PluginPermission> granted)
    : granted = Set<PluginPermission>.unmodifiable(granted);

  const PluginGrants._none() : granted = const <PluginPermission>{};

  /// Nothing granted: a run-time plugin reaches its own files and the
  /// world's fields and nothing else.
  static const PluginGrants none = PluginGrants._none();

  /// What the application allows.
  final Set<PluginPermission> granted;

  /// Why a plugin with [manifest] may not be loaded here, or null when every
  /// permission it declares is granted.
  String? refusalOf(PluginManifest manifest) {
    final missing = <String>[
      for (final permission in manifest.permissions)
        if (!granted.contains(permission)) permission.name,
    ];
    if (missing.isEmpty) return null;
    return 'plugin "${manifest.id}" asks for ${missing.join(', ')}, which '
        'this application has not granted. Grant '
        '${missing.length == 1 ? 'it' : 'them'} through PluginGrants, or '
        'load a plugin that does without';
  }

  /// Throws a [PermissionException] unless [manifest] declares [permission]
  /// and it is granted. [forWhat] says what it was needed for, in the
  /// sentence the refusal reads: "to fetch https://…".
  void require(
    PluginManifest manifest,
    PluginPermission permission, {
    required String forWhat,
  }) {
    if (!manifest.permissions.contains(permission)) {
      throw PermissionException(
        'plugin "${manifest.id}" needs ${permission.name} $forWhat and does '
        'not declare it in its manifest\'s permissions',
      );
    }
    if (!granted.contains(permission)) {
      throw PermissionException(
        'plugin "${manifest.id}" needs ${permission.name} $forWhat, and this '
        'application has not granted it',
      );
    }
  }
}

/// A run-time plugin reached for something it was not allowed, with the
/// sentence that says what and why.
final class PermissionException extends PluginException {
  const PermissionException(super.message);

  @override
  String toString() => 'PermissionException: $message';
}
