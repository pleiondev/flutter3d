/// `ui-15`'s own start screen: "Open file", the recent-models list
/// `RecentModels` already keeps, and "New project" with a profile.
///
/// **A dialog, not the launch sequence.** This application always opens a
/// cube the moment a device is ready (`_open()` in `main.dart`) rather than
/// waiting on a "nothing open yet" state — rewiring that sequence is a
/// bigger, riskier change than this row's own `S` size asks for, and the
/// existing behaviour (something to look at immediately, on every platform
/// this ships to) is worth keeping. This screen is reached explicitly
/// instead, the same "modal, not a route" shape `export_screen.dart` already
/// established for this single-screen app.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// What the person chose, or null from [showStartScreen] when they backed
/// out without picking anything.
sealed class StartChoice {
  const StartChoice();
}

/// "Open file" was pressed — the caller's own file picker decides the rest.
final class OpenFileChoice extends StartChoice {
  const OpenFileChoice();
}

/// A row in the recent list was tapped.
final class OpenRecentChoice extends StartChoice {
  const OpenRecentChoice(this.path);

  final String path;
}

/// "New project" was pressed, with the profile the person picked.
final class NewProjectChoice extends StartChoice {
  const NewProjectChoice(this.profile);

  final ProjectProfile profile;
}

/// The two profiles this screen offers — [ProjectProfile]'s own default
/// (unnamed, desktop) and its `mobile` preset are the only two named
/// constants that type exposes; a picker choosing between more than the
/// project itself can name yet would be inventing presets this row was
/// never asked to design.
const List<ProjectProfile> kStartProfiles = <ProjectProfile>[
  ProjectProfile(),
  ProjectProfile.mobile,
];

/// Opens `ui-15`'s own start screen. [recentPaths] is read once, most
/// recent first — the caller already resolved which of `RecentModels`'
/// own entries still exist before handing them here, so this widget stays
/// free of `dart:io`/`package:web` itself.
Future<StartChoice?> showStartScreen(
  BuildContext context, {
  required List<String> recentPaths,
}) => showDialog<StartChoice>(
  context: context,
  builder: (BuildContext context) => _StartScreen(recentPaths: recentPaths),
);

class _StartScreen extends StatelessWidget {
  const _StartScreen({required this.recentPaths});

  final List<String> recentPaths;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Start'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Open file'),
              onTap: () =>
                  Navigator.of(context).pop(const OpenFileChoice()),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text('New project', style: theme.textTheme.labelMedium),
            for (final ProjectProfile profile in kStartProfiles)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_box_outlined),
                title: Text(profile.name),
                onTap: () => Navigator.of(
                  context,
                ).pop(NewProjectChoice(profile)),
              ),
            if (recentPaths.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text('Recent', style: theme.textTheme.labelMedium),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final String path in recentPaths)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(
                          path.split(RegExp(r'[\\/]')).lastOrNull ?? path,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                        onTap: () => Navigator.of(
                          context,
                        ).pop(OpenRecentChoice(path)),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
