extends SceneTree
## Opens a glTF with physics the way Godot's importer does (OMI_physics_body and OMI_physics_shape) and checks it: a
## rigid body with a collision shape for what falls, a static body for what stays, and an animation that moves the
## falling thing (the run baked into keys). Prints "MAQUETTE GODOT PHYSICS: ..." and exits 1 on any failure.
## Usage: godot --headless --path Tools/godot --script check_physics.gd -- /absolute/path/to/file.glb


func fail(message: String) -> void:
	printerr("MAQUETTE GODOT PHYSICS: FAILED: " + message)
	quit(1)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		fail("no file given")
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(args[0], state)
	if error != OK:
		fail("could not read %s (error %d)" % [args[0], error])
		return
	var scene := document.generate_scene(state)
	if scene == null:
		fail("no scene")
		return
	root.add_child(scene)
	var rigid := scene.find_children("*", "RigidBody3D", true, false)
	var still := scene.find_children("*", "StaticBody3D", true, false)
	var shapes := scene.find_children("*", "CollisionShape3D", true, false)
	if rigid.is_empty():
		fail("no rigid body")
		return
	if still.is_empty():
		fail("no static body")
		return
	if shapes.size() < 2:
		fail("only %d collision shapes" % shapes.size())
		return
	var body: RigidBody3D = rigid[0]
	if body.mass < 600.0 or body.mass > 800.0:
		fail("the wood cube weighs %.1f kg, not about 700" % body.mass)
		return
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		fail("no animation")
		return
	print("MAQUETTE GODOT PHYSICS: %d rigid, %d static, %d shapes, %.0f kg, animated" % [rigid.size(), still.size(), shapes.size(), body.mass])
	quit(0)
