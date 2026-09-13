# flutter3d_core

The engine's rendering core with no Flutter SDK behind it (`mcp-03n`): scene
graph, render list, passes, materials, animation, and model/material loading
down to the one call each still needs an injected reader or decoder for.

`flutter3d` is the thin Flutter shell over this package that most
applications actually depend on — `BundleAssetSource`, `defaultImageDecoder`,
and the widgets. A modeller's document layer, the tool an agent starts with
`dart run`, and a service checking an uploaded asset depend on this package
directly instead, since none of them has a window in front of it.
