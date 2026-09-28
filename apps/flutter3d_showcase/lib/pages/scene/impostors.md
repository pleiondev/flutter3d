# Impostors

A tree forty metres away covers a few dozen pixels, and drawing all its triangles to
fill them is mostly wasted work. An impostor replaces the far tree with a single square
card. The card always turns to face the camera, and it shows a picture of the tree taken
from roughly the direction you are looking.

Those pictures are baked ahead of time: 8 by 8 views of the model from all around it,
packed into one texture called an octahedral atlas. The map puts straight up in the
middle of the atlas and straight down in its four corners, so the views a tree is
usually seen from (level, or from above) get the middle. A second atlas holds the
surface normal and depth for each texel, which is how the scene's lights can still
shade the card.

## Step 1: A tree with sides that differ

The tree is a trunk, two balls of leaves and one red fruit on the +X side. Because of
the fruit, the tree looks different from each side, and that lets you check that the
card picks the right view.

{{code tree}}

The parts are merged into one mesh, each painted with its own vertex colour. One mesh
matters here: a model node only switches through a level of detail chain when every
level is a single surface. The card is a square around the sphere that holds the whole
mesh, so the page measures that sphere as well.

{{code mesh}}

## Step 2: Bake the views

With a real model you do not write this step. When `flutter3d_build` converts a model
with `--impostor`, it adds an impostor as the last level of detail of every node that
draws something, except skinned and morphed ones, since a card holds one pose. It bakes the atlases on the software rasteriser, so every machine that converts the
model gets the same bytes, and the `.f3d` file stores them in a section of their own.
This page bakes a small atlas itself only so that it needs no asset.

Every view looks back along `impostorViewDirection` at the tree's sphere. The camera's
right hand is `impostorRight`, and the top row of a view is the side its up axis points
to. That is the layout the impostor shader reads, and if one sign here differed, the
view would come out mirrored. The tree is made of simple shapes, so instead of drawing
each view, the page casts one ray per texel and records what the ray hits. The albedo's
alpha is coverage. The normal is written in the tree's own space as `n * 0.5 + 0.5`,
and the depth goes in alpha, from 0 at the near side of the sphere to 1 at the far side.

{{code bake}}

At 32 texels per view, each atlas is 256 texels square. Both are uploaded as plain RGBA
textures.

{{code upload}}

## Step 3: End the chain in a card

A `ModelLod.impostor` is a level of detail whose content is a picture instead of
surfaces. It carries a `ModelImpostor`, which gives the grid size and the sphere the
views were taken around. It is always the coarsest level. `maxScreenFraction` is the
share of the screen's height below which the card takes over. Here it is a quarter, so
the switch happens within a short row of trees. The converter picks a smaller number:
half the coarsest mesh level's own threshold, and never more than a tenth.

A loader fills `ModelAsset.impostors` from the file. Here the page fills it directly:
one card mesh and the two atlases, uploaded once however many copies of the tree stand
in the scene.

{{code asset}}

## Step 4: Plant a row

Each instance becomes an `LodGroup` with two levels: the mesh, and an `ImpostorNode`
that draws the shared card. The renderer picks a level for each group every frame from
how much of the view the tree covers. The near trees stay meshes and the far ones
become cards. Zoom out or orbit and watch them switch.

{{code row}}

## Step 5: The same light on both

The card is drawn like any other mesh, with `LightingModel.impostor`, and it is lit by
the same lights. For each pixel the shader reads the three baked views nearest the
direction it is seen from and blends them. It reads the normal from the second atlas,
so a card darkens on the side away from the sun the way the mesh does. The light is
the same, but the shading is not quite: the mesh is lit with the full PBR model, while
the card stage is diffuse only, because the atlases carry no roughness or metal. At the
distance a tree turns into a card its highlights would be smaller than a pixel anyway.
Turn **Sun direction** and compare a near tree with a far one.

{{code sun}}

{{code light}}

Cards receive shadows but cast none. The shadow passes would draw the card as it was
built, an upright square, not as it is seen. So look at the ground beside each tree.
A near tree, drawn as a mesh, has its shadow there. A far tree, drawn as a card, has
none.

> **Note.** Each card is its own draw. A forest of cards is one draw per tree, not
> one instanced draw, because the instanced path uses the engine's own vertex stage,
> which does not know how to turn a card to the eye.

## Step 6: Tell them apart

Switch on **Tint the cards blue** to see which trees are cards. The base colour of the
impostor material tints the atlas the way it tints any texture.

{{code mark}}

The page checks that the row has five groups, that at least one of them is showing its
card and at least one its mesh, and that the frame drew something.

{{code check}}
