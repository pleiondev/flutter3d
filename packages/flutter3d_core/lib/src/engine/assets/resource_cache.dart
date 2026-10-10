import 'dart:async';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show ResourceException;

import '../render/memory_report.dart' show MemoryCategory;
import 'memory_budget.dart';

/// How much a resource matters to whoever asked for it: which load starts
/// first when [ResourceCache.maxConcurrentLoads] holds loads back, and
/// which unheld entry goes last when a [MemoryBudget] is over.
///
/// **An open set of ranks**, with the constants a game usually needs and a
/// constructor for the steps between: a streaming scheduler that ranks by
/// distance makes its own. Higher matters more.
final class ResourcePriority implements Comparable<ResourcePriority> {
  const ResourcePriority(this.rank);

  /// Higher is wanted more.
  final int rank;

  /// Something that may be wanted later: a level beyond the next door.
  static const ResourcePriority background = ResourcePriority(-100);

  /// What a request is when it says nothing.
  static const ResourcePriority normal = ResourcePriority(0);

  /// Something on screen, or about to be.
  static const ResourcePriority visible = ResourcePriority(100);

  /// Something the frame cannot be drawn without.
  static const ResourcePriority blocking = ResourcePriority(1000);

  @override
  int compareTo(ResourcePriority other) => rank.compareTo(other.rank);

  @override
  bool operator ==(Object other) =>
      other is ResourcePriority && other.rank == rank;

  @override
  int get hashCode => rank.hashCode;

  @override
  String toString() => 'ResourcePriority($rank)';
}

/// A request for a cached resource that was called off before it was
/// handed over — what [ResourceRequest.handle] completes with after
/// [ResourceRequest.cancel].
final class ResourceLoadCanceledException extends ResourceException {
  const ResourceLoadCanceledException(this.key);

  /// The key that was asked for.
  final Object? key;

  @override
  String get message => 'the request for $key was canceled';

  @override
  String toString() => 'ResourceLoadCanceledException: $message';
}

/// A borrowed reference to a cached resource.
///
/// Holding a handle keeps the resource in the cache; [release] gives it back.
/// Handles rather than raw values because "who still needs this" is the only
/// question a cache cannot answer on its own.
final class ResourceHandle<V> {
  ResourceHandle._(this._entry, this.value, this._priority) {
    _entry.holders.add(this);
  }

  final _CacheEntry<V> _entry;

  /// The cached resource. Reading it after [release] is a bug.
  final V value;

  bool _released = false;

  bool get isReleased => _released;

  /// How much this holder wants the resource. The entry ranks as the most
  /// any holder wants it, and once nobody holds it, as the most anybody did
  /// last — the order a [MemoryBudget] that is over evicts unheld entries
  /// in. A streaming game lowers it as the player walks away.
  ResourcePriority get priority => _priority;
  ResourcePriority _priority;
  set priority(ResourcePriority value) {
    _priority = value;
    _entry.rerank();
  }

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
    _entry
      ..refCount -= 1
      ..holders.remove(this)
      ..rerank()
      ..lastUsed = _entry.cache._tick++;
  }
}

/// One ask for [key], as [ResourceCache.request] makes it: the [handle]
/// it will hand over, its [priority] while it waits, and [cancel].
final class ResourceRequest<K, V> {
  ResourceRequest._(this._cache, this.key, this._entry, this._priority);

  final ResourceCache<K, V> _cache;
  final _CacheEntry<V> _entry;

  /// What was asked for.
  final K key;

  final Completer<ResourceHandle<V>> _handed = Completer<ResourceHandle<V>>();

  /// The handle, once the load is done; an error if it failed, or a
  /// [ResourceLoadCanceledException] if [cancel] came first.
  Future<ResourceHandle<V>> get handle => _handed.future;

  /// How much this request wants the resource. While it waits for a slot
  /// ([ResourceCache.maxConcurrentLoads]), the queue starts the entry the
  /// most is wanted of first; raising it moves the load up.
  ResourcePriority get priority => _priority;
  ResourcePriority _priority;
  set priority(ResourcePriority value) {
    _priority = value;
    _entry.rerank();
  }

  /// Whether [cancel] called this request off before its handle was handed
  /// over.
  bool get isCanceled => _canceled;
  bool _canceled = false;

  /// Calls the request off, if its handle has not been handed over yet:
  /// [handle] completes with a [ResourceLoadCanceledException], and the reference
  /// it held is given back. A load nobody else is waiting for is taken off
  /// the queue before it starts; one already running finishes and is kept,
  /// held by nobody, for [ResourceCache.evictUnused] or the budget. Once
  /// the handle is handed over, this does nothing: release the handle.
  void cancel() {
    if (_canceled || _handed.isCompleted) return;
    _canceled = true;
    _entry
      ..refCount -= 1
      ..waiting.remove(this)
      ..rerank();
    _handed.completeError(ResourceLoadCanceledException(key));
    _cache._forgetIfAbandoned(key, _entry);
  }
}

final class _CacheEntry<V> {
  _CacheEntry(this.cache, this.category, this.order);

  final ResourceCache<Object?, V> cache;
  final MemoryCategory category;

  /// When the entry was made, which breaks a tie between two waiting loads
  /// of one priority in favour of the earlier.
  final int order;

  /// Completes with the value, or the error, when the load is done. Null
  /// until the load starts.
  Future<V>? pending;
  bool get started => pending != null;
  final Completer<V> done = Completer<V>();

  V? loaded;
  bool get hasValue => done.isCompleted && loaded != null;
  int refCount = 0;
  int bytes = 0;

  final List<ResourceRequest<Object?, V>> waiting =
      <ResourceRequest<Object?, V>>[];
  final List<ResourceHandle<V>> holders = <ResourceHandle<V>>[];

  /// The most any request or holder wants it; once none is left, the most
  /// anybody did last.
  ResourcePriority priority = ResourcePriority.normal;

  /// When it was last released, for the eviction's tie between two unheld
  /// entries of one priority: the one released longest ago goes first.
  int lastUsed = 0;

  void rerank() {
    if (waiting.isEmpty && holders.isEmpty) return;
    var most = const ResourcePriority(-0x7fffffff);
    for (final request in waiting) {
      if (request.priority.rank > most.rank) most = request.priority;
    }
    for (final holder in holders) {
      if (holder.priority.rank > most.rank) most = holder.priority;
    }
    priority = most;
  }
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
/// Resources with a zero reference count are *kept* until [evictUnused] is
/// called, or until a [budget] is over. For models that is the useful
/// policy: flipping back to a previously viewed model should be free, and
/// the cost of holding it is bounded by how many the caller chooses to keep —
/// or by the budget.
///
/// **What a streaming game adds**, each off unless asked for:
///
///  * **A budget.** Given a [budget] and [sizeOf], each value is charged to
///    its [categoryOf] when it arrives and refunded when it leaves; while the
///    budget is over for that category, the cache evicts what nobody holds,
///    the least wanted ([ResourcePriority]) and then the longest released
///    first. What is held is never evicted.
///  * **A queue.** With [maxConcurrentLoads], at most that many loads run at
///    once and the rest wait, the most wanted starting first; a request's or
///    a handle's priority can change while it waits or holds.
///  * **Cancellation.** [request] hands back a [ResourceRequest] whose
///    [ResourceRequest.cancel] calls it off; [acquire] is a request whose
///    handle is awaited.
final class ResourceCache<K, V> {
  ResourceCache({
    required this.load,
    this.dispose,
    this.budget,
    this.sizeOf,
    MemoryCategory Function(K key)? categoryOf,
    this.maxConcurrentLoads,
  }) : assert(
         maxConcurrentLoads == null || maxConcurrentLoads > 0,
         'a cache that may run no load at a time loads nothing',
       ),
       // A named parameter may not be private, and the field stays private
       // behind [categoryOf], which supplies the default.
       // ignore: prefer_initializing_formals
       _categoryOf = categoryOf;

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

  /// The account each loaded value is charged to, or null for none.
  final MemoryBudget? budget;

  /// What a loaded value holds, in bytes, for [budget]. Null charges
  /// nothing.
  final int Function(V value)? sizeOf;

  /// Which category a key's value is charged to; textures when not given,
  /// the category a cache of images is.
  MemoryCategory categoryOf(K key) =>
      _categoryOf?.call(key) ?? MemoryCategory.textures;
  final MemoryCategory Function(K key)? _categoryOf;

  /// How many loads may run at once, or null for as many as are asked.
  final int? maxConcurrentLoads;

  final Map<K, _CacheEntry<V>> _entries = <K, _CacheEntry<V>>{};
  final List<K> _queue = <K>[];
  int _running = 0;
  int _made = 0;
  int _tick = 0;

  /// Number of entries currently held, loaded, in flight or waiting.
  int get length => _entries.length;

  Iterable<K> get keys => _entries.keys;

  bool contains(K key) => _entries.containsKey(key);

  /// How many handles and waiting requests are outstanding for [key].
  int referenceCount(K key) => _entries[key]?.refCount ?? 0;

  /// True once the value for [key] has finished loading.
  ///
  /// Borrowing waits for the load, so nothing here has to ask first. It is for a
  /// caller that must not wait — a frame that will draw a placeholder rather
  /// than block, or a loading screen counting how much of a level has arrived.
  bool isLoaded(K key) => _entries[key]?.hasValue ?? false;

  /// Borrows [key], loading it if needed.
  ///
  /// The reference is counted before awaiting, so a resource cannot be evicted
  /// out from under a caller that is still waiting for it. The same as
  /// `request(key, priority: priority).handle`, for a caller that will not
  /// call it off.
  Future<ResourceHandle<V>> acquire(
    K key, {
    ResourcePriority priority = ResourcePriority.normal,
  }) => request(key, priority: priority).handle;

  /// Asks for [key] at [priority], loading it if needed, and hands back the
  /// request: its [ResourceRequest.handle] to await, and the means to change
  /// its priority or call it off while it waits.
  ResourceRequest<K, V> request(
    K key, {
    ResourcePriority priority = ResourcePriority.normal,
  }) {
    var entry = _entries[key];
    if (entry == null) {
      entry = _CacheEntry<V>(
        this as ResourceCache<Object?, V>,
        categoryOf(key),
        _made++,
      );
      _entries[key] = entry;
      _schedule(key, entry);
    }
    entry.refCount++;
    final request = ResourceRequest<K, V>._(this, key, entry, priority);
    entry.waiting.add(request as ResourceRequest<Object?, V>);
    entry.rerank();
    final waitingEntry = entry;
    waitingEntry.done.future.then(
      (V value) {
        waitingEntry.waiting.remove(request);
        if (request._canceled) return;
        request._handed.complete(
          ResourceHandle<V>._(waitingEntry, value, request._priority),
        );
      },
      onError: (Object error, StackTrace stack) {
        waitingEntry.waiting.remove(request);
        if (request._canceled) return;
        // Undo the reference and forget the entry so the next attempt
        // retries rather than replaying a cached failure.
        waitingEntry.refCount--;
        if (_entries[key] == waitingEntry) _entries.remove(key);
        request._handed.completeError(error, stack);
      },
    );
    // Started now if a slot is free: the queue is only ever as long as the
    // slots are short.
    _startWaiting();
    return request;
  }

  void _schedule(K key, _CacheEntry<V> entry) {
    _queue.add(key);
    entry.done.future.then((V value) {
      _finished();
      // Cleared away while it loaded. Handed to whoever still waits for it,
      // outside the cache, as a value [clear] dropped always was; given to
      // [dispose] when nobody does.
      if (_entries[key] != entry) {
        if (entry.refCount <= 0) dispose?.call(value);
        return;
      }
      entry.loaded = value;
      final size = sizeOf?.call(value) ?? 0;
      entry.bytes = size;
      budget?.charge(entry.category, size);
      _trimFor(entry.category);
    }, onError: (Object _, StackTrace _) => _finished());
  }

  void _finished() {
    _running--;
    _startWaiting();
  }

  /// Starts what waits, the most wanted first, while there are slots.
  void _startWaiting() {
    final slots = maxConcurrentLoads;
    while (_queue.isNotEmpty && (slots == null || _running < slots)) {
      var best = 0;
      for (var i = 1; i < _queue.length; i++) {
        final a = _entries[_queue[i]]!;
        final b = _entries[_queue[best]]!;
        final wanted = a.priority.compareTo(b.priority);
        if (wanted > 0 || (wanted == 0 && a.order < b.order)) best = i;
      }
      final key = _queue.removeAt(best);
      final entry = _entries[key]!;
      _running++;
      final Future<V> loading;
      try {
        loading = load(key);
      } catch (error, stack) {
        entry.done.completeError(error, stack);
        continue;
      }
      entry.pending = loading;
      loading.then(entry.done.complete, onError: entry.done.completeError);
    }
  }

  /// [entry] dropped, when the last request for it was called off before
  /// its load started.
  void _forgetIfAbandoned(Object? key, _CacheEntry<V> entry) {
    if (entry.refCount > 0 || entry.started) return;
    if (_entries[key] != entry) return;
    _entries.remove(key);
    _queue.remove(key);
  }

  /// Evicts what nobody holds from [category], least wanted and longest
  /// released first, while [budget] is over for it.
  void _trimFor(MemoryCategory category) {
    final account = budget;
    if (account == null || !account.isOverFor(category)) return;
    final candidates = <K>[
      for (final MapEntry(:key, value: entry) in _entries.entries)
        if (entry.refCount <= 0 &&
            entry.hasValue &&
            (account.isOver() || entry.category == category))
          key,
    ];
    candidates.sort((a, b) {
      final x = _entries[a]!;
      final y = _entries[b]!;
      final wanted = x.priority.compareTo(y.priority);
      return wanted != 0 ? wanted : x.lastUsed.compareTo(y.lastUsed);
    });
    for (final key in candidates) {
      if (!account.isOverFor(category)) break;
      _evict(key);
    }
  }

  /// Takes [key] out, giving its value to [dispose] and its bytes back to
  /// [budget].
  void _evict(K key) {
    final entry = _entries.remove(key);
    if (entry == null) return;
    _queue.remove(key);
    final value = entry.loaded;
    if (value == null) return;
    budget?.refund(entry.category, entry.bytes);
    dispose?.call(value);
  }

  /// Drops every entry nobody holds. Returns how many were removed.
  int evictUnused() {
    final doomed = <K>[
      for (final MapEntry(:key, value: entry) in _entries.entries)
        // Not one still loading: what nobody waits for any more is kept
        // when it arrives, and evicted then.
        if (entry.refCount <= 0 && entry.done.isCompleted) key,
    ];
    doomed.forEach(_evict);
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
    _entries.keys.toList().forEach(_evict);
    _queue.clear();
  }
}
