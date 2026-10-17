extends SceneTree
## Opens a sprite sheet (K1: the PNG and its JSON) the way a Godot game does and checks it plays in an AnimatedSprite2D:
## a SpriteFrames with an animation per direction, each frame a region of the sheet with something drawn in it.
## Prints "MAQUETTE GODOT SPRITES: ..." and exits 1 on any failure.
## Usage: godot --headless --path Tools/godot --script check_sprites.gd -- /absolute/path/to/dog.png /absolute/path/to/dog.json


func fail(message: String) -> void:
	printerr("MAQUETTE GODOT SPRITES: FAILED: " + message)
	quit(1)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		fail("give the PNG and the JSON")
		return
	var image := Image.load_from_file(args[0])
	if image == null or image.is_empty():
		fail("could not read " + args[0])
		return
	var texture := ImageTexture.create_from_image(image)
	var data = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	if typeof(data) != TYPE_DICTIONARY or not data.has("frames") or not data.has("meta"):
		fail("the JSON isn't a sprite sheet")
		return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var drawn := 0
	for tag in data["meta"]["frameTags"]:
		var name: String = tag["name"]
		frames.add_animation(name)
		frames.set_animation_loop(name, true)
		for index in range(int(tag["from"]), int(tag["to"]) + 1):
			var key := "%s_%d" % [name, index - int(tag["from"])]
			if not data["frames"].has(key):
				fail("no frame " + key)
				return
			var box: Dictionary = data["frames"][key]["frame"]
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(box["x"], box["y"], box["w"], box["h"])
			frames.add_frame(name, atlas, data["frames"][key]["duration"] / 1000.0)
			if not image.get_region(Rect2i(atlas.region)).is_invisible():
				drawn += 1
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	root.add_child(sprite)
	var names := frames.get_animation_names()
	if names.size() < 4:
		fail("only %d directions" % names.size())
		return
	sprite.play(names[0])
	if not sprite.is_playing() or frames.get_frame_count(names[0]) < 2:
		fail("the first animation doesn't play")
		return
	var total := 0
	for name in names:
		total += frames.get_frame_count(name)
	if drawn < total:
		fail("%d of %d frames are empty" % [total - drawn, total])
		return
	print("MAQUETTE GODOT SPRITES: %d animations (%s), %d frames, every frame drawn, playing \"%s\"" % [names.size(), ", ".join(names), total, names[0]])
	quit(0)
