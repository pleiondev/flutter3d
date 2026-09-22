/// Which lesson an LTI launch opens.
///
/// One entry, the same honesty `cloud/lessons/lib/src/lessons_registry.dart`
/// states about itself: `ls-e-00`'s `prep-00`/`prep-01`/`prep-02` (real
/// content, more than one lesson) have not happened, so there is exactly one
/// document to launch into today — the camera tour `tpl-04`'s `viewer.json`
/// already proved, the same one `cloud/lessons` serves at `/l/engine-tour`.
///
/// Not shared with `cloud/lessons`'s own registry: that one carries a title
/// and description for an HTML landing page this service has no use for (a
/// launch redirects straight into the viewer, no page of its own to land
/// on), and the two services resolve their dependencies independently
/// outside the pub workspace, so there is nowhere in common to put a shared
/// file without joining one service's release to the other's.
library;

/// The path bundled into `flutter3d_lesson_viewer`'s web build, read by its
/// own `?level=` query parameter.
const _defaultLessonAsset = 'assets/levels/tour.json';

/// The level asset a launch opens when nothing more specific is asked for.
///
/// A real deployment with more than one lesson would read this from an LTI
/// custom parameter or the resource link's own id (`LtiLaunchClaims.
/// resourceLinkId`) instead of a constant — out of scope while there is
/// only the one lesson to pick from.
String defaultLessonAsset() => _defaultLessonAsset;
