extends SceneTree
## Opens a game level from Maquette (G1, Dev's level) the way Godot imports a .glb from a project folder, and checks each
## piece named "…-col" became a static body with a collision shape (so the player can't walk through the level).
## Prints "MAQUETTE GODOT LEVEL: ..." and exits 1 on any failure.
## The .glb is imported by Godot's own scene importer first (the "-col" naming is the importer's), so copy it into the
## project and run `godot --headless --path Tools/godot --import` before this.
## Usage: godot --headless --path Tools/godot --script check_level.gd -- res://level/level.glb


func fail(message: String) -> void:
	printerr("MAQUETTE GODOT LEVEL: FAILED: " + message)
	quit(1)


func count(node: Node, kind: String) -> int:
	var found := 1 if node.is_class(kind) else 0
	for child in node.get_children():
		found += count(child, kind)
	return found


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		fail("no file given")
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		fail("could not import " + args[0])
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var meshes := count(scene, "MeshInstance3D")
	var bodies := count(scene, "StaticBody3D")
	var shapes := count(scene, "CollisionShape3D")
	if meshes == 0:
		fail("no pieces")
		return
	if bodies == 0 or shapes < bodies:
		fail("%d pieces but %d static bodies with %d shapes" % [meshes, bodies, shapes])
		return
	print("MAQUETTE GODOT LEVEL: %d pieces, %d static bodies with collision" % [meshes, bodies])
	quit(0)
