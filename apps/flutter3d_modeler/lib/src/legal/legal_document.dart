/// The legal documents as the application reads them — `rel-21d`.
///
/// **A parser for the subset these six files actually use, rather than a
/// Markdown package.** The alternative was a dependency that renders every
/// construct CommonMark defines, for six documents that between them use
/// headings, paragraphs, two kinds of list, tables, fenced code and four
/// inline marks. The parser below is that list and nothing else, it is a
/// hundred lines, and `test/legal_documents_test.dart` runs it over the real
/// documents rather than over samples — so the thing being checked is the
/// thing being shipped.
///
/// **It fails soft.** A construct it does not know about comes through as the
/// text that was written, marks and all. That is the right failure for a legal
/// text: a reader seeing `**` around a word has still read the word, where a
/// parser that dropped what it did not understand would quietly lose a clause.
library;

/// One run of text, with whatever marks were on it.
///
/// Records rather than a class hierarchy: nothing here needs to be subclassed,
/// and a span is a value the renderer turns into one `TextSpan`.
typedef LegalSpan = ({String text, bool strong, bool code, String? href});

/// Plain text, no marks — the common case, so it has a name.
LegalSpan plainSpan(String text) =>
    (text: text, strong: false, code: false, href: null);

/// One block of a document.
sealed class LegalBlock {
  const LegalBlock();
}

/// `#`, `##` or `###`, by [level].
final class LegalHeading extends LegalBlock {
  const LegalHeading({required this.level, required this.text});

  final int level;
  final List<LegalSpan> text;
}

final class LegalParagraph extends LegalBlock {
  const LegalParagraph(this.text);

  final List<LegalSpan> text;
}

/// A run of `-` items, or of `1.` items when [numbered].
final class LegalList extends LegalBlock {
  const LegalList({required this.items, required this.numbered});

  final List<List<LegalSpan>> items;
  final bool numbered;
}

/// A fenced block, kept exactly as written — the MIT licence text is one, and
/// re-wrapping a licence is not this application's business.
final class LegalCode extends LegalBlock {
  const LegalCode(this.text);

  final String text;
}

/// A pipe table: one header row and the rows under it.
final class LegalTable extends LegalBlock {
  const LegalTable({required this.header, required this.rows});

  final List<List<LegalSpan>> header;
  final List<List<List<LegalSpan>>> rows;
}

/// A whole document: what the front matter says about it, and its blocks.
final class LegalDocument {
  const LegalDocument({
    required this.name,
    required this.title,
    required this.version,
    required this.effective,
    required this.blocks,
    this.description,
  });

  /// The file it came from — `privacy.md`. What a caller addresses it by, and
  /// what the asset path is built from.
  final String name;

  final String title;
  final String? description;

  /// The `version` and `effective` lines of the front matter, shown together
  /// under the title. Empty strings for a document that carries neither, which
  /// no document here does but which must not crash the screen if one ever
  /// does.
  final String version;
  final String effective;

  final List<LegalBlock> blocks;
}

/// [source] parsed, named [name].
LegalDocument parseLegalDocument(String source, {required String name}) {
  final (Map<String, String> front, List<String> lines) = _frontMatter(source);
  return LegalDocument(
    name: name,
    title: front['title'] ?? name,
    description: front['description'],
    version: front['version'] ?? '',
    effective: front['effective'] ?? '',
    blocks: _blocks(lines),
  );
}

/// The `---`-fenced `key: value` head, and everything after it.
///
/// The same three lines the site's own builder reads, restated here rather
/// than shared: this application does not depend on the site's toolchain, and
/// "split on the first colon" is smaller than the import would be.
(Map<String, String>, List<String>) _frontMatter(String source) {
  final List<String> lines = source.split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') {
    return (const <String, String>{}, lines);
  }
  final int end = lines.indexWhere((String it) => it.trim() == '---', 1);
  if (end < 0) return (const <String, String>{}, lines);
  final front = <String, String>{};
  for (final String line in lines.sublist(1, end)) {
    final int at = line.indexOf(':');
    if (at < 0) continue;
    front[line.substring(0, at).trim()] = line.substring(at + 1).trim();
  }
  return (front, lines.sublist(end + 1));
}

List<LegalBlock> _blocks(List<String> lines) {
  final blocks = <LegalBlock>[];
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(LegalParagraph(parseLegalSpans(paragraph.join(' '))));
    paragraph.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    final String line = lines[i];
    final String trimmed = line.trim();

    if (trimmed.isEmpty) {
      flushParagraph();
      continue;
    }

    if (trimmed.startsWith('```')) {
      flushParagraph();
      final code = <String>[];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        code.add(lines[i]);
        i++;
      }
      blocks.add(LegalCode(code.join('\n')));
      continue;
    }

    if (trimmed.startsWith('#')) {
      flushParagraph();
      final int level =
          trimmed.length - trimmed.replaceFirst(RegExp('^#+'), '').length;
      blocks.add(
        LegalHeading(
          level: level.clamp(1, 3),
          text: parseLegalSpans(trimmed.substring(level).trim()),
        ),
      );
      continue;
    }

    if (trimmed.startsWith('|')) {
      flushParagraph();
      final rows = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        rows.add(lines[i].trim());
        i++;
      }
      i--;
      final LegalTable? table = _table(rows);
      if (table != null) {
        blocks.add(table);
      } else {
        // Not a table after all — a line that merely begins with a pipe. Say
        // what was written rather than swallow it.
        blocks.add(LegalParagraph(parseLegalSpans(rows.join(' '))));
      }
      continue;
    }

    final RegExpMatch? bullet = RegExp(
      r'^(-|\d+\.)\s+(.*)$',
    ).firstMatch(trimmed);
    if (bullet != null) {
      flushParagraph();
      final bool numbered = bullet.group(1) != '-';
      final items = <List<String>>[];
      while (i < lines.length) {
        final String at = lines[i].trim();
        final RegExpMatch? next = RegExp(r'^(-|\d+\.)\s+(.*)$').firstMatch(at);
        if (next != null && (next.group(1) != '-') == numbered) {
          items.add(<String>[next.group(2)!]);
        } else if (at.isNotEmpty &&
            items.isNotEmpty &&
            lines[i].startsWith(' ')) {
          // A wrapped continuation of the item above, which is how every list
          // in these documents is written once a line runs past eighty
          // columns.
          items.last.add(at);
        } else {
          break;
        }
        i++;
      }
      i--;
      blocks.add(
        LegalList(
          numbered: numbered,
          items: <List<LegalSpan>>[
            for (final List<String> item in items)
              parseLegalSpans(item.join(' ')),
          ],
        ),
      );
      continue;
    }

    paragraph.add(trimmed);
  }
  flushParagraph();
  return blocks;
}

/// [rows] as a table, or null when the second row is not a `|---|---|` rule —
/// which is what tells a table apart from a paragraph that starts with a pipe.
LegalTable? _table(List<String> rows) {
  if (rows.length < 2) return null;
  if (!RegExp(r'^\|[\s:|-]+\|$').hasMatch(rows[1])) return null;
  List<List<LegalSpan>> cells(String row) => <List<LegalSpan>>[
    for (final String cell in _cells(row)) parseLegalSpans(cell),
  ];
  return LegalTable(
    header: cells(rows.first),
    rows: <List<List<LegalSpan>>>[
      for (final String row in rows.sublist(2)) cells(row),
    ],
  );
}

List<String> _cells(String row) {
  final String inner = row.substring(
    1,
    row.length - (row.endsWith('|') ? 1 : 0),
  );
  return <String>[for (final String cell in inner.split('|')) cell.trim()];
}

/// [text] split into runs by the four inline marks these documents use:
/// `**strong**`, `` `code` ``, `[label](href)` and `<https://autolink>`.
///
/// Marks do not nest here, because none of them nests in the documents. A
/// `**` inside a code span is code, since the code span is found first at that
/// position; anything the scanner does not recognise stays in the text.
List<LegalSpan> parseLegalSpans(String text) {
  final spans = <LegalSpan>[];
  final buffer = StringBuffer();

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(plainSpan(buffer.toString()));
    buffer.clear();
  }

  var at = 0;
  while (at < text.length) {
    final String rest = text.substring(at);

    if (rest.startsWith('`')) {
      final int end = rest.indexOf('`', 1);
      if (end > 0) {
        flush();
        spans.add((
          text: rest.substring(1, end),
          strong: false,
          code: true,
          href: null,
        ));
        at += end + 1;
        continue;
      }
    }

    if (rest.startsWith('**')) {
      final int end = rest.indexOf('**', 2);
      if (end > 0) {
        flush();
        for (final LegalSpan inner in parseLegalSpans(rest.substring(2, end))) {
          spans.add((
            text: inner.text,
            strong: true,
            code: inner.code,
            href: inner.href,
          ));
        }
        at += end + 2;
        continue;
      }
    }

    if (rest.startsWith('[')) {
      final RegExpMatch? link = RegExp(
        r'^\[([^\]]*)\]\(([^)]*)\)',
      ).firstMatch(rest);
      if (link != null) {
        flush();
        spans.add((
          text: link.group(1)!,
          strong: false,
          code: false,
          href: link.group(2),
        ));
        at += link.group(0)!.length;
        continue;
      }
    }

    if (rest.startsWith('<http') || rest.startsWith('<mailto:')) {
      final int end = rest.indexOf('>');
      if (end > 0) {
        flush();
        final String href = rest.substring(1, end);
        spans.add((text: href, strong: false, code: false, href: href));
        at += end + 1;
        continue;
      }
    }

    buffer.write(text[at]);
    at++;
  }
  flush();
  return spans;
}

/// [spans] as the text a person would read, with every mark removed — what a
/// test asserts against, and what a search over a document would match.
String legalPlainText(List<LegalSpan> spans) =>
    spans.map((LegalSpan it) => it.text).join();
