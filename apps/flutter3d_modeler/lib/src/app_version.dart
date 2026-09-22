/// Which build of the modeller this is — the one number a person reading the
/// About row or a maintainer reading a bug report can be told and act on.
///
/// **A constant beside `pubspec.yaml`, checked against it by a test.** The
/// version lives in the pubspec, and the only ways to read it at run time are
/// a plugin (`package_info_plus`, which is a dependency for the sake of one
/// string and brings a platform channel with it) or a generated file that
/// somebody has to remember to regenerate. A constant is neither, and its one
/// way to go wrong — being bumped in one place — is exactly what
/// `test/app_version_test.dart` fails on: it reads `pubspec.yaml` and compares.
///
/// **The whole string, build number included.** `0.7.0+1` and `0.7.0+2` are
/// different builds of one release, and a report against the first should not
/// be answered from the second.
library;

/// `pubspec.yaml`'s own `version:`.
const String kModelerVersion = '0.7.0+1';

/// [kModelerVersion] as a line for a bug report's environment field, in front
/// of the platform — so a report says which build it is about before it says
/// where it ran.
String reportEnvironmentFor(String platformSummary) =>
    'Modeler $kModelerVersion, Flutter, $platformSummary';
