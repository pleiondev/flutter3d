/// A guide, read into blocks.
///
/// **A small subset of Markdown, and a lint that holds authors to it.** The app
/// draws a guide with its own widgets and the site draws the same file with
/// markdown-it; two renderers agree only about what both can do. So a guide may
/// use headings, paragraphs, lists, code, emphasis, links and `>` callouts, and
/// [lintTutorial] refuses tables, raw HTML and images rather than letting the
/// two disagree about them.
///
/// No Flutter import, so the tool that writes the site can use it too.
library;

/// A run of text inside a paragraph, a list item or a callout.
sealed class Inline {
  const Inline(this.text);

  final String text;
}

final class Plain extends Inline {
  const Plain(super.text);
}

final class Bold extends Inline {
  const Bold(super.text);
}

final class Italic extends Inline {
  const Italic(super.text);
}

final class CodeSpan extends Inline {
  const CodeSpan(super.text);
}

final class Link extends Inline {
  const Link(super.text, this.url);

  final String url;
}

/// One block of a guide.
sealed class Block {
  const Block();
}

final class Heading extends Block {
  const Heading(this.level, this.text);

  final int level;
  final String text;
}

final class Paragraph extends Block {
  const Paragraph(this.inlines);

  final List<Inline> inlines;
}

final class ListBlock extends Block {
  const ListBlock({required this.ordered, required this.items});

  final bool ordered;
  final List<List<Inline>> items;
}

final class CodeBlock extends Block {
  const CodeBlock(this.language, this.code);

  final String language;
  final String code;
}

/// A `>` block. [kind] is the word in a leading `**Note**` or `**Warning**`,
/// lower-cased, or `note` when there is none.
final class Callout extends Block {
  const Callout(this.kind, this.inlines);

  final String kind;
  final List<Inline> inlines;
}

/// A `{{demo}}` or `{{shot}}` line: what it becomes depends on where the guide
/// is being shown.
final class DirectiveBlock extends Block {
  const DirectiveBlock(this.name);

  final String name;
}

final RegExp _inlinePattern = RegExp(
  r'\*\*(.+?)\*\*|`([^`]+)`|\*(.+?)\*|\[([^\]]+)\]\(([^)\s]+)\)',
);

/// [text] split into its runs of emphasis, code and links.
List<Inline> parseInlines(String text) {
  final List<Inline> out = <Inline>[];
  var at = 0;
  for (final RegExpMatch match in _inlinePattern.allMatches(text)) {
    if (match.start > at) out.add(Plain(text.substring(at, match.start)));
    if (match.group(1) != null) {
      out.add(Bold(match.group(1)!));
    } else if (match.group(2) != null) {
      out.add(CodeSpan(match.group(2)!));
    } else if (match.group(3) != null) {
      out.add(Italic(match.group(3)!));
    } else {
      out.add(Link(match.group(4)!, match.group(5)!));
    }
    at = match.end;
  }
  if (at < text.length) out.add(Plain(text.substring(at)));
  return out;
}

final RegExp _heading = RegExp(r'^(#{1,4})\s+(.*\S)\s*$');
final RegExp _bullet = RegExp(r'^[-*]\s+(.*)$');
final RegExp _numbered = RegExp(r'^\d+\.\s+(.*)$');
final RegExp _fence = RegExp(r'^```(\w*)\s*$');
final RegExp _standalone = RegExp(r'^\{\{\s*(demo|shot)\s*\}\}\s*$');

/// [markdown] as blocks. Directives that quote code must have been expanded
/// already, so what arrives here is plain Markdown.
List<Block> parseTutorial(String markdown) {
  final List<String> lines = markdown.split('\n');
  final List<Block> blocks = <Block>[];
  var i = 0;

  bool blank(String line) => line.trim().isEmpty;

  while (i < lines.length) {
    final String line = lines[i];
    if (blank(line)) {
      i++;
      continue;
    }

    final RegExpMatch? fence = _fence.firstMatch(line);
    if (fence != null) {
      final List<String> code = <String>[];
      i++;
      while (i < lines.length && !_fence.hasMatch(lines[i])) {
        code.add(lines[i++]);
      }
      i++;
      blocks.add(CodeBlock(fence.group(1) ?? '', code.join('\n')));
      continue;
    }

    final RegExpMatch? heading = _heading.firstMatch(line);
    if (heading != null) {
      blocks.add(Heading(heading.group(1)!.length, heading.group(2)!));
      i++;
      continue;
    }

    final RegExpMatch? directive = _standalone.firstMatch(line);
    if (directive != null) {
      blocks.add(DirectiveBlock(directive.group(1)!));
      i++;
      continue;
    }

    if (line.startsWith('>')) {
      final List<String> quoted = <String>[];
      while (i < lines.length && lines[i].startsWith('>')) {
        quoted.add(lines[i].replaceFirst(RegExp(r'^>\s?'), ''));
        i++;
      }
      final String joined = quoted.join(' ').trim();
      final RegExpMatch? kind = RegExp(
        r'^\*\*(Note|Warning|Tip)[:.]?\*\*[:.]?\s*',
      ).firstMatch(joined);
      blocks.add(
        Callout(
          kind?.group(1)!.toLowerCase() ?? 'note',
          parseInlines(kind == null ? joined : joined.substring(kind.end)),
        ),
      );
      continue;
    }

    final bool ordered = _numbered.hasMatch(line);
    if (ordered || _bullet.hasMatch(line)) {
      final RegExp marker = ordered ? _numbered : _bullet;
      final List<List<Inline>> items = <List<Inline>>[];
      while (i < lines.length && marker.hasMatch(lines[i])) {
        items.add(parseInlines(marker.firstMatch(lines[i])!.group(1)!));
        i++;
      }
      blocks.add(ListBlock(ordered: ordered, items: items));
      continue;
    }

    final List<String> paragraph = <String>[];
    while (i < lines.length &&
        !blank(lines[i]) &&
        !_fence.hasMatch(lines[i]) &&
        !_heading.hasMatch(lines[i]) &&
        !lines[i].startsWith('>') &&
        !_bullet.hasMatch(lines[i]) &&
        !_numbered.hasMatch(lines[i]) &&
        !_standalone.hasMatch(lines[i])) {
      paragraph.add(lines[i++].trim());
    }
    blocks.add(Paragraph(parseInlines(paragraph.join(' '))));
  }
  return blocks;
}

/// The reasons [markdown] is not a valid guide, one sentence each; empty when
/// it is.
///
/// Checked on the guide as written, before directives are expanded, because
/// what an author controls is that file. A guide has a title and at least three
/// steps, `## Step 1: …` onward without a gap, and each step quotes a region:
/// a step with no code is a paragraph, and the point of a guide here is that the
/// reader sees the lines that make the thing work.
List<String> lintTutorial(String markdown) {
  final List<String> problems = <String>[];
  final List<String> lines = markdown.split('\n');
  var inFence = false;

  if (lines.isEmpty || !lines.first.startsWith('# ')) {
    problems.add('the first line is not a "# Title"');
  }

  final List<int> steps = <int>[];
  final Map<int, bool> hasCode = <int, bool>{};
  int? current;

  for (var n = 0; n < lines.length; n++) {
    final String line = lines[n];
    if (_fence.hasMatch(line) || line.startsWith('```')) {
      inFence = !inFence;
      if (current != null && inFence) hasCode[current] = true;
      continue;
    }
    if (inFence) continue;

    if (line.contains(RegExp(r'^\s*\|.*\|\s*$'))) {
      problems.add('line ${n + 1}: a table; the app cannot draw one');
    }
    if (line.contains(RegExp(r'!\[[^\]]*\]\('))) {
      problems.add('line ${n + 1}: an image; use {{shot}} on the site');
    }
    final String withoutCode = line.replaceAll(RegExp(r'`[^`]*`'), '');
    if (RegExp(r'</?[a-zA-Z][^>]*>').hasMatch(withoutCode)) {
      problems.add('line ${n + 1}: raw HTML');
    }

    final RegExpMatch? step = RegExp(r'^## Step (\d+):\s+\S').firstMatch(line);
    if (step != null) {
      current = int.parse(step.group(1)!);
      steps.add(current);
    }
    if (RegExp(r'^\{\{\s*(code|source)\b').hasMatch(line) && current != null) {
      hasCode[current] = true;
    }
  }
  if (inFence) problems.add('a code fence is never closed');

  if (steps.length < 3) {
    problems.add('${steps.length} steps; a guide has at least three');
  }
  for (var k = 0; k < steps.length; k++) {
    if (steps[k] != k + 1) {
      problems.add('steps are not numbered from 1 without a gap');
      break;
    }
  }
  for (final int step in steps) {
    if (hasCode[step] != true) {
      problems.add('Step $step quotes no code; add a {{code region}} line');
    }
  }
  return problems;
}

/// The step numbers a guide has, in order, for a page that scrolls to one.
List<int> stepsOf(String markdown) => <int>[
  for (final String line in markdown.split('\n'))
    if (RegExp(r'^## Step (\d+):').firstMatch(line) case final RegExpMatch m)
      int.parse(m.group(1)!),
];
