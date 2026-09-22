# A decoder of your own

This engine knows glTF, OBJ, STL and its own `.f3d`. A studio's internal
format, or anything invented after this page was written, comes in
through `ModelDecoder`, one interface an application implements itself.

## Step 1: A format this engine has never heard of

Three numbers and nothing else: a width, a height, a depth. No glTF
header, no OBJ directive, nothing any built-in reader would recognise.

{{code decoder}}

## Step 2: Hand it in with the request

`ModelLoadRequest.decoders` carries an application's own readers
alongside the file. They travel with the request rather than living in a
registry, because decoding runs on a background isolate and a registry
filled on the main one would be empty there.

{{code request}}

## Step 3: Decode it

An application's own decoders are tried first, by file name and by
magic, before this package's built-in glTF, OBJ, STL and `.f3d` readers
ever see the bytes — which is also how a project replaces a built-in
reader rather than only adding to the list.

{{code decode}}

## Step 4: Check the claim

The file named a box 1.4 units wide, so that is what the decoded
document's own bounds should say.

{{code check}}
