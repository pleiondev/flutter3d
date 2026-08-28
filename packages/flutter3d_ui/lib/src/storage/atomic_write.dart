/// Writing a document without the moment where it is half a document.
///
/// **One copy of this existed and the wrong file used it.** `FileStorage.write`
/// has gone through a temporary and a rename since it was written — settings
/// and saves, both of which a game can afford to lose — while the level editor
/// wrote a person's hand-built level with a bare `writeAsString`. That is the
/// document `Editing`'s own header calls "the part that can lose somebody's
/// work", and it had the least crash-safe write in the repository.
library;

import 'dart:io';

/// Writes [contents] to [path], through a temporary file and a rename.
///
/// The rename is the point. A crash, a power cut or a full disk halfway
/// through a direct write leaves a truncated document where the good one was —
/// so one lost session becomes every future one, because the next read finds
/// something that will not parse. Writing beside it and renaming means the
/// worst case is a leftover `.new` file next to a document that is still
/// whole.
///
/// `flush: true` because a rename that beats the bytes to the disk is the same
/// failure with an extra step.
///
/// Throws what the filesystem throws. A caller that would rather report than
/// fail — [FileStorage] is one — catches it; a caller that must tell somebody
/// their level did not save — the editor is one — lets it out.
Future<void> writeFileAtomically(String path, String contents) async {
  final temporary = File('$path.new');
  await temporary.writeAsString(contents, flush: true);
  await temporary.rename(path);
}

/// The same, without waiting. For a caller already on a synchronous path.
void writeFileAtomicallySync(String path, String contents) {
  final temporary = File('$path.new')..writeAsStringSync(contents, flush: true);
  temporary.renameSync(path);
}
