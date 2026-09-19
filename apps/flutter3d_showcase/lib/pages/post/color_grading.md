# Colour grade

Grading is what you do to a picture after it is lit: push the contrast, cool the shadows, warm the highlights, darken the corners. The renderer does it inside its last pass, so it costs almost nothing, and everything on this page is one `LookSettings` value. Every field has a neutral setting that changes nothing, so you only pay attention to the ones you use.

## Step 1: Move the whole picture

`contrast` is pivoted about mid grey, so raising it darkens the darks and lightens the lights without changing the overall exposure. `saturation` at 0 is a grey picture and at 2 is twice the colour. `temperature` runs from cool at -1 to warm at 1.

Drag each of the three and watch the red ball, the blue block and the floor.

{{code whole}}

## Step 2: Move one end of the picture

Contrast and saturation act on everything at once. A grade usually wants the opposite: a cool tone in the shadows and a warm one in the highlights. `lift` is added to each colour channel, so it moves the shadows and leaves white where it is. `gain` is multiplied in, so it moves the highlights and leaves black alone. Both are colours rather than single numbers, which is why they take a `Vector3`.

Drag Cool shadows and look at the dark side of the shapes. Drag Warm highlights and look at the lit floor.

{{code ranges}}

> **Note.** There is a third range, `gamma`, for the midtones between the two. It is an exponent, so it moves the middle and leaves both ends alone.

## Step 3: Add what a lens adds

`vignette` darkens the corners, `grain` adds a fixed speckle and `chromaticAberration` splits the colours slightly towards the edge. They are the marks of a camera rather than of a scene, so they go last, after the grade.

The Vignette slider is the easiest to see: at 1 the corners are nearly black. The grain does not move, so it will not shimmer when you turn the view.

{{code lens}}
