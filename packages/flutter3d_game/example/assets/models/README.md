# Empty on purpose

This application is the template without the models. A project scaffolded from
a template in `apps/flutter3d_editor/assets/templates` gets its models copied in
here. The seed itself ships none, and its own level test says so when it skips.

The directory still has to exist. `pubspec.yaml` declares `assets/models/`, and
Flutter refuses to analyse a package that names an asset directory which is not
there. The error is `unable to find directory entry in pubspec.yaml`, and
nothing at that point says the cause is an empty folder. Git tracks files, not
directories, so on a fresh checkout this file is the only reason the directory
exists.

Deleting it makes every clean clone fail.
