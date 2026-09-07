import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart';

import 'editor_cubit.dart';

/// Asks the person which document they mean, and answers with its path.
///
/// **The only call into a plugin nobody here can fix, and it is four lines.**
/// The other two plugins this repository uses are packages in it; this one
/// comes off pub.dev, because the system's open panel is the one thing no
/// amount of Dart can produce and is exactly what "open a level" has always
/// meant everywhere else on this machine. Keeping it alone in a function keeps
/// the rest honest: what a path means is `Documents`, which projects are still
/// there is `RecentProjects`, and both are tested with no plugin registered and
/// no window open.
///
/// Null when the panel was dismissed, which is a person saying no rather than
/// anything going wrong — so nobody is told about it.
///
/// The macOS sandbox is off for this application already — see
/// `macos/Runner/*.entitlements`, which explains why — so a chosen path is
/// readable and writable the same way a `--dart-define` one is. The panel is
/// here to save somebody typing a path, not to buy access.
Future<String?> askForLevel() async {
  const level = XTypeGroup(
    label: 'level documents',
    extensions: <String>['json'],
  );
  final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[level]);
  return file?.path;
}

/// The screen for when no document is open yet.
///
/// **A path that is not there is a request to make one**, and answering it
/// with "no such file" and a list of the places looked is the right answer for
/// a typo and the wrong one for somebody starting a game. So: the templates,
/// and underneath them the path that will be written.
///
/// And beside those, the two ways to open something that already exists — the
/// system's open panel, and the projects this editor has had open before. The
/// second is the one that gets used: choosing a level is a question with the
/// same answer most days, and a list of recent projects is that answer already
/// given. Everything a row here does ends in the same place a template does,
/// which is `_openAt` in `main.dart`.
final class EditorChooser extends StatelessWidget {
  const EditorChooser({
    super.key,
    required this.state,
    required this.levelPath,
    required this.recent,
    required this.onCreate,
    required this.onOpen,
  });

  final EditorChoosing state;

  /// Where a new project's level will land — see [kLevelPath] in `main.dart`.
  final String levelPath;

  /// The documents this editor has had open, most recent first, and all of
  /// them still on the disk — see `RecentProjects`.
  final List<String> recent;

  final Future<void> Function(Template template) onCreate;

  /// Opens the document at a path a person picked, whether out of the panel or
  /// out of [recent].
  final Future<void> Function(String path) onOpen;

  @override
  Widget build(BuildContext context) {
    final where = projectAt(
      File(levelPath).isAbsolute
          ? levelPath
          : '${Directory.current.path}/$levelPath',
    );
    return Scaffold(
      backgroundColor: const Color(0xFF14161A),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          // Scrolls, because what is on this screen is now four templates, a
          // button and up to eight projects — and a window short enough to cut
          // one off would cut off the templates, which are what somebody with
          // no projects yet came here for.
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _Heading('Open a level'),
                const SizedBox(height: 6),
                Text(
                  'There is nothing at ${where.level} yet. Open a document from '
                  'anywhere on this machine, come back to one you were working '
                  'on, or write a new project here from a template.',
                  style: const TextStyle(
                    color: Color(0xFF9AA4B2),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                _Row(
                  title: 'Choose a file…',
                  about: 'The open panel, on any .json level document.',
                  onTap: () => unawaited(_choose()),
                ),
                if (recent.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 14),
                  const _Heading('Where you were'),
                  const SizedBox(height: 8),
                  for (final path in recent)
                    _Row(
                      title: projectAt(path).root.split('/').last,
                      about: path,
                      onTap: () => unawaited(onOpen(path)),
                    ),
                ],
                const SizedBox(height: 14),
                const _Heading('Start a game'),
                const SizedBox(height: 8),
                for (final template in state.templates)
                  _Row(
                    title: template.name,
                    about: template.about,
                    onTap: () => unawaited(onCreate(template)),
                  ),
                const SizedBox(height: 10),
                Text(
                  state.said,
                  style: const TextStyle(
                    color: Color(0xFFFFB74D),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The panel, and then the same opening every other row here does.
  Future<void> _choose() async {
    final path = await askForLevel();
    if (path == null) return;
    await onOpen(path);
  }
}

/// One line of the screen that names what is under it.
final class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFFE6EAF0),
      fontSize: 22,
      fontWeight: FontWeight.w700,
    ),
  );
}

/// One thing that can be clicked: a template, a project, or the panel.
///
/// The same shape for all three because they are the same act — after any of
/// them a document is open and this screen is gone — and three different
/// shapes would say they were different acts.
final class _Row extends StatelessWidget {
  const _Row({required this.title, required this.about, required this.onTap});

  final String title;
  final String about;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1F26),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFFFFB74D),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              about,
              style: const TextStyle(color: Color(0xFFCBD3DD), fontSize: 13),
            ),
          ],
        ),
      ),
    ),
  );
}
