import 'dart:convert';

import 'package:flutter3d_game/flutter3d_game.dart'
    show Demo, DemoFormatException, Issue, IssueSink, printIssue;

import 'save_file.dart';
import 'storage/storage.dart';

/// Where the last run is kept as what the player did.
///
/// The same shape as [SaveFile] and stored the same way — per application, on
/// whatever [Storage] the platform has — but a separate document on purpose,
/// for the reason a save and the settings are separate: a save is where the
/// player got to and is read on the next launch, a demo is how they got there
/// and is read by whoever they send it to. Resuming a launch from a demo would
/// replay the run instead of continuing it.
///
/// **One demo, the last run.** A player who hit something strange has the
/// file that reproduces it as soon as the run ends, without having pressed
/// record beforehand — which is when nobody has. A library of named demos is
/// a different feature, and this file's name is the only thing it would change.
final class DemoFile {
  DemoFile({required this.appName, Storage? storage, IssueSink? onIssue})
    : onIssue = onIssue ?? printIssue,
      storage = storage ?? defaultStorage(appName, onIssue: onIssue);

  /// Which game's demo this is. See [SaveFile.appName].
  final String appName;

  /// Where the document is kept. See [Storage].
  final Storage storage;

  /// Where this says what it could not read.
  final IssueSink onIssue;

  static const String _name = 'demo.json';

  /// The last run, or null with a reason said through [onIssue].
  ///
  /// **Never throws**, on [SaveFile.read]'s argument: a demo that cannot be
  /// read is a bug report that has to be written in words instead, which is a
  /// smaller loss than a game that will not launch. The reason is said out
  /// loud rather than swallowed, because "no demo" and "a demo from a newer
  /// build" ask the player to do different things.
  Demo? read() {
    final text = storage.read(_name);
    if (text == null) return null;
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, Object?>) {
        onIssue(Issue('demo: the document is not an object'));
        return null;
      }
      return Demo.fromJson(json);
    } on DemoFormatException catch (error) {
      onIssue(Issue('demo: ${error.message}'));
      return null;
    } catch (error) {
      onIssue(Issue('demo: could not be read ($error)'));
      return null;
    }
  }

  /// Writes the run, and says whether it managed to.
  bool write(Demo demo) => storage.write(
    _name,
    const JsonEncoder.withIndent('  ').convert(demo.toJson()),
  );

  /// Forgets the run.
  void clear() => storage.remove(_name);
}
