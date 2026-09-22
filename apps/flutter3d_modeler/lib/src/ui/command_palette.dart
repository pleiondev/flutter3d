/// Everything the editor can do, by name — `ux-25`.
///
/// **One table for the rail, the keyboard, the palette and the agent.**
/// `tools.dart` is where a tool is written down once: its id, its label, its
/// icon and the rail it sits on. The rail draws the ones for the mode you are
/// in; this draws all of them, says which key the live preset gives each, and
/// says why the ones from another mode are not runnable from here instead of
/// hiding them — a person looking for "Bevel" wants to be told it is in Mesh
/// mode, not to be told nothing.
///
/// **Filtering is a plain substring over the label and the id.** A fuzzy
/// matcher was considered and left out: the list is forty entries, the labels
/// are one or two words, and the failure mode of fuzziness — "bev" finding
/// something that is not Bevel because it happens to share three letters —
/// costs more than it saves at this size.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart'
    show ProjectSelection;

import '../../l10n/app_localizations.dart';
import 'keymap.dart';
import 'shortcut_help.dart' show describeShortcut;
import 'tool_strings.dart';
import 'tools.dart';

/// One line of the palette: what it is, what it would do, and whether it can
/// be done from where the person is standing.
@immutable
final class PaletteEntry {
  const PaletteEntry({
    required this.id,
    required this.label,
    required this.icon,
    required this.mode,
    this.about = '',
    this.keys,
    this.disabledBecause,
  });

  /// `ModelerTool.id` — the same string the rail, the keyboard and
  /// `run_command` all name a tool by.
  final String id;

  final String label;

  /// `ModelerTool.about` — one sentence on what running it does, shown under
  /// the name (`ux-18`).
  ///
  /// **Empty rather than null, and empty means "the name says it".** The two
  /// folds and the legal screen are already sentences: "Fold the properties
  /// panel" leaves nothing for a second line to add, and a subtitle repeating
  /// it would make the list longer without making it clearer.
  final String about;

  final IconData icon;

  /// Which mode this tool belongs to, shown beside the label so the list
  /// reads as a map of the application rather than a flat pile of verbs.
  final ModelerMode mode;

  /// How the live preset spells it, or null where that preset binds nothing.
  final String? keys;

  /// Why running it from here would not work, or null when it would.
  final String? disabledBecause;

  bool get enabled => disabledBecause == null;
}

/// Every tool in the application, as palette entries, with the ones outside
/// [mode] marked with the mode they need.
///
/// [animation] picks which of the animation mode's four rails is listed; the
/// other three are still listed, each named by its own sub-mode, because a
/// person searching for "Paint weights" has not necessarily thought about
/// which sub-mode it lives in.
///
/// [extra] is for the things that are not rail tools and belong here anyway —
/// `ux-27`'s own two folds. They come first, because they are about the
/// window rather than the model and a search for "panel" should find them
/// before it finds a material one.
List<PaletteEntry> paletteEntries({
  required ModelerMode mode,
  required AnimationSubmode animation,
  required Keymap keymap,

  /// `ux-22`: what each tool is called in the language the person picked.
  /// Null lists them in English, which is what a test pumping this list
  /// without a `MaterialApp` gets — and what an agent reading the same
  /// table over MCP sees regardless.
  AppLocalizations? l10n,
  Set<String> unavailable = const <String>{},
  List<PaletteEntry> extra = const <PaletteEntry>[],
}) {
  final entries = <PaletteEntry>[...extra];
  final seen = <String>{for (final PaletteEntry it in extra) it.id};
  void add(ModelerTool tool, ModelerMode from, {String? because}) {
    if (!seen.add(tool.id)) return;
    final ShortcutActivator? key = from == mode
        ? keymap.forTool(tool.id)
        : null;
    entries.add(
      PaletteEntry(
        id: tool.id,
        label: l10n == null ? tool.label : toolLabel(l10n, tool),
        about: l10n == null ? tool.about : toolAbout(l10n, tool),
        icon: tool.icon,
        mode: from,
        keys: key == null ? null : describeShortcut(key),
        disabledBecause: because,
      ),
    );
  }

  for (final ModelerTool tool in toolsFor(mode, animation: animation)) {
    add(
      tool,
      mode,
      because: unavailable.contains(tool.id)
          ? 'nothing it can act on is selected'
          : null,
    );
  }
  for (final ModelerMode other in ModelerMode.values) {
    if (other == mode || !other.ready) continue;
    for (final AnimationSubmode submode in AnimationSubmode.values) {
      for (final ModelerTool tool in toolsFor(other, animation: submode)) {
        add(tool, other, because: '${other.label} mode');
      }
      if (other != ModelerMode.animation) break;
    }
  }
  return entries;
}

/// The tools that would refuse right now, by id — what makes an entry a
/// disabled entry with a reason rather than one that answers with a refusal
/// after somebody has chosen it.
///
/// **Coarse on purpose: "it acts on a selection and there is none".** That
/// is the refusal people actually meet, it is the one a palette can answer
/// before the fact without duplicating every command's own checks, and being
/// told "nothing is selected" by a greyed row is better than being told it
/// by the status line a moment later. Anything finer — a bevel that needs
/// edges rather than faces — stays the command's own answer, where it is
/// written once.
Set<String> unavailableTools({
  required ModelerMode mode,
  required ProjectSelection selection,
}) {
  if (!selection.isEmpty) return const <String>{};
  return <String>{
    for (final ModelerTool tool in toolsFor(mode))
      if (_needsSelection(tool.id)) tool.id,
  };
}

/// Whether [id] is one of the tools that acts on what is selected.
///
/// The ones that are not: adding a shape, which is where a selection comes
/// from, and the tools that make a selection rather than reading one —
/// Select, `ux-28`'s lasso, and the lathe's own dialog.
bool _needsSelection(String id) =>
    !id.endsWith('.select') &&
    !id.endsWith('.add') &&
    !id.endsWith('.lathe') &&
    !id.endsWith('.lasso');

/// `ux-27`'s own two folds, as palette entries — the ids are this file's
/// own rather than any rail's, since nothing on a rail folds a panel.
const String kFoldPanelCommand = 'view.foldPanel';
const String kFoldRailCommand = 'view.foldRail';

/// `rel-21d`'s own: the licence, the privacy policy and the four beside them.
///
/// **In the palette because that is where a person who does not know where it
/// lives will look.** It is also in Settings, which is where somebody who has
/// thought about it will look; two doors onto one screen, and no third
/// implementation of it.
const String kLegalCommand = 'help.legal';

/// Those two, with whatever keys [keymap] gives them.
List<PaletteEntry> foldEntries(
  Keymap keymap, {
  required ModelerMode mode,
  required AppLocalizations l10n,
}) {
  String? keysFor(ModelerAction action) {
    final List<ShortcutActivator> keys = keymap.forAction(action);
    return keys.isEmpty ? null : describeShortcut(keys.first);
  }

  return <PaletteEntry>[
    PaletteEntry(
      id: kFoldPanelCommand,
      label: l10n.foldPropertiesPanel,
      icon: Icons.view_sidebar_outlined,
      mode: mode,
      keys: keysFor(ModelerAction.foldPanel),
    ),
    PaletteEntry(
      id: kFoldRailCommand,
      label: l10n.foldToolRail,
      icon: Icons.view_week_outlined,
      mode: mode,
      keys: keysFor(ModelerAction.foldRail),
    ),
  ];
}

/// The entries that are about the application rather than about the model —
/// `rel-21d`'s own one, for now.
///
/// Separate from [foldEntries] rather than appended to it because the folds
/// are about the window and this is not, and a function called `foldEntries`
/// that also returns a legal screen is the kind of small lie that makes a
/// file hard to read a year later.
List<PaletteEntry> helpEntries({
  required ModelerMode mode,
  required AppLocalizations l10n,
}) => <PaletteEntry>[
  PaletteEntry(
    id: kLegalCommand,
    label: l10n.legalEntry,
    icon: Icons.gavel_outlined,
    mode: mode,
  ),
];

/// [said] matched against an entry's own words — the label first, then the
/// id, so "bev" finds Bevel and "mesh." finds everything in the mesh rail.
bool paletteMatches(PaletteEntry entry, String said) {
  final String want = said.trim().toLowerCase();
  if (want.isEmpty) return true;
  return entry.label.toLowerCase().contains(want) ||
      entry.id.toLowerCase().contains(want);
}

/// Opens the palette and answers with the id chosen, or null.
Future<String?> showCommandPalette(
  BuildContext context, {
  required List<PaletteEntry> entries,
}) => showDialog<String>(
  context: context,
  builder: (BuildContext context) => CommandPalette(entries: entries),
);

/// The dialog itself — a field and a list, and nothing else.
class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key, required this.entries});

  final List<PaletteEntry> entries;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  String _said = '';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<PaletteEntry> shown = <PaletteEntry>[
      for (final PaletteEntry entry in widget.entries)
        if (paletteMatches(entry, _said)) entry,
    ];
    return Dialog(
      child: SizedBox(
        width: 520,
        height: 440,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: AppLocalizations.of(context).runACommand,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (String it) => setState(() => _said = it),
                // Enter runs the first thing on the list, which is what a
                // palette is for: type three letters and go.
                onSubmitted: (_) {
                  final PaletteEntry? first = shown
                      .where((PaletteEntry it) => it.enabled)
                      .firstOrNull;
                  if (first != null) Navigator.of(context).pop(first.id);
                },
              ),
            ),
            if (shown.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    AppLocalizations.of(context).commandPaletteNoMatch(_said),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (BuildContext context, int at) {
                    final PaletteEntry entry = shown[at];
                    return ListTile(
                      dense: true,
                      enabled: entry.enabled,
                      leading: Icon(entry.icon, size: 18),
                      title: Text(entry.label),
                      // `ux-18`: what it does, under the name. The refusal
                      // wins the line where there is one — being told why a
                      // row is greyed matters more right now than being told
                      // what it would have done.
                      // One line each, clipped rather than wrapped: a palette
                      // is scanned, and a list that gives three lines to
                      // every row shows four things at a time.
                      subtitle: switch ((entry.disabledBecause, entry.about)) {
                        (final String why?, _) => Text(
                          why,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        (_, '') => null,
                        (_, final String about) => Text(
                          about,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      },
                      trailing: entry.keys == null
                          ? null
                          : Text(
                              entry.keys!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                      onTap: entry.enabled
                          ? () => Navigator.of(context).pop(entry.id)
                          : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
