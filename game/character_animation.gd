extends RefCounted
## Play the authored Blender clips on any of the village character variants.
var player: AnimationPlayer
var clips: Dictionary = {}
var attacking := false

func setup(model: Node) -> void:
	var players = model.find_children("*", "AnimationPlayer", true, false)
	assert(not players.is_empty(), "The Blender character must include its animation clips")
	player = players.front()
	for name in player.get_animation_list():
		var short_name = String(name).get_slice("/", String(name).get_slice_count("/") - 1).to_lower()
		if short_name in ["idle", "walk", "run", "attack"]:
			clips[short_name] = name
			player.get_animation(name).loop_mode = Animation.LOOP_NONE if short_name == "attack" else Animation.LOOP_LINEAR
	for required in ["idle", "walk", "run", "attack"]:
		assert(clips.has(required), "Missing authored animation: " + required)
	player.animation_finished.connect(_finished)
	player.play(clips.idle)

func _finished(name: StringName) -> void:
	if name == clips.attack: attacking = false

func attack() -> void:
	attacking = true
	player.speed_scale = 1.0
	player.play(clips.attack, 0.09, 1.0)
	player.seek(0, true)

func update(speed: float) -> void:
	if attacking: return
	var clip = "idle" if speed < 0.12 else "walk" if speed < 2.8 else "run"
	var rate = 1.0 if clip == "idle" else clampf(speed / (1.8 if clip == "walk" else 4.5), 0.6, 1.6)
	if player.current_animation != clips[clip]: player.play(clips[clip], 0.18)
	player.speed_scale = rate
