/// Who may do what to a model, in one place.
///
/// Every handler and every page asks these, rather than comparing ids itself.
/// A rule written out at each use is a rule that is eventually written wrong at
/// one of them, and that one is the leak.
library;

import 'model.dart';
import 'project.dart';
import 'user.dart';

/// Whether [viewer] may see [model] at all — its page, its preview, its file.
bool canView(ModelRecord model, User? viewer) =>
    model.isPublic || viewer?.id == model.ownerId;

/// Whether [viewer] may rename, publish, replace or delete [model].
bool canEdit(ModelRecord model, User? viewer) =>
    viewer != null && viewer.id == model.ownerId;

/// Whether [viewer] may rename, delete [project], or move models in or out
/// of it. A project has no visibility of its own to check — unlike
/// [canView], there is no public side to this: only its owner ever reaches
/// it at all.
bool canEditProject(ProjectRecord project, User? viewer) =>
    viewer != null && viewer.id == project.ownerId;

/// Whether [user] may upload.
///
/// An unconfirmed address may sign in but not store anything: the address is
/// how a forgotten password comes back, and an account that cannot get its
/// password back should not be holding files it will lose.
bool canUpload(User? user) => user != null && user.emailVerified;
