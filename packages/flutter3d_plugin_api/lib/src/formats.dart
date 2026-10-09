/// The registry that knows the formats an engine reads.
///
/// What a format is — [FormatSpec], the envelope, [FormatDocument] — is
/// `flutter3d_foundation`'s, re-exported by this package; what is here is
/// the registry a plugin adds its formats to, and what it refuses.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';

import 'registration.dart';

/// A format a [FormatRegistry] would not take: an id, alias or suffix that is
/// another format's, a plugin's id outside its namespace, or a plugin's
/// format with no fixture.
///
/// **A [PluginException]**, because the formats come from plugins and the
/// application's own list — data a correct program can be handed — and a
/// plugin manager reports it as the install that failed.
final class FormatRegistrationException extends PluginException {
  const FormatRegistrationException(super.message);

  @override
  String toString() => 'FormatRegistrationException: $message';
}

/// The formats an engine reads and writes, by id, suffix and first bytes.
///
/// **Also a [PluginRegistry]**, so a plugin that brings a format registers it
/// here and is held to the same rules as the engine's own: an id in its own
/// namespace (`<pluginId>.<kind>`), a version, and fixtures. One registry per
/// engine; nothing is global.
base class FormatRegistry extends PluginRegistry {
  /// A registry holding [formats], each registered as the application's.
  FormatRegistry([Iterable<FormatSpec> formats = const <FormatSpec>[]]) {
    for (final spec in formats) {
      _add(spec, owner: null);
    }
  }

  final Map<String, FormatSpec> _byId = <String, FormatSpec>{};
  final Map<String, String?> _owners = <String, String?>{};

  /// Every format registered, in the order it was added.
  Iterable<FormatSpec> get formats => _byId.values;

  /// The format named [id], under its own id or an alias; null when none is
  /// registered.
  FormatSpec? byId(String id) {
    final direct = _byId[id];
    if (direct != null) return direct;
    for (final spec in _byId.values) {
      if (spec.aliases.contains(id)) return spec;
    }
    return null;
  }

  /// The format a file at [path] is saved as, by its longest matching
  /// suffix; null when no format claims it.
  FormatSpec? forPath(String path) {
    FormatSpec? best;
    var bestLength = 0;
    final lower = path.toLowerCase();
    for (final spec in _byId.values) {
      for (final suffix in spec.suffixes) {
        if (lower.endsWith(suffix.toLowerCase()) &&
            suffix.length > bestLength) {
          best = spec;
          bestLength = suffix.length;
        }
      }
    }
    return best;
  }

  /// The format [head] — the first bytes of a file — is, by a binary
  /// format's magic or a JSON document's `"format"`; null when neither says.
  ///
  /// Reads only what it is given, so 256 bytes is enough for every format
  /// the engine writes: the envelope is the first thing in a document.
  FormatSpec? sniff(List<int> head) {
    for (final spec in _byId.values) {
      final magic = spec.magic;
      if (magic == null || head.length < magic.length) continue;
      var same = true;
      for (var i = 0; i < magic.length && same; i++) {
        same = head[i] == magic[i];
      }
      if (same) return spec;
    }
    final text = String.fromCharCodes(
      head.where((int b) => b >= 0x20 && b < 0x7f),
    );
    final said = RegExp(r'"format"\s*:\s*"([^"]+)"').firstMatch(text)?[1];
    return said == null ? null : byId(said);
  }

  /// Adds [spec] for the application. Throws a [FormatRegistrationException]
  /// when its id, an alias or a suffix is already another format's, or it
  /// has no version.
  Registration add(FormatSpec spec) => _add(spec, owner: null);

  Registration _add(FormatSpec spec, {required String? owner}) {
    for (final name in <String>[spec.id, ...spec.aliases]) {
      final held = byId(name);
      if (held != null) {
        throw FormatRegistrationException(
          'format "$name" is already registered'
          '${_owners[held.id] == null ? '' : ' by ${_owners[held.id]}'}',
        );
      }
    }
    for (final suffix in spec.suffixes) {
      final held = forPath('x$suffix');
      if (held != null && held.suffixes.contains(suffix)) {
        throw FormatRegistrationException(
          'suffix "$suffix" is already the "${held.id}" format\'s',
        );
      }
    }
    if (spec.version < 1) {
      throw FormatRegistrationException('format "${spec.id}" has no version');
    }
    _byId[spec.id] = spec;
    _owners[spec.id] = owner;
    return Registration(() {
      _byId.remove(spec.id);
      _owners.remove(spec.id);
    });
  }

  @override
  FormatRegistry forPlugin(PluginScope scope) => _PluginFormats(this, scope);
}

/// [FormatRegistry] as one plugin sees it: ids in its namespace, every
/// registration tracked so switching the plugin off takes its formats out.
final class _PluginFormats extends FormatRegistry {
  _PluginFormats(this._inner, this._scope);

  final FormatRegistry _inner;
  final PluginScope _scope;

  @override
  Iterable<FormatSpec> get formats => _inner.formats;

  @override
  FormatSpec? byId(String id) => _inner.byId(id);

  @override
  FormatSpec? forPath(String path) => _inner.forPath(path);

  @override
  FormatSpec? sniff(List<int> head) => _inner.sniff(head);

  @override
  Registration add(FormatSpec spec) {
    final plugin = _scope.manifest.id;
    // The aliases too: an alias is an id a document may carry, and one
    // outside the plugin's namespace would take a name the engine, or
    // another plugin, may want.
    for (final name in <String>[spec.id, ...spec.aliases]) {
      if (!name.startsWith('$plugin.')) {
        throw FormatRegistrationException(
          'plugin "$plugin" registered format "${spec.id}"'
          '${name == spec.id ? '' : ' with the alias "$name"'}: a plugin\'s '
          'format ids and aliases start with its own id, "$plugin.<kind>"',
        );
      }
    }
    if (spec.fixture == null) {
      throw FormatRegistrationException(
        'plugin "$plugin" registered format "${spec.id}" with no fixture: '
        'every version of a format needs a file minted at it',
      );
    }
    final registration = _inner._add(spec, owner: plugin);
    _scope.track(registration);
    return registration;
  }
}
