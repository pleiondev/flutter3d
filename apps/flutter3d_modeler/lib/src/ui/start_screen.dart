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

import '../../../l10n/app_localizations.dart';

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

/// One of the four scenario cards was tapped — `ux-42`.
final class ScenarioChoice extends StartChoice {
  const ScenarioChoice(this.scenario);

  final StartScenario scenario;
}

/// "Don't show this at launch" was ticked or unticked — `ux-42`.
///
/// **Its own choice rather than a flag on the others**, because it is a
/// different kind of answer: the rest of this screen says what to do now, and
/// this says what to do next time.
final class ShowAtLaunchChoice extends StartChoice {
  const ShowAtLaunchChoice(this.show);

  final bool show;
}

/// The four ways a session starts, from the tutorial's own four cases —
/// `ux-42`.
///
/// **Four, because the tutorial has four.** Each card lands in the state its
/// case begins from, so somebody following along on the site is where the
/// first paragraph assumes they are rather than one mode and two menus away
/// from it.
enum StartScenario {
  /// Case 1: a scan or a download, brought in and made editable. Opens the
  /// import screen, which is where welding and units are chosen.
  scan(
    'From a scan or a download',
    'Bring in an STL, OBJ or GLB and weld it into something editable.',
    Icons.file_download_outlined,
  ),

  /// Case 2: build it here. A new project, Object mode, the Add menu.
  primitives(
    'From primitives',
    'Start with a box and build the shape out of it.',
    Icons.category_outlined,
  ),

  /// Case 3: a character. A new project in the Full workspace, standing in
  /// Animation mode, which is where a rig is built.
  character(
    'A character',
    'A rig, weights and a clip — the Full workspace, in Animation mode.',
    Icons.accessibility_new_outlined,
  ),

  /// Case 4: a scene. A new project in Scene mode, where the lights are.
  scene(
    'A scene',
    'Lights, environment and the look of it — straight into Scene mode.',
    Icons.light_mode_outlined,
  );

  const StartScenario(this.label, this.about, this.icon);

  final String label;
  final String about;
  final IconData icon;
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
  bool showAtLaunch = true,
  bool offerLaunchChoice = false,
}) => showDialog<StartChoice>(
  context: context,
  builder: (BuildContext context) => StartScreen(
    recentPaths: recentPaths,
    showAtLaunch: showAtLaunch,
    offerLaunchChoice: offerLaunchChoice,
  ),
);

/// Public since `ux-42`: `start_screen_test.dart` pumps it directly rather
/// than through a dialog route, which is the only way to ask what a card does
/// without a window behind it.
class StartScreen extends StatelessWidget {
  const StartScreen({
    super.key,
    required this.recentPaths,
    this.showAtLaunch = true,
    this.offerLaunchChoice = false,
  });

  final List<String> recentPaths;

  /// Whether this screen opens itself at launch — `ux-42`. The checkbox shows
  /// only when [offerLaunchChoice] is set, so a caller that opened this from
  /// the Home button rather than at launch does not offer a setting about a
  /// moment that has already passed.
  final bool showAtLaunch;
  final bool offerLaunchChoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final AppLocalizations l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.startTitle),
      // **Scrolling, since `ux-42` put four scenario cards above Recent.**
      // A `Column` of "Open file", two profiles, four cards and a recent list
      // is taller than a phone and taller than a laptop with a keyboard
      // showing; an `AlertDialog` does not scroll its content on its own, and
      // what it does instead is paint the overflow stripes over the bottom
      // third of the screen.
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_open_outlined),
                title: Text(l10n.openFile),
                onTap: () => Navigator.of(context).pop(const OpenFileChoice()),
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text(l10n.newProject, style: theme.textTheme.labelMedium),
              for (final ProjectProfile profile in kStartProfiles)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add_box_outlined),
                  title: Text(profile.name),
                  onTap: () =>
                      Navigator.of(context).pop(NewProjectChoice(profile)),
                ),
              const SizedBox(height: 8),
              // `ux-42`: the four the tutorial is written around. Above Recent,
              // because a first session has nothing in Recent and this is the
              // screen a first session sees.
              Text(l.startFrom, style: theme.textTheme.labelMedium),
              for (final StartScenario scenario in StartScenario.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(scenario.icon),
                  title: Text(scenario.label),
                  subtitle: Text(
                    scenario.about,
                    style: theme.textTheme.bodySmall,
                  ),
                  onTap: () =>
                      Navigator.of(context).pop(ScenarioChoice(scenario)),
                ),
              if (recentPaths.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(l10n.recent, style: theme.textTheme.labelMedium),
                // Plain rows rather than a `ListView` inside the scroll view
                // above: two scrollables, one inside the other, is a dialog
                // where the recent list scrolls under a finger meant for the
                // page.
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
                    onTap: () =>
                        Navigator.of(context).pop(OpenRecentChoice(path)),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (offerLaunchChoice)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Checkbox(
                value: !showAtLaunch,
                onChanged: (bool? ticked) => Navigator.of(
                  context,
                ).pop(ShowAtLaunchChoice(ticked != true)),
              ),
              const Text("Don't show this at launch"),
              const SizedBox(width: 12),
            ],
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
