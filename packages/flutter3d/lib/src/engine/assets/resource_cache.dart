import 'dart:async';

/// A borrowed reference to a cached resource.
///
/// Holding a handle keeps the resource in the cache; [release] gives it back.
/// Handles rather than raw values because "who still needs this" is the only
/// question a cache cannot answer on its own.
final class ResourceHandle<V> {
  ResourceHandle._(this._entry, this.value);

  final _CacheEntry<V> _entry;

  /// The cached resource. Reading it after [release] is a bug.
  final V value;

  bool _released = false;

  bool get isReleased => _released;

  /// Returns the reference.
  ///
  /// Throws on a second call: releasing twice would drop someone else's reference
  /// and evict a resource still in use, which then fails somewhere unrelated. An
  /// exception at the mistake is much cheaper to debug.
  void release() {
    if (_released) {
      throw StateError('ResourceHandle released twice.');
    }
    _released = true;
    _entry.refCount--;
  }
}

final class _CacheEntry<V> {
  _CacheEntry(this.pending);

  Future<V> pending;
  V? loaded;
  int refCount = 0;
}

/// A reference-counted cache of asynchronously loaded resources.
///
/// Three behaviours it exists to provide, each of which is a bug when missing:
///
///  * **Deduplicated loads.** Two callers asking for the same key while it is
///    still loading await one load, not two. Without this, selecting a model
///    twice in quick succession decodes it twice and uploads it twice.
///  * **Reference counting.** The cache knows whether anyone still holds a
///    resource, which is what makes eviction safe.
///  * **Retry after failure.** A failed load is not remembered, so the next
///    request tries again instead of replaying the error forever.
///
/// Resources with a zero reference count are *kept* until [evictUnused] is called.
/// For models that is the useful policy: flipping back to a previously viewed
/// model should be free, and the cost of holding it is bounded by how many the
/// caller chooses to keep.
final class ResourceCache<K, V> {
  ResourceCache({required this.load, this.dispose});

  /// Produces the resource for a key.
  final Future<V> Function(K key) load;

  /// Called when an entry leaves the cache.
  ///
  /// **This used to say no backend has an explicit release, so leaving it null
  /// was the normal thing.** That was never true of `flutter3d_webgl` and is
  /// no longer true of any of them: every device implements
  /// `TextureAllocator.releaseTexture` — a no-op where the collector already
  /// frees, a `gl.deleteTexture` where nothing else will. A cache of GPU
  /// resources on the web that leaves this null still leaks, and the sentence
  /// that said otherwise is what made `ModelAsset` having no `dispose` look
  /// like a decision rather than a gap.
  final void Function(V value)? dispose;

  final Map<K, _CacheEntry<V>> _entries = <K, _CacheEntry<V>>{};

  /// Number of entries currently held, loaded or in flight.
  int get length => _entries.length;

  Iterable<K> get keys => _entries.keys;

  bool contains(K key) => _entries.containsKey(key);

  /// How many handles are outstanding for [key].
  int referenceCount(K key) => _entries[key]?.refCount ?? 0;

  /// True once the value for [key] has finished loading.
  ///
  /// Borrowing waits for the load, so nothing here has to ask first. It is for a
  /// caller that must not wait — a frame that will draw a placeholder rather
  /// than block, or a loading screen counting how much of a level has arrived.
  bool isLoaded(K key) => _entries[key]?.loaded != null;

  /// Borrows [key], loading it if needed.
  ///
  /// The reference is counted before awaiting, so a resource cannot be evicted
  /// out from under a caller that is still waiting for it.
  Future<ResourceHandle<V>> acquire(K key) async {
    var entry = _entries[key];
    if (entry == null) {
      entry = _CacheEntry<V>(load(key));
      _entries[key] = entry;
    }
    entry.refCount++;

    try {
      final value = await entry.pending;
      entry.loaded = value;
      return ResourceHandle<V>._(entry, value);
    } catch (_) {
      // Undo the reference and forget the entry so the next attempt retries
      // rather than replaying a cached failure.
      entry.refCount--;
      if (_entries[key] == entry) _entries.remove(key);
      rethrow;
    }
  }

  /// Drops every entry nobody holds. Returns how many were removed.
  int evictUnused() {
    final doomed = <K>[];
    _entries.forEach((key, entry) {
      if (entry.refCount <= 0) doomed.add(key);
    });

    for (final key in doomed) {
      final entry = _entries.remove(key);
      final value = entry?.loaded;
      if (value != null) dispose?.call(value);
    }
    return doomed.length;
  }

  /// Drops everything, held or not.
  ///
  /// **"Outstanding handles keep working" is true of the Dart object and false
  /// of anything [dispose] actually frees.** A handle held across this call
  /// comes back a live `ModelAsset` full of deleted GPU objects, with
  /// `isReleased` still answering false — which is the worst of both, because
  /// nothing about it looks wrong until a draw. The assert says so in the
  /// build where saying so is free; in release this stays the blunt instrument
  /// it has always been, because refusing to clear would be worse than
  /// clearing.
  void clear() {
    assert(() {
      final held = _entries.values.where((_CacheEntry<V> e) => e.refCount > 0);
      if (dispose != null && held.isNotEmpty) {
        throw StateError(
          'ResourceCache.clear() while ${held.length} entries are still held. '
          'The dispose callback frees them, so every outstanding handle is '
          'about to point at released resources while still reporting itself '
          'live. Release the handles first, or use evictUnused().',
        );
      }
      return true;
    }());
    for (final entry in _entries.values) {
      final value = entry.loaded;
      if (value != null) dispose?.call(value);
    }
    _entries.clear();
  }
}
