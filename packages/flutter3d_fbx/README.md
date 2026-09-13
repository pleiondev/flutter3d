# flutter3d_fbx

A `ModelDecoder` for Autodesk's FBX — the skeleton `fmt-29d`'s own row asks
for, not the reader.

**Recognises a file; does not read one, yet.** `FbxDecoder.handles` sniffs
the binary magic (`"Kaydara FBX Binary"`) and the ASCII header comment
(`"; FBX ..."`) the same way every other decoder in this repository
recognises its own format, and `FbxDecoder.decode` refuses every one it is
handed with a plain `FormatException` explaining why, rather than crashing
partway through a parse nobody has written. The real reader — binary and
ASCII 7.x, geometry, materials, a node hierarchy with pivots — is `fmt-24`;
skins and animation are `fmt-25`. Both land in this package once they exist.

**No Flutter and no renderer in it**, the same reason
[`flutter3d_formats`](../flutter3d_formats) has none: a modeller's document
layer, a service that checks an uploaded asset, and the tool an agent starts
with `dart run` all want to ask "is this an FBX file" with no window in
front of them.

```dart
import 'package:flutter3d_fbx/flutter3d_fbx.dart';

const decoder = FbxDecoder();
decoder.handles('character.fbx', bytes); // true — recognised
await decoder.decode(bytes, request, resolveUri); // throws FormatException
```

Hand a `const FbxDecoder()` to `ModelLoadRequest.decoders` (in
`flutter3d_formats`) to make `decodeModelBytes` try it, the same way an
application registers any other decoder of its own.
