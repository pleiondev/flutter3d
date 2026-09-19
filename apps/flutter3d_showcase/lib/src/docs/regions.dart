/// Quoting the lines of a page that a guide is talking about.
///
/// **The one implementation of it.** The app's Step by step tab, the Source tab
/// and `tool/showcase_bundle.dart`, which writes the pages of the documentation
/// site, all cut regions out of a page file with the functions here. A guide is
/// therefore never a copy of the code: it is a pointer into the file that runs,
/// so a step cannot describe lines that are no longer there, and a test that
/// every pointer resolves is the whole of keeping them honest.
///
/// No Flutter import, so a plain `dart run` can use it.
///
/// A region is a pair of comment lines:
///
///     // #region light  Point a sun at it
///     final sun = LightNode(intensity: 3.0);
///     // #endregion light
///
/// Names are `[a-z0-9-]+`. Regions may nest and may not overlap. The marker
/// lines never appear in anything shown.
library;

/// A region the file does not have, or markers that do not pair up.
final class RegionError implements Exception {
  const RegionError(this.message);

  final String message;

  @override
  String toString() => 'RegionError: $message';
}

final RegExp _start = RegExp(r'^\s*// #region ([a-z0-9-]+)(?:\s+(.*))?$');
final RegExp _end = RegExp(r'^\s*// #endregion(?:\s+([a-z0-9-]+))?\s*$');

bool _isMarker(String line) => _start.hasMatch(line) || _end.hasMatch(line);

/// One region as it was found: its lines with the markers of every region
/// taken out, and the (zero-based) line it starts on in the whole file.
final class Region {
  const Region(this.name, this.title, this.firstLine, this.lastLine);

  final String name;

  /// What follows the name on the marker line, or empty.
  final String title;

  /// The line after the start marker, and the line of the end marker,
  /// zero-based in the file.
  final int firstLine;
  final int lastLine;
}

/// Every region of [source], in the order they open. Throws [RegionError] for
/// a marker that never closes, closes without opening, or closes another
/// region's name.
List<Region> parseRegions(String source) {
  final List<String> lines = source.split('\n');
  final List<Region> found = <Region>[];
  final List<({String name, String title, int at})> open =
      <({String name, String title, int at})>[];
  final Set<String> seen = <String>{};

  for (var i = 0; i < lines.length; i++) {
    final RegExpMatch? begins = _start.firstMatch(lines[i]);
    if (begins != null) {
      final String name = begins.group(1)!;
      if (!seen.add(name)) {
        throw RegionError('region "$name" is opened twice (line ${i + 1})');
      }
      open.add((name: name, title: (begins.group(2) ?? '').trim(), at: i));
      continue;
    }
    final RegExpMatch? ends = _end.firstMatch(lines[i]);
    if (ends != null) {
      if (open.isEmpty) {
        throw RegionError('#endregion with nothing open (line ${i + 1})');
      }
      final ({String name, String title, int at}) top = open.removeLast();
      final String? named = ends.group(1);
      if (named != null && named != top.name) {
        throw RegionError(
          '#endregion $named closes "${top.name}" (line ${i + 1})',
        );
      }
      found.add(Region(top.name, top.title, top.at + 1, i));
    }
  }
  if (open.isNotEmpty) {
    throw RegionError('region "${open.last.name}" is never closed');
  }
  found.sort((Region a, Region b) => a.firstLine.compareTo(b.firstLine));
  return found;
}

/// The names of the regions of [source], in order.
List<String> listRegions(String source) => <String>[
  for (final Region region in parseRegions(source)) region.name,
];

/// The lines of region [name], without any marker line, with the indentation
/// they share taken off.
///
/// Throws [RegionError] when the file has no such region, and names the ones it
/// has, since the usual cause is a typo in a guide.
String extractRegion(String source, String name) {
  final List<Region> regions = parseRegions(source);
  final Region? region = regions
      .where((Region r) => r.name == name)
      .firstOrNull;
  if (region == null) {
    throw RegionError(
      'no region "$name"; the file has: '
      '${regions.map((Region r) => r.name).join(', ')}',
    );
  }
  final List<String> lines = source.split('\n');
  return _dedent(<String>[
    for (var i = region.firstLine; i < region.lastLine; i++)
      if (!_isMarker(lines[i])) lines[i],
  ]);
}

/// [source] with every marker line removed and nothing else touched: what the
/// Source tab shows.
String stripMarkers(String source) =>
    source.split('\n').where((String line) => !_isMarker(line)).join('\n');

/// The zero-based line of [name] in [source] once the markers are stripped,
/// for scrolling the Source tab to a step; null when there is no such region.
int? strippedLineOf(String source, String name) {
  final List<Region> regions = parseRegions(source);
  final Region? region = regions
      .where((Region r) => r.name == name)
      .firstOrNull;
  if (region == null) return null;
  final List<String> lines = source.split('\n');
  var stripped = 0;
  for (var i = 0; i < region.firstLine; i++) {
    if (!_isMarker(lines[i])) stripped++;
  }
  return stripped;
}

String _dedent(List<String> lines) {
  final Iterable<String> code = lines.where((String l) => l.trim().isNotEmpty);
  if (code.isEmpty) return '';
  final int indent = code
      .map((String l) => l.length - l.trimLeft().length)
      .reduce((int a, int b) => a < b ? a : b);
  return lines
      .map(
        (String l) => l.length >= indent ? l.substring(indent) : l.trimLeft(),
      )
      .join('\n')
      .trimRight();
}

final RegExp _directive = RegExp(
  r'^\{\{\s*(code|source)(?:\s+([^}\s]+))?\s*\}\}\s*$',
);

/// [markdown] with each `{{code region}}`, `{{code other-id#region}}` and
/// `{{source}}` line replaced by a fenced `dart` block quoting the page.
///
/// [own] is the source of the page the guide belongs to and [sourceOf] returns
/// the source of another page by id. Other directives (`{{demo}}`, `{{shot}}`)
/// are left as they are: what they become differs between the app and the
/// site, and quoting code is the part both must do the same way.
///
/// Throws [RegionError] for an unresolvable pointer, so a guide that points at
/// nothing stops the build rather than showing an empty block.
String expandDirectives(
  String markdown, {
  required String own,
  String Function(String id)? sourceOf,
}) {
  final List<String> out = <String>[];
  for (final String line in markdown.split('\n')) {
    final RegExpMatch? match = _directive.firstMatch(line);
    if (match == null) {
      out.add(line);
      continue;
    }
    final String kind = match.group(1)!;
    final String? argument = match.group(2);
    if (kind == 'source') {
      out.add('```dart\n${stripMarkers(own).trimRight()}\n```');
      continue;
    }
    if (argument == null) {
      throw const RegionError('{{code}} needs a region name');
    }
    final int hash = argument.indexOf('#');
    final String code;
    if (hash < 0) {
      code = extractRegion(own, argument);
    } else {
      final String id = argument.substring(0, hash);
      final String Function(String id)? other = sourceOf;
      if (other == null) {
        throw RegionError('{{code $argument}} needs a way to read "$id"');
      }
      code = extractRegion(other(id), argument.substring(hash + 1));
    }
    out.add('```dart\n$code\n```');
  }
  return out.join('\n');
}
