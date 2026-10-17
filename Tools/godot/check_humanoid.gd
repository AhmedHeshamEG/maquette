extends SceneTree
## Opens a made character's glTF (K1) and checks it is ready for Godot's humanoid retargeting: every bone of Godot's
## humanoid profile that a character needs is in its skeleton under the profile's name and hangs from the right bone,
## a BoneMap over the profile finds them all, its named clips play (Walk moves its bones) and its mouth carries the
## face states as blend shapes. Prints "MAQUETTE GODOT HUMANOID: ..." and exits 1 on any failure.
## Usage: godot --headless --path Tools/godot --script check_humanoid.gd -- /absolute/path/to/person.glb

const REQUIRED := ["Hips", "Spine", "Chest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm",
	"RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]


func fail(message: String) -> void:
	printerr("MAQUETTE GODOT HUMANOID: FAILED: " + message)
	quit(1)


func is_below(skeleton: Skeleton3D, bone: int, ancestor: int) -> bool:
	var current := skeleton.get_bone_parent(bone)
	while current >= 0:
		if current == ancestor:
			return true
		current = skeleton.get_bone_parent(current)
	return false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		fail("no file given")
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(args[0], state) != OK:
		fail("could not read " + args[0])
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
	var profile := SkeletonProfileHumanoid.new()
	var map := BoneMap.new()
	map.profile = profile
	var mapped := 0
	for i in profile.bone_size:
		var name := profile.get_bone_name(i)
		if skeleton.find_bone(name) >= 0:
			map.set_skeleton_bone_name(name, name)
			mapped += 1
	for name in REQUIRED:
		if map.get_skeleton_bone_name(name) == StringName():
			fail("the profile's %s isn't in the skeleton" % name)
			return
	# Each bone hangs (perhaps through others) from the bone the profile hangs it from.
	for i in profile.bone_size:
		var name := profile.get_bone_name(i)
		var parent := profile.get_bone_parent(i)
		var bone := skeleton.find_bone(name)
		var above := skeleton.find_bone(parent)
		if bone >= 0 and above >= 0 and not is_below(skeleton, bone, above):
			fail("%s should hang from %s" % [name, parent])
			return
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		fail("no clips")
		return
	var player: AnimationPlayer = players[0]
	if not player.has_animation("Walk"):
		fail("no Walk clip (clips: %s)" % [player.get_animation_list()])
		return
	var walk := player.get_animation("Walk")
	player.play("Walk")
	player.seek(0.0, true)
	var start := []
	for bone in skeleton.get_bone_count():
		start.append(skeleton.get_bone_pose_rotation(bone))
	player.seek(walk.length * 0.5, true)
	var moved := 0
	for bone in skeleton.get_bone_count():
		if not skeleton.get_bone_pose_rotation(bone).is_equal_approx(start[bone]):
			moved += 1
	if moved < 4:
		fail("Walk moves only %d bones" % moved)
		return
	var shapes := 0
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null and node.name.begins_with("Mouth"):
			shapes = mesh.get_blend_shape_count()
	if shapes < 13:
		fail("the mouth has %d blend shapes" % shapes)
		return
	print("MAQUETTE GODOT HUMANOID: %d of the profile's bones mapped (all %d needed), %d clips, Walk moves %d bones, the mouth has %d blend shapes" % [mapped, REQUIRED.size(), player.get_animation_list().size(), moved, shapes])
	quit(0)
