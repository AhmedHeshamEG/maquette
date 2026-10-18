extends SceneTree
## Renders the Ink Look's exported Godot material (A1) the way a game would use it: a sphere and a cube on a floor,
## a sun with shadows, a camera. Saves the frame as a PNG for Tools/check_look_render.py to compare with the golden.
## Prints "MAQUETTE GODOT LOOK: ..." and exits 1 on any failure.
## Usage (it draws, so not --headless): godot --rendering-method gl_compatibility --resolution 1280x720 --path Tools/godot
##        --script render_look.gd -- res://look/maquette_ink.tres /absolute/path/to/render.png


func fail(message: String) -> void:
	printerr("MAQUETTE GODOT LOOK: FAILED: " + message)
	quit(1)


func painted(material: ShaderMaterial, colour: Color) -> ShaderMaterial:
	var copy: ShaderMaterial = material.duplicate(true)
	copy.set_shader_parameter("albedo", colour)
	if copy.next_pass is ShaderMaterial:
		copy.next_pass.set_shader_parameter("albedo", colour)
	return copy


func add_mesh(mesh: Mesh, material: Material, place: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = place
	root.add_child(instance)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		fail("give the material and where the picture goes")
		return
	var material = load(args[0])
	if not material is ShaderMaterial or material.shader == null:
		fail("the material didn't load: " + args[0])
		return
	if not material.next_pass is ShaderMaterial:
		fail("the outline pass is missing")
		return
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.78, 0.8, 0.85)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.62, 0.8)
	environment.ambient_light_energy = 0.4
	var world := WorldEnvironment.new()
	world.environment = environment
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -70, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var sphere := SphereMesh.new()
	sphere.radius = 0.6
	sphere.height = 1.2
	add_mesh(sphere, painted(material, Color(0.85, 0.45, 0.3)), Vector3(-0.8, 0.6, 0))
	var cube := BoxMesh.new()
	cube.size = Vector3(1, 1, 1)
	add_mesh(cube, painted(material, Color(0.3, 0.5, 0.85)), Vector3(0.9, 0.5, -0.2))
	var floor := PlaneMesh.new()
	floor.size = Vector2(8, 8)
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.62, 0.6, 0.57)
	add_mesh(floor, ground, Vector3.ZERO)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 2.2, 4.2)
	camera.rotation_degrees = Vector3(-24, 0, 0)
	camera.fov = 45
	root.add_child(camera)
	camera.make_current()
	for frame in 6:
		await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		fail("nothing was drawn")
		return
	if image.save_png(args[1]) != OK:
		fail("couldn't save " + args[1])
		return
	print("MAQUETTE GODOT LOOK: rendered %dx%d with the outline pass" % [image.get_width(), image.get_height()])
	quit(0)
