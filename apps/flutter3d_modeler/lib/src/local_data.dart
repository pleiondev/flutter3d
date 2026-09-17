/// Everything the Modeller keeps on this device, and the one call that
/// removes it — `rel-21d`.
///
/// **The privacy policy promises this exists, so it has to exist.** The
/// policy's own "how to erase what the Modeller keeps on your device" section
/// names Settings → "Clear local data" beside deleting the application's
/// container by hand, because a person who wants their work gone should not
/// have to find a support directory to do it — and a policy that names a
/// button nobody built is a policy that is not true.
///
/// **Three documents, named rather than swept.** [Storage] has no way to list
/// what is in it and does not need one: this application keeps exactly the
/// settings, the recent-files list and one autosave slot (see
/// `app_wiring.dart`'s own `_kAutosaveSessionId` for why there is exactly
/// one). Naming them means this cannot delete somebody else's document out of
/// a shared container, which a sweep of the directory could.
library;

import 'package:flutter3d_app/flutter3d_app.dart' show BinaryStorage, Storage;
import 'package:flutter3d_model_core/flutter3d_model_core.dart'
    show recoveryPathFor;

import 'recent_projects.dart';
import 'settings.dart';

/// What [clearLocalData] found and removed.
///
/// Counted rather than assumed, so the sentence a person is shown afterwards
/// is about what was actually there: "nothing to clear" and "cleared three
/// things" are different answers, and a dialog that says the second when the
/// first is true is a dialog nobody believes the next time.
typedef ClearedLocalData = ({bool settings, bool recentFiles, bool autosave});

extension ClearedLocalDataCount on ClearedLocalData {
  int get count =>
      (settings ? 1 : 0) + (recentFiles ? 1 : 0) + (autosave ? 1 : 0);

  /// What to tell the person, in their own terms rather than in file names.
  String get says {
    if (count == 0) return 'There was nothing stored on this device.';
    final removed = <String>[
      if (settings) 'settings',
      if (recentFiles) 'the recent-files list',
      if (autosave) 'the autosave',
    ];
    return 'Cleared ${_and(removed)}.';
  }
}

String _and(List<String> items) => switch (items.length) {
  1 => items.first,
  2 => '${items.first} and ${items.last}',
  _ => '${items.take(items.length - 1).join(', ')} and ${items.last}',
};

/// Removes the settings, the recent-files list and the autosave slot.
///
/// **Does not touch a project file.** A `.f3dproj` a person saved is theirs,
/// sitting where they put it, and an editor that deleted documents off the
/// disk because somebody asked it to forget its own settings would be a
/// different and much worse program. What this clears is what the application
/// wrote without being asked to.
Future<ClearedLocalData> clearLocalData({
  required Storage storage,
  required BinaryStorage documents,
  required String autosaveSessionId,
}) async {
  final bool hadSettings = storage.read(SettingsStore.name) != null;
  if (hadSettings) storage.remove(SettingsStore.name);

  final bool hadRecent = storage.read(RecentModels.name) != null;
  if (hadRecent) storage.remove(RecentModels.name);

  final String autosave = recoveryPathFor(null, sessionId: autosaveSessionId);
  final bool hadAutosave = await documents.read(autosave) != null;
  if (hadAutosave) await documents.remove(autosave);

  return (settings: hadSettings, recentFiles: hadRecent, autosave: hadAutosave);
}
