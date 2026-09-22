/// Sort keys for the draw list, stored the way the platform can store them.
///
/// The native form packs a key and its payload into one 63-bit integer and
/// radix-sorts the result: 0.99 ms for 50 000 draws against 11.4 ms for a
/// comparison sort with a closure comparator, which is two thirds of a 60 Hz
/// frame and the reason this engine needs no native code for sorting. The run
/// those come from — the day, the SDK and the machine — is written once, on
/// `sortPackedKeys` in `key_sort.dart`, rather than here too: two copies of it
/// drift apart, and a reader then has to guess which is the later one.
///
/// That packing cannot exist on the web. Dart compiles `int` to a JavaScript
/// number there, so integers are exact only to 2^53, and a 63-bit packed key
/// is not merely awkward to hold — it cannot be represented at all, whatever
/// container it is put in. `Int64List` is absent for the same reason.
///
/// So the split is conditional, and the boundary is *how a key is stored*
/// rather than *how it is sorted*. This is the case conditional imports exist
/// for: no fake wants to stand here, and the difference is a fact about the
/// platform rather than a choice anybody is making. Both implementations are
/// covered by one test file, which runs on the VM and under
/// `flutter test --platform chrome`.
///
/// The web form keeps the key and the payload apart instead of packed. A key
/// is at most [kSortKeyBits] wide and fits a double exactly, so ordering there
/// is identical to native rather than approximate — which matters more than it
/// sounds: the back-to-front mode decides the order transparent surfaces blend
/// in, and a coarser key would change the picture, not just the speed.
library;

export 'packed_keys_native.dart'
    if (dart.library.js_interop) 'packed_keys_web.dart';
