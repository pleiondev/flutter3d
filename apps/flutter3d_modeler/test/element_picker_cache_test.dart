/// The picker cache over the mesh currently being edited: same version, same
/// picker; a moved version or an explicit [ElementPickerCache.forget] rebuilds
/// it.
///
///     flutter test test/element_picker_cache_test.dart
library;

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_modeler/src/element_picker_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same version answers with the same picker, not a rebuilt one', () {
    final cache = ElementPickerCache();
    final mesh = EditMesh.cuboid();

    final first = cache.pickerFor(mesh, 1);
    final second = cache.pickerFor(mesh, 1);

    // Mutation: rebuild on every call regardless of version. A picker held
    // by a drag across a hundred frames would then pay `MeshBvh`'s own build
    // cost every one of them, for a mesh that has not changed at all.
    expect(identical(first, second), isTrue);
  });

  test('a moved version rebuilds the picker', () {
    final cache = ElementPickerCache();
    final mesh = EditMesh.cuboid();

    final first = cache.pickerFor(mesh, 1);
    final second = cache.pickerFor(mesh, 2);

    // Mutation: keep answering with the stale picker once the version has
    // moved. A click after an edit would then be picked against geometry
    // that no longer exists.
    expect(identical(first, second), isFalse);
  });

  test('forget makes the next call rebuild even at the same version', () {
    final cache = ElementPickerCache();
    final mesh = EditMesh.cuboid();

    final first = cache.pickerFor(mesh, 1);
    cache.forget();
    final second = cache.pickerFor(mesh, 1);

    expect(identical(first, second), isFalse);
  });

  test('the rebuilt picker still picks the mesh it was built over', () {
    final cache = ElementPickerCache();
    final mesh = EditMesh.cuboid();

    final picker = cache.pickerFor(mesh, 1);

    expect(picker.mesh, same(mesh));
  });
}
