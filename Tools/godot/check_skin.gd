extends SceneTree
## Opens a rigged, animated glTF or FBX the way Godot's importer does and checks it plays: a skeleton with bones, a mesh skinned
## to it, an animation, and bones that move when the animation runs. Prints "MAQUETTE GODOT: ..." and exits 1 on any
## failure. Usage: godot --headless --path Tools/godot --script check_skin.gd -- /absolute/path/to/file.glb (or .fbx)


func fail(message: String) -> void:
	printerr("MAQUETTE GODOT: FAILED: " + message)
	quit(1)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		fail("no file given")
		return
	# FBX goes through Godot's own FBX reader (ufbx), glTF through its glTF reader.
	var document: GLTFDocument = FBXDocument.new() if args[0].ends_with(".fbx") else GLTFDocument.new()
	var state: GLTFState = FBXState.new() if args[0].ends_with(".fbx") else GLTFState.new()
	var error := document.append_from_file(args[0], state)
	if error != OK:
		fail("could not read %s (error %d)" % [args[0], error])
		return
	var scene := document.generate_scene(state)
	if scene == null:
		fail("no scene")
		return
	root.add_child(scene)
	var skeletons := scene.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		fail("no skeleton")
		return
	var skeleton: Skeleton3D = skeletons[0]
	if skeleton.get_bone_count() < 2:
		fail("only %d bones" % skeleton.get_bone_count())
		return
	# glTF gives mesh instances; the FBX reader gives importer mesh instances (the editor turns them into the same).
	var skinned := false
	for mesh in scene.find_children("*", "MeshInstance3D", true, false):
		if (mesh as MeshInstance3D).skin != null:
			skinned = true
	for mesh in scene.find_children("*", "ImporterMeshInstance3D", true, false):
		if (mesh as ImporterMeshInstance3D).skin != null:
			skinned = true
	if not skinned:
		fail("no mesh is skinned to the skeleton")
		return
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		fail("no animation")
		return
	var player: AnimationPlayer = players[0]
	var names := player.get_animation_list()
	if names.is_empty():
		fail("no animation in the player")
		return
	var animation := player.get_animation(names[0])
	if animation.length <= 0.0:
		fail("the animation has no length")
		return
	player.play(names[0])
	player.seek(0.0, true)
	var start := []
	for bone in skeleton.get_bone_count():
		start.append(skeleton.get_bone_pose_rotation(bone))
	player.seek(animation.length, true)
	var moved := 0
	for bone in skeleton.get_bone_count():
		if not skeleton.get_bone_pose_rotation(bone).is_equal_approx(start[bone]):
			moved += 1
	if moved == 0:
		fail("no bone moves when the animation plays")
		return
	print("MAQUETTE GODOT: %d bones, %d move over %.2f s of \"%s\"" % [skeleton.get_bone_count(), moved, animation.length, names[0]])
	quit(0)
