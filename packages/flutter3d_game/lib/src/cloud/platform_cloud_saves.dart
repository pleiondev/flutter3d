import 'package:flutter/services.dart';

import 'cloud_save_store.dart';

/// A platform service a player is already signed in to.
///
/// **A class a game can make more of**, not an enum: a store this package does
/// not name — Steam Cloud, a console's own — is one more constant and a native
/// side that answers to its [name], with nothing here to change.
final class CloudProvider {
  const CloudProvider(this.name, this.title);

  /// What the platform side is told, in the channel's `provider` argument.
  final String name;

  /// As a player knows it.
  final String title;

  /// Google Play Games Services' saved games, on Android.
  static const CloudProvider playGames = CloudProvider(
    'playGames',
    'Play Games',
  );

  /// iCloud, on iOS and macOS.
  static const CloudProvider iCloud = CloudProvider('iCloud', 'iCloud');
}

/// Saves kept by Play Games or iCloud, through the platform's own side.
///
/// ## The channel
///
/// `flutter3d/cloud_saves`, two methods, each with `provider` (the
/// [CloudProvider]'s name) and `slot`:
///
/// | | |
/// |---|---|
/// | `fetch` | null for no copy, or `{document, version}` |
/// | `put` | also `document` and `replacing` (null to create); `{version}` when written, `{moved: true}` when another device wrote first |
///
/// The versions are the service's own: a Play Games snapshot's revision, an
/// iCloud record's change tag. The Dart side never reads them, it only hands
/// them back, so each platform keeps what its service already compares.
///
/// **A build without the platform side answers, it does not crash.** The
/// method channel throws `MissingPluginException` there, and a game that
/// offered iCloud on a build that cannot reach it should say so on the
/// settings screen rather than in a crash report.
final class PlatformCloudSaves implements CloudSaveStore {
  PlatformCloudSaves(this.provider, {MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('flutter3d/cloud_saves');

  final CloudProvider provider;
  final MethodChannel _channel;

  @override
  String get name => provider.title;

  @override
  Future<CloudFetch> fetch(String slot) async => switch (await _ask(
    'fetch',
    <String, Object?>{'slot': slot},
  )) {
    (_, final CloudUnavailable failed) => failed,
    (null, _) => const CloudEmpty(),
    ({'document': final String document, 'version': final String version}, _) =>
      CloudDocument(document, version: version),
    (final answer, _) => CloudUnavailable(
      '$name answered a fetch with $answer',
    ),
  };

  @override
  Future<CloudPut> put(
    String slot,
    String document, {
    String? replacing,
  }) async => switch (await _ask('put', <String, Object?>{
    'slot': slot,
    'document': document,
    'replacing': replacing,
  })) {
    (_, final CloudUnavailable failed) => failed,
    ({'moved': true}, _) => const CloudMoved(),
    ({'version': final String version}, _) => CloudStored(version: version),
    (final answer, _) => CloudUnavailable(
      '$name answered a write with $answer',
    ),
  };

  /// The platform's answer, or why there was none.
  Future<(Object?, CloudUnavailable?)> _ask(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final answer = await _channel.invokeMethod<Object?>(
        method,
        <String, Object?>{'provider': provider.name, ...arguments},
      );
      return (answer, null);
    } on MissingPluginException {
      return (null, CloudUnavailable('$name is not available in this build'));
    } on PlatformException catch (error) {
      return (
        null,
        CloudUnavailable('$name refused: ${error.message ?? error.code}'),
      );
    }
  }
}
