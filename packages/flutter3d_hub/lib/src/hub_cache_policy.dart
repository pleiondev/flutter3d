/// How a hub model may be fetched and kept on the device.
///
/// **What makes a cache simple here.** A version on the hub is immutable, so
/// a cached copy of `<uuid>@<n>` is never stale: the cache is keyed by the
/// file's hash, a copy that hashes right is the file, and there is nothing
/// to revalidate. What a policy decides is only where a copy may come from
/// and whether one is kept.
///
/// **A value, not an enumeration.** Each field is one decision with a
/// default, so a later minor adds a field with a default of its own and a
/// policy written against this one keeps meaning the same. The constants
/// are the combinations an application usually wants. Plain data, so a
/// policy travels with an asset source to a decoding isolate.
final class HubCachePolicy {
  /// A policy; every field defaults to [standard]'s.
  const HubCachePolicy({
    this.readCache = true,
    this.useNetwork = true,
    this.writeCache = true,
    this.maxBytes = defaultMaxBytes,
  }) : assert(maxBytes == null || maxBytes > 0);

  /// The cache first, then the network, and what was fetched is kept. A file
  /// over [defaultMaxBytes] is refused.
  static const HubCachePolicy standard = HubCachePolicy();

  /// The cache only. A model that is not cached is refused with
  /// `HubRefusal.offline` rather than fetched: for a build that must not
  /// touch the network, and for a test.
  static const HubCachePolicy offline = HubCachePolicy(useNetwork: false);

  /// The network, with nothing kept and nothing read from the cache: for a
  /// tool that checks what the hub serves.
  static const HubCachePolicy noStore = HubCachePolicy(
    readCache: false,
    writeCache: false,
  );

  /// The default [maxBytes]: 256 MiB.
  static const int defaultMaxBytes = 256 * 1024 * 1024;

  /// Whether a cached copy whose hash matches is used instead of a fetch.
  final bool readCache;

  /// Whether the hub and its mirrors may be asked at all.
  final bool useNetwork;

  /// Whether a fetched file is kept for the next load.
  final bool writeCache;

  /// The largest file accepted, in bytes; a larger one is refused with
  /// `HubRefusal.tooLarge` before it is downloaded where the server says
  /// its size, and as soon as it passes the limit where it does not. Null
  /// for no limit.
  final int? maxBytes;

  /// This policy with the fields given changed.
  HubCachePolicy copyWith({
    bool? readCache,
    bool? useNetwork,
    bool? writeCache,
    int? maxBytes,
  }) => HubCachePolicy(
    readCache: readCache ?? this.readCache,
    useNetwork: useNetwork ?? this.useNetwork,
    writeCache: writeCache ?? this.writeCache,
    maxBytes: maxBytes ?? this.maxBytes,
  );

  /// This policy with no size limit.
  HubCachePolicy get unlimited => HubCachePolicy(
    readCache: readCache,
    useNetwork: useNetwork,
    writeCache: writeCache,
    maxBytes: null,
  );

  @override
  bool operator ==(Object other) =>
      other is HubCachePolicy &&
      other.readCache == readCache &&
      other.useNetwork == useNetwork &&
      other.writeCache == writeCache &&
      other.maxBytes == maxBytes;

  @override
  int get hashCode => Object.hash(readCache, useNetwork, writeCache, maxBytes);

  @override
  String toString() =>
      'HubCachePolicy(readCache: $readCache, useNetwork: $useNetwork, '
      'writeCache: $writeCache, maxBytes: $maxBytes)';
}
