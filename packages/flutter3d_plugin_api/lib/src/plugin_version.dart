/// A plugin's own version, the ranges its dependencies accept, and what is
/// thrown when either cannot be read.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';

/// Text that should name a version, a range or a manifest and does not.
///
/// The plugin API's leaf of [Flutter3dFormatException]: a manifest read from
/// a document, a version in a hello, a range in `dependsOn`. [source] is the
/// text or the map that was refused, for the report.
final class PluginFormatException extends Flutter3dFormatException {
  const PluginFormatException(this.message, [this.source]);

  @override
  final String message;

  /// What was being read, when there was something to show.
  final Object? source;

  @override
  String toString() => source == null
      ? 'PluginFormatException: $message'
      : 'PluginFormatException: $message ($source)';
}

/// A plugin's release, by semantic versioning: `1.4.2`, `2.0.0-dev.3`.
///
/// **Distinct from [PluginManifest.apiVersion]** (the plugin API a plugin
/// was written against). This is the plugin's own number, which another
/// plugin's `dependsOn` range is held to and which `SimulationVersion` names
/// beside the plugin's simulation number.
final class PluginVersion implements Comparable<PluginVersion> {
  const PluginVersion(this.major, this.minor, this.patch, {this.preRelease})
    : assert(major >= 0 && minor >= 0 && patch >= 0, 'whole numbers');

  /// What a manifest that names no version is read as: before any release,
  /// which every range from `any` and `>=0.0.0` accepts.
  static const PluginVersion none = PluginVersion(0, 0, 0);

  final int major;
  final int minor;
  final int patch;

  /// The part after `-`, or null for a release.
  final String? preRelease;

  static final RegExp _pattern = RegExp(
    r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.\-]+))?(?:\+[0-9A-Za-z.\-]+)?$',
  );

  /// Reads `1.4.2` or `1.4.2-dev.1`; build metadata after `+` is ignored.
  /// Throws a [PluginFormatException] naming the text otherwise.
  factory PluginVersion.parse(String text) {
    final match = _pattern.firstMatch(text.trim());
    if (match == null) {
      throw PluginFormatException(
        'a plugin version is MAJOR.MINOR.PATCH, such as "1.0.0"',
        text,
      );
    }
    return PluginVersion(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      preRelease: match[4],
    );
  }

  /// The smallest version above every `major.minor.patch-*` release of this
  /// number: the end of a caret range.
  PluginVersion get nextBreaking => major > 0
      ? PluginVersion(major + 1, 0, 0)
      : minor > 0
      ? PluginVersion(0, minor + 1, 0)
      : PluginVersion(0, 0, patch + 1);

  @override
  int compareTo(PluginVersion other) {
    if (major != other.major) return major - other.major;
    if (minor != other.minor) return minor - other.minor;
    if (patch != other.patch) return patch - other.patch;
    final a = preRelease;
    final b = other.preRelease;
    if (a == b) return 0;
    // A release sorts after every pre-release of the same number.
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  bool operator <(PluginVersion other) => compareTo(other) < 0;
  bool operator <=(PluginVersion other) => compareTo(other) <= 0;
  bool operator >(PluginVersion other) => compareTo(other) > 0;
  bool operator >=(PluginVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is PluginVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  @override
  String toString() =>
      '$major.$minor.$patch${preRelease == null ? '' : '-$preRelease'}';
}

/// The versions of a plugin a dependent accepts: `any`, `^1.2.0`,
/// `>=1.0.0 <2.0.0`, `1.4.2`.
///
/// The pub syntax, cut to what a plugin dependency needs: a lower bound that
/// is inclusive, an upper bound that is exclusive, either may be missing.
final class VersionRange {
  const VersionRange({this.min, this.max, this.includeMax = false});

  /// Every version.
  static const VersionRange any = VersionRange();

  /// Exactly [version].
  VersionRange.exactly(PluginVersion version)
    : min = version,
      max = version,
      includeMax = true;

  /// `^version`: from [version] up to the next breaking release.
  VersionRange.compatibleWith(PluginVersion version)
    : min = version,
      max = version.nextBreaking,
      includeMax = false;

  /// The lowest version accepted, inclusive; null for no lower bound.
  final PluginVersion? min;

  /// The version above every accepted one, or the highest accepted one when
  /// [includeMax]; null for no upper bound.
  final PluginVersion? max;

  final bool includeMax;

  /// Reads a range. Throws a [PluginFormatException] naming the text when it
  /// is not one.
  factory VersionRange.parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed == 'any') return any;
    if (trimmed.startsWith('^')) {
      return VersionRange.compatibleWith(
        PluginVersion.parse(trimmed.substring(1)),
      );
    }
    PluginVersion? min;
    PluginVersion? max;
    var includeMax = false;
    var bounded = false;
    for (final part in trimmed.split(RegExp(r'\s+'))) {
      if (part.startsWith('>=')) {
        min = PluginVersion.parse(part.substring(2));
      } else if (part.startsWith('<=')) {
        max = PluginVersion.parse(part.substring(2));
        includeMax = true;
      } else if (part.startsWith('<')) {
        max = PluginVersion.parse(part.substring(1));
      } else if (part.startsWith('>')) {
        throw PluginFormatException(
          'a range starts at a version it includes; write ">=" rather than ">"',
          text,
        );
      } else {
        if (bounded) {
          throw PluginFormatException('a range names one exact version', text);
        }
        return VersionRange.exactly(PluginVersion.parse(part));
      }
      bounded = true;
    }
    return VersionRange(min: min, max: max, includeMax: includeMax);
  }

  /// Whether [version] is in the range.
  bool allows(PluginVersion version) {
    final low = min;
    if (low != null && version < low) return false;
    final high = max;
    if (high == null) return true;
    return includeMax ? version <= high : version < high;
  }

  @override
  bool operator ==(Object other) =>
      other is VersionRange &&
      other.min == min &&
      other.max == max &&
      other.includeMax == includeMax;

  @override
  int get hashCode => Object.hash(min, max, includeMax);

  @override
  String toString() {
    final low = min;
    final high = max;
    if (low == null && high == null) return 'any';
    if (low != null && high != null && includeMax && low == high) {
      return '$low';
    }
    if (low != null &&
        high != null &&
        !includeMax &&
        low.nextBreaking == high) {
      return '^$low';
    }
    return <String>[
      if (low != null) '>=$low',
      if (high != null) '${includeMax ? '<=' : '<'}$high',
    ].join(' ');
  }
}

/// One entry of a manifest's `dependsOn`: a plugin id and the versions of it
/// accepted.
///
/// Written as one string, so a manifest stays a list of names: `'heat'`
/// accepts any version, `'heat ^1.2.0'` and `'heat >=1.0.0 <3.0.0'` a range.
final class PluginDependency {
  const PluginDependency(this.id, [this.range = VersionRange.any]);

  /// Reads `'id'` or `'id <range>'`. Throws a [PluginFormatException] when
  /// the range is not one.
  factory PluginDependency.parse(String text) {
    final trimmed = text.trim();
    final space = trimmed.indexOf(RegExp(r'\s'));
    if (space < 0) return PluginDependency(trimmed);
    return PluginDependency(
      trimmed.substring(0, space),
      VersionRange.parse(trimmed.substring(space + 1)),
    );
  }

  /// The plugin depended on.
  final String id;

  /// Its versions this dependent accepts.
  final VersionRange range;

  /// Why [version] of [id] does not satisfy this dependency, or null when it
  /// does.
  String? refusalOf(PluginVersion version) => range.allows(version)
      ? null
      : 'it needs "$id" $range and "$id" is $version';

  @override
  bool operator ==(Object other) =>
      other is PluginDependency && other.id == id && other.range == range;

  @override
  int get hashCode => Object.hash(id, range);

  @override
  String toString() => range == VersionRange.any ? id : '$id $range';
}
