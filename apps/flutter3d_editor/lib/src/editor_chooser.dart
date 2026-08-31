import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Material;

import 'editor_cubit.dart';
import 'scaffold.dart';

/// The screen for a level that does not exist yet.
///
/// **A path that is not there is a request to make one**, and answering it
/// with "no such file" and a list of the places looked is the right answer
/// for a typo and the wrong one for somebody starting a game. Both, then: the
/// templates, and underneath them the path that will be written.
final class EditorChooser extends StatelessWidget {
  const EditorChooser({
    super.key,
    required this.state,
    required this.levelPath,
    required this.onCreate,
  });

  final EditorChoosing state;

  /// Where a new project's level will land — see [kLevelPath] in `main.dart`.
  final String levelPath;

  final Future<void> Function(Template template) onCreate;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'Start a game',
                style: TextStyle(
                  color: Color(0xFFE6EAF0),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'There is nothing at ${where.level} yet. A template writes a '
                'project there: a vocabulary, a first level and a model for '
                'each kind of thing.',
                style: const TextStyle(color: Color(0xFF9AA4B2), fontSize: 13),
              ),
              const SizedBox(height: 18),
              for (final template in state.templates)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => unawaited(onCreate(template)),
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
                            template.name,
                            style: const TextStyle(
                              color: Color(0xFFFFB74D),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            template.about,
                            style: const TextStyle(
                              color: Color(0xFFCBD3DD),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                state.said,
                style: const TextStyle(color: Color(0xFFFFB74D), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
