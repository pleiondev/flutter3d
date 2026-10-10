/// Just enough XML for a MaterialX document: elements, attributes, text
/// ignored. No namespaces, no DTD, no entities beyond the five.
library;

import '../build_exceptions.dart';

/// One element.
final class XmlElement {
  XmlElement(this.name, this.attributes);

  final String name;
  final Map<String, String> attributes;
  final List<XmlElement> children = <XmlElement>[];

  String? operator [](String attribute) => attributes[attribute];

  /// The children called [name].
  Iterable<XmlElement> all(String name) =>
      children.where((XmlElement c) => c.name == name);
}

/// Parses [source] and returns its root element.
///
/// Throws [SourceFormatException] with the line for malformed input.
XmlElement parseXml(String source) {
  final stack = <XmlElement>[];
  XmlElement? root;
  var i = 0;
  int line() => '\n'.allMatches(source.substring(0, i)).length + 1;

  while (i < source.length) {
    final open = source.indexOf('<', i);
    if (open < 0) break;
    i = open;
    if (source.startsWith('<!--', i)) {
      final end = source.indexOf('-->', i);
      if (end < 0) {
        throw SourceFormatException('line ${line()}: unclosed comment');
      }
      i = end + 3;
    } else if (source.startsWith('<?', i)) {
      final end = source.indexOf('?>', i);
      if (end < 0) {
        throw SourceFormatException('line ${line()}: unclosed declaration');
      }
      i = end + 2;
    } else if (source.startsWith('<![CDATA[', i)) {
      final end = source.indexOf(']]>', i);
      if (end < 0) {
        throw SourceFormatException('line ${line()}: unclosed CDATA');
      }
      i = end + 3;
    } else if (source.startsWith('<!', i)) {
      final end = source.indexOf('>', i);
      if (end < 0) {
        throw SourceFormatException('line ${line()}: unclosed declaration');
      }
      i = end + 1;
    } else if (source.startsWith('</', i)) {
      final end = source.indexOf('>', i);
      if (end < 0) throw SourceFormatException('line ${line()}: unclosed tag');
      final name = source.substring(i + 2, end).trim();
      if (stack.isEmpty || stack.last.name != name) {
        throw SourceFormatException(
          'line ${line()}: </$name> closes nothing open',
        );
      }
      stack.removeLast();
      i = end + 1;
    } else {
      final match = _tag.matchAsPrefix(source, i);
      if (match == null) throw SourceFormatException('line ${line()}: bad tag');
      final element = XmlElement(match.group(1)!, <String, String>{
        for (final a in _attribute.allMatches(match.group(2) ?? ''))
          a.group(1)!: _unescape(a.group(2) ?? a.group(3) ?? ''),
      });
      if (stack.isEmpty) {
        root ??= element;
      } else {
        stack.last.children.add(element);
      }
      if (match.group(3) != '/') stack.add(element);
      i = match.end;
    }
  }
  if (root == null) {
    throw const SourceFormatException('no element in the document');
  }
  if (stack.isNotEmpty) {
    throw SourceFormatException('<${stack.last.name}> is never closed');
  }
  return root;
}

final RegExp _tag = RegExp(
  r'<([A-Za-z_][\w:.-]*)((?:\s+[^\s=/>]+\s*=\s*(?:"[^"]*"|'
  "'[^']*'"
  r'))*)\s*(/?)>',
);
final RegExp _attribute = RegExp(
  r'''([^\s=]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
);

String _unescape(String text) => text
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
