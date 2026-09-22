/// Everything the editor has said, kept — `ux-26`.
///
/// **The status line says one sentence and forgets it.** That is right for a
/// status line and wrong for a session: a refusal read while somebody was
/// looking at the viewport is gone by the time they look down, an import
/// that warned about three objects leaves one sentence about the last of
/// them, and an agent working in the same document says things while the
/// person is somewhere else in the window. So every sentence lands here as
/// well, with who said it and when.
///
/// **A value with no Flutter in it**, so the panel that draws it and the MCP
/// tool that answers with it read the same list, and a test can ask what ten
/// commands leave behind without a window.
library;

/// Who said it.
enum ConsoleAuthor {
  /// The person at the keyboard — a command run from the rail, a file
  /// written, a refusal their own click earned.
  person,

  /// Whatever is on the other end of the MCP socket.
  agent;

  /// The word the panel's own filter shows.
  String get label => switch (this) {
    ConsoleAuthor.person => 'You',
    ConsoleAuthor.agent => 'Agent',
  };
}

/// How loudly it was said.
///
/// The same three levels `StatusTone` already draws the strip in, named here
/// rather than reused from it because that enum is about a project's export
/// readiness and this is about one sentence — sharing a type would put the
/// panel in the position of asking a message whether the model exports.
enum ConsoleKind {
  /// Something happened: a file opened, an operation run.
  report,

  /// Something will disappoint somebody later — an n-gon, a shell wound
  /// inside out, an object the device could not show.
  warning,

  /// Something was refused and nothing happened.
  refusal,
}

/// One line of the console.
final class ConsoleEntry {
  const ConsoleEntry({
    required this.at,
    required this.text,
    required this.author,
    this.kind = ConsoleKind.report,
    this.tool,
  });

  /// When it was said, by the clock the caller keeps — the cubit's own, so a
  /// test can hand over a fixed one and assert an order rather than a race.
  final DateTime at;

  final String text;
  final ConsoleAuthor author;
  final ConsoleKind kind;

  /// The MCP tool that caused it, when one did. Null for everything a person
  /// did, and for anything an agent's call led to indirectly.
  final String? tool;

  /// What `get_console` answers with — the whole entry, since an agent
  /// reading its own session back has no panel to look at.
  Map<String, Object?> toJson() => <String, Object?>{
    'at': at.toIso8601String(),
    'text': text,
    'author': author.name,
    'kind': kind.name,
    if (tool != null) 'tool': tool,
  };
}

/// The console's own list, oldest first.
///
/// **Bounded, and it drops the oldest.** A session left open all day would
/// otherwise keep every sentence a drag ever produced; two hundred is more
/// than anybody scrolls back through and small enough that an agent asking
/// for the whole thing gets an answer rather than a transcript.
///
/// **Mutable, unlike most of this application's state.** It is a log: the
/// only thing ever done to it is appending, and copying two hundred entries
/// on every sentence — several a second while somebody drags — to preserve a
/// habit would be the habit costing more than it is worth. The cubit hands
/// out an unmodifiable view of it.
final class ConsoleLog {
  ConsoleLog({this.limit = 200});

  /// The most entries kept.
  final int limit;

  final List<ConsoleEntry> _entries = <ConsoleEntry>[];

  /// Every entry, oldest first.
  List<ConsoleEntry> get entries => List<ConsoleEntry>.unmodifiable(_entries);

  int get length => _entries.length;

  /// Adds [entry], dropping the oldest if that takes the log over [limit].
  void add(ConsoleEntry entry) {
    _entries.add(entry);
    if (_entries.length > limit) {
      _entries.removeRange(0, _entries.length - limit);
    }
  }

  /// The entries since [when], exclusive — what `get_console {since}`
  /// answers with, and the shape an agent polling it wants: hand back the
  /// `at` of the last entry you saw and get only what has happened since.
  ///
  /// Null asks for everything. An entry stamped exactly [when] is *not*
  /// returned: it is the one the caller already has.
  List<ConsoleEntry> since(DateTime? when) => <ConsoleEntry>[
    for (final ConsoleEntry entry in _entries)
      if (when == null || entry.at.isAfter(when)) entry,
  ];

  /// The entries [author] left, or all of them when it is null — the panel's
  /// own filter.
  List<ConsoleEntry> by(ConsoleAuthor? author) => <ConsoleEntry>[
    for (final ConsoleEntry entry in _entries)
      if (author == null || entry.author == author) entry,
  ];
}
