import 'package:flutter/foundation.dart';

/// One thing the editor said, and when.
final class LogEntry {
  const LogEntry(this.time, this.text, {this.error = false});

  final DateTime time;
  final String text;

  /// Whether it was a failure — a document that would not open, a save that
  /// did not land — rather than news.
  final bool error;

  /// `12:04:31`, which is as precise as a person reading a log back wants.
  String get clock =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';
}

/// Everything the strip along the top has said, oldest first.
///
/// **The strip says one thing at a time, and the next thing replaces it.**
/// "could not write …" is gone the moment somebody presses an arrow key, and
/// "the running game did not take the material" arrives while they are
/// looking at the picture. The console keeps what the strip only shows, so
/// the sentence that scrolled away can be read again.
///
/// Capped like a game's console, dropping the oldest, so an afternoon of
/// arrow keys is a few hundred kilobytes rather than a leak.
final class EditorLog extends ChangeNotifier {
  EditorLog({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const int limit = 1000;

  final DateTime Function() _clock;
  final List<LogEntry> _entries = <LogEntry>[];

  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_entries);

  void add(String text, {bool error = false}) {
    if (text.isEmpty) return;
    _entries.add(LogEntry(_clock(), text, error: error));
    if (_entries.length > limit) _entries.removeAt(0);
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
