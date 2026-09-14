/// The tutorial's own Markdown, read off disk and turned into HTML.
///
/// **Read once, at start, like [Config][../config.dart].** A case is a file
/// under `content/learn/modeler/`; the file name (without `.md`) is its slug,
/// a leading `---`-fenced block gives it a title and a one-line summary in the
/// same shape `site/content` already uses, and everything after that block is
/// the case's body, rendered with `package:markdown`.
library;

import 'dart:io';

import 'package:markdown/markdown.dart' as md;

/// One tutorial page: a slug the URL names, a title and summary for the index
/// card, and a body already rendered to HTML.
class LearnCase {
  const LearnCase({
    required this.slug,
    required this.title,
    required this.summary,
    required this.bodyHtml,
  });

  /// The address it is served at: `/learn/modeler/<slug>`.
  final String slug;

  final String title;

  /// The index card's teaser line. Empty when the file's front matter names
  /// none.
  final String summary;

  /// The Markdown body, already rendered — `LearnPage` drops it in as-is.
  final String bodyHtml;
}

/// Reads every `.md` file in [directory], sorted by file name — a case named
/// `01-hello.md` lists and links before `02-onward.md`.
///
/// An absent directory reads as no cases rather than an error: the tutorial
/// route exists before the first case is written.
List<LearnCase> loadLearnCases({String directory = 'content/learn/modeler'}) {
  final dir = Directory(directory);
  if (!dir.existsSync()) return const [];
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [for (final file in files) _read(file)];
}

LearnCase _read(File file) {
  final name = file.uri.pathSegments.last;
  final slug = name.substring(0, name.length - '.md'.length);
  final (front, body) = _splitFrontMatter(file.readAsStringSync());
  return LearnCase(
    slug: slug,
    title: front['title'] ?? slug,
    summary: front['summary'] ?? '',
    bodyHtml: md.markdownToHtml(body, extensionSet: md.ExtensionSet.gitHubWeb),
  );
}

/// Splits a leading `---\n`-delimited block of `key: value` lines from the
/// Markdown that follows it. A file with no such block is all body.
(Map<String, String> front, String body) _splitFrontMatter(String text) {
  if (!text.startsWith('---\n')) return (const {}, text);
  final end = text.indexOf('\n---\n', 4);
  if (end == -1) return (const {}, text);
  final fields = <String, String>{};
  for (final line in text.substring(4, end).split('\n')) {
    final colon = line.indexOf(':');
    if (colon == -1) continue;
    fields[line.substring(0, colon).trim()] = line.substring(colon + 1).trim();
  }
  return (fields, text.substring(end + '\n---\n'.length));
}
