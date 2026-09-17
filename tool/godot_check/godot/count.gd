# What Godot read out of each GLB in the project, printed as one JSON line.
#
#     godot --headless --path <project> --script count.gd
#
# **Run after `--import`, and on the imported scene rather than on the file.**
# `GLTFDocument.append_from_file` would parse the same bytes without an import
# step, but that is not what a person dragging the file into Godot gets: the
# editor's import pipeline is what builds the meshes, the materials and the
# node names, and it is the half that can reject an image or drop a surface.
# So this loads `res://<name>.glb`, which is the imported scene, and walks it.
#
# The line is prefixed with `@@@` because Godot writes its own banner and,
# on a headless exit, a page of "leaked at exit" complaints from the dummy
# renderer to the same stream. The caller looks for the prefix rather than
# trying to guess which line is ours.
extends SceneTree


func _init() -> void:
	var out := {}
	var dir := DirAccess.open("res://")
	for name in dir.get_files():
		if not name.ends_with(".glb"):
			continue
		var packed = load("res://" + name)
		if packed == null:
			out[name] = {"error": "Godot could not load the imported scene"}
			continue
		out[name] = _read(packed.instantiate())
	print("@@@" + JSON.stringify(out))
	quit(0)


func _read(root: Node) -> Dictionary:
	var surfaces := []
	var materials := {}
	var nodes := 0
	for n in _walk(root):
		nodes += 1
		if not (n is MeshInstance3D):
			continue
		var mesh: Mesh = n.mesh
		if mesh == null:
			continue
		# The mesh's own bounds, in its own space — the node's transform is
		# not applied, so this is comparable with what a `MeshData` in our
		# document says about the same surface.
		var box: AABB = mesh.get_aabb()
		for s in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(s)
			var indices = arrays[Mesh.ARRAY_INDEX]
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			var count = indices.size() if indices != null else vertices.size()
			var material = mesh.surface_get_material(s)
			if material != null:
				materials[material.resource_name] = true
			surfaces.append({
				"node": String(n.name),
				"triangles": count / 3,
				"vertices": vertices.size(),
				"material": material.resource_name if material != null else "",
				"min": [box.position.x, box.position.y, box.position.z],
				"max": [box.end.x, box.end.y, box.end.z],
			})
	return {
		"nodes": nodes,
		"materials": materials.keys().size(),
		"surfaces": surfaces,
	}


func _walk(n: Node) -> Array:
	var all := [n]
	for c in n.get_children():
		all.append_array(_walk(c))
	return all
