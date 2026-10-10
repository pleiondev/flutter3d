/// How much memory a set of caches may hold, by category — the account a
/// `ResourceCache` charges what it loads to.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show Registration;

import '../render/memory_report.dart' show MemoryCategory;

/// A category, or the whole budget, crossing its limit one way or the
/// other — what [MemoryBudget.onCrossed] hears.
final class MemoryBudgetCrossing {
  const MemoryBudgetCrossing({
    required this.category,
    required this.used,
    required this.limit,
    required this.isOver,
  });

  /// The category that crossed, or null for the budget's [MemoryBudget.total].
  final MemoryCategory? category;

  /// What it holds now, in bytes.
  final int used;

  /// Its limit, in bytes.
  final int limit;

  /// Whether it went over (true) or came back under (false).
  final bool isOver;

  @override
  String toString() =>
      'MemoryBudgetCrossing(${category?.name ?? 'total'} '
      '${isOver ? 'over' : 'under'}: $used of $limit B)';
}

/// How much memory may be held, per [MemoryCategory] and in all, and what
/// is held now.
///
/// **An account, as `MemoryReport` is**: a cache charges what it loads by
/// its own estimate of the value (`ResourceCache.sizeOf`) and refunds it
/// when the value leaves, so the budget holds the bytes the data needs, the
/// floor every backend sits on, and nothing a driver adds behind it.
///
/// **It says when a limit is crossed; a cache acts on it.** A
/// `ResourceCache` given this budget evicts what nobody holds, least wanted
/// first, until it is back under; what is held stays, and the budget stays
/// over until something is released. [onCrossed] hears each crossing once,
/// going over and coming back, so a game can lower its texture quality or
/// stop streaming the moment it matters rather than polling.
///
/// One budget may be shared by several caches: the models and the textures
/// of a level against one limit for the level.
final class MemoryBudget {
  MemoryBudget({Map<MemoryCategory, int> limits = const {}, this.total})
    : _limits = Map<MemoryCategory, int>.unmodifiable(limits);

  final Map<MemoryCategory, int> _limits;

  /// The most every category may hold together, in bytes, or null for no
  /// limit beyond the categories' own.
  final int? total;

  final Map<MemoryCategory, int> _used = <MemoryCategory, int>{};
  int _total = 0;
  final List<void Function(MemoryBudgetCrossing)> _listeners =
      <void Function(MemoryBudgetCrossing)>[];

  /// [category]'s limit in bytes, or null when it has none.
  int? limitOf(MemoryCategory category) => _limits[category];

  /// What [category] holds now, in bytes.
  int usedOf(MemoryCategory category) => _used[category] ?? 0;

  /// What every category holds together, in bytes.
  int get used => _total;

  /// Whether [category] is over its limit, or with no category, whether
  /// the [total] is.
  bool isOver([MemoryCategory? category]) {
    if (category == null) {
      final limit = total;
      return limit != null && _total > limit;
    }
    final limit = _limits[category];
    return limit != null && usedOf(category) > limit;
  }

  /// Whether [category] or the total is over, which is what a cache holding
  /// [category] has to bring down.
  bool isOverFor(MemoryCategory category) => isOver(category) || isOver();

  /// Calls [handler] each time a category or the total crosses its limit,
  /// either way, until the registration is canceled.
  Registration onCrossed(void Function(MemoryBudgetCrossing crossing) handler) {
    _listeners.add(handler);
    return Registration(() => _listeners.remove(handler));
  }

  /// Puts [bytes] on [category]'s account.
  void charge(MemoryCategory category, int bytes) => _move(category, bytes);

  /// Takes [bytes] off [category]'s account.
  void refund(MemoryCategory category, int bytes) => _move(category, -bytes);

  void _move(MemoryCategory category, int bytes) {
    if (bytes == 0) return;
    final wasOver = isOver(category);
    final wasTotalOver = isOver();
    _used[category] = usedOf(category) + bytes;
    _total += bytes;
    final crossings = <MemoryBudgetCrossing>[
      if (isOver(category) != wasOver)
        MemoryBudgetCrossing(
          category: category,
          used: usedOf(category),
          limit: _limits[category]!,
          isOver: !wasOver,
        ),
      if (isOver() != wasTotalOver)
        MemoryBudgetCrossing(
          category: null,
          used: _total,
          limit: total!,
          isOver: !wasTotalOver,
        ),
    ];
    for (final crossing in crossings) {
      for (final listener in List<void Function(MemoryBudgetCrossing)>.of(
        _listeners,
      )) {
        listener(crossing);
      }
    }
  }

  @override
  String toString() =>
      'MemoryBudget($_total B${total == null ? '' : ' of $total'})';
}
