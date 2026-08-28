/// A handle to something in the world, not the thing itself.
///
/// ## Why it carries a generation
///
/// An entity id that is only an index is a use-after-free waiting to happen:
/// despawn the monster you were holding, spawn a pickup, and the handle you
/// kept now points at the pickup. The bug does not throw — it reads a
/// perfectly valid component off an entity that is not the one you meant, and
/// the symptom appears three systems away.
///
/// So an index is reused and a generation is not. The pair is one integer, and
/// a stale handle answers `false` to [EcsWorld.alive] instead of quietly
/// working.
///
/// ## Why it is an extension type
///
/// It is an `int` at runtime with no allocation. A query walking ten thousand
/// entities a frame would otherwise allocate ten thousand objects to say ten
/// thousand numbers.
library;

extension type const Entity._(int packed) {
  /// Index below 16 million, generation above — which leaves room for 16
  /// million live entities and 500 million recycles of each before either
  /// wraps, and keeps the whole thing inside the 53 bits a web `int` really
  /// has.
  ///
  /// **Packed by arithmetic, not by shifting.** `generation << 24` reaches
  /// those 53 bits only on the VM: on the web an `int` is a double and a
  /// bitwise operation is done in 32 bits, so the generation overflows once it
  /// passes 255 and a handle starts aliasing an earlier one — which is the
  /// whole of what the generation is for. A product and a division are exact to
  /// 2^53 on both. The two forms agree bit for bit over the valid range, so
  /// nothing that stored a packed value has to be re-read.
  static const int _indexBits = 24;
  static const int _indexSpan = 1 << _indexBits;

  const Entity.of(int index, int generation)
    : packed = generation * _indexSpan + index % _indexSpan;

  /// The handle that refers to nothing. Distinct from every real entity.
  static const Entity none = Entity._(-1);

  int get index => packed % _indexSpan;
  int get generation => packed ~/ _indexSpan;

  bool get isNone => packed == -1;
}
