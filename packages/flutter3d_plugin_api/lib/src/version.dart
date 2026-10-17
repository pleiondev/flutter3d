import 'plugin_version.dart';

/// Which plugin API a plugin was written against, and which one the engine
/// provides.
///
/// **Its own version, not the package's.** `flutter3d_plugin_api` moves with
/// the stack's releases like every other package here, but most releases
/// change nothing a plugin calls. A plugin states the API it needs, and the
/// engine answers whether it provides it, so a plugin written for 1.0 keeps
/// installing on every engine that provides 1.x.
///
/// The rule is semver's, cut to the two numbers that matter:
///
/// * a different **major** is a different contract — what `install` is handed
///   changed shape — and nothing installs across it;
/// * a plugin asking for a newer **minor** than the engine has may call a
///   registry or a member this engine does not have, and is refused;
/// * an older minor installs.
final class PluginApiVersion implements Comparable<PluginApiVersion> {
  const PluginApiVersion(this.major, this.minor)
    : assert(major >= 0 && minor >= 0, 'a version is two whole numbers');

  /// Reads `"1.0"`. Throws a [PluginFormatException] naming the text
  /// otherwise.
  factory PluginApiVersion.parse(String text) {
    final match = RegExp(r'^(\d+)\.(\d+)$').firstMatch(text.trim());
    if (match == null) {
      throw PluginFormatException(
        'a plugin API version is MAJOR.MINOR, such as "1.0"',
        text,
      );
    }
    return PluginApiVersion(int.parse(match[1]!), int.parse(match[2]!));
  }

  /// The API this build of the package provides.
  ///
  /// 1.0: the manifest, the host, the loop and event registries, and the
  /// typed slots for render steps, decoders, entity kinds, the editor and
  /// MCP tools.
  ///
  /// **When it moves.** The minor moves in the release that adds anything a
  /// plugin can call: a member of `flutter3d_plugin_api`, `flutter3d_fields`
  /// or `flutter3d_plugin_runtime`, or of a registry another package hands
  /// a plugin (`McpTools`, `RendererSteps`, `ModelDecoders`). A structure
  /// rule compares those against the last 1.x release and fails while the
  /// number has not moved (`docs/CONTRACTS.md`).
  ///
  /// **A plugin writes the number it was written against as a literal**,
  /// `PluginApiVersion(1, 0)`, never `current`: `current` is whatever the
  /// engine it is compiled with provides, so it always passes and says
  /// nothing about what the plugin calls.
  static const PluginApiVersion current = PluginApiVersion(1, 0);
  final int major;

  final int minor;

  /// Why a plugin needing this version cannot install on an engine that
  /// provides [provided], or null when it can.
  ///
  /// A sentence rather than a flag, because the two refusals want different
  /// things done about them: a newer major wants an older plugin or a newer
  /// engine, a newer minor wants a newer engine.
  String? refusalOn(PluginApiVersion provided) {
    if (major != provided.major) {
      return 'it was written against plugin API $this and this engine '
          'provides $provided; a major version changes what install() is '
          'handed, so nothing installs across one. Use a release of the '
          'plugin built for ${provided.major}.x, or an engine that provides '
          '$major.x';
    }
    if (minor > provided.minor) {
      return 'it needs plugin API $this and this engine provides $provided, '
          'so it may call a registry this engine does not have. Update '
          'flutter3d to a release that provides $this';
    }
    return null;
  }

  @override
  int compareTo(PluginApiVersion other) =>
      major != other.major ? major - other.major : minor - other.minor;

  @override
  bool operator ==(Object other) =>
      other is PluginApiVersion && other.major == major && other.minor == minor;

  @override
  int get hashCode => Object.hash(major, minor);

  @override
  String toString() => '$major.$minor';
}
