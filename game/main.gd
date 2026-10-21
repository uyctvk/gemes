extends Node3D
const World = preload("res://game/core/world.gd")
const Catalog = preload("res://game/core/catalog.gd")
const Village = preload("res://game/village.gd")
const Player = preload("res://game/player.gd")
const Interface = preload("res://game/ui/interface.gd")
var world: RefCounted
var village: Node3D
var player: CharacterBody3D
var ui: CanvasLayer
var started := false
var elapsed := 0.0
var auto_save := 0.0
var target: Dictionary = {}
var request_sequence := 0
var session_id := ""
var last_event_index := 0
var text_scale := 1.0
var font: Font
var village_music: AudioStreamPlayer
var ruins_music: AudioStreamPlayer
var effects: AudioStreamPlayer
var music_volume := 0.55
var danger_mix := 0.0

func _ready() -> void:
	_setup_input()
	session_id = str(Time.get_unix_time_from_system()) + "-" + str(Time.get_ticks_usec())
	var data_dir = "user://"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save-dir="): data_dir = arg.trim_prefix("--save-dir=") + "/"
	world = World.new(data_dir + "world.json")
	DirAccess.make_dir_recursive_absolute(world.save_path.get_base_dir())
	world.new_world()
	font = load("res://game/assets/NotoSansJP.ttf")
	village = Village.new()
	add_child(village)
	village.build(font)
	player = Player.new()
	add_child(player)
	player.setup(world)
	ui = Interface.new()
	add_child(ui)
	ui.setup(self, font)
	_setup_audio()
	load_settings()
	set_text_scale(text_scale)
	get_tree().auto_accept_quit = false
	if "--smoke" in OS.get_cmdline_user_args(): _smoke_run.call_deferred()
	if "--capture" in OS.get_cmdline_user_args(): _capture.call_deferred()

func _setup_audio() -> void:
	village_music = AudioStreamPlayer.new()
	village_music.stream = load("res://game/assets/audio/village.ogg")
	(village_music.stream as AudioStreamOggVorbis).loop = true
	add_child(village_music)
	ruins_music = AudioStreamPlayer.new()
	ruins_music.stream = load("res://game/assets/audio/ruins.ogg")
	(ruins_music.stream as AudioStreamOggVorbis).loop = true
	add_child(ruins_music)
	effects = AudioStreamPlayer.new()
	add_child(effects)
	village_music.play()
	ruins_music.play()

func sound(name: String) -> void:
	if name not in ["ui", "swing", "gather", "step"]: return
	effects.stream = load("res://game/assets/audio/" + name + ".wav")
	effects.volume_db = -15 if name == "step" else -8
	effects.play()

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0, 1)
	save_settings()

func _setup_input() -> void:
	var keys = {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "sprint": KEY_SHIFT, "interact": KEY_E, "inventory": KEY_I, "journal": KEY_J, "heal": KEY_H, "pause": KEY_ESCAPE, "save": KEY_F5}
	for action in keys:
		InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = keys[action]
		InputMap.action_add_event(action, key)
	InputMap.add_action("attack")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", click)
	var buttons = {"interact": JOY_BUTTON_A, "pause": JOY_BUTTON_B, "inventory": JOY_BUTTON_Y, "heal": JOY_BUTTON_X, "sprint": JOY_BUTTON_LEFT_STICK}
	for action in buttons:
		var event := InputEventJoypadButton.new()
		event.button_index = buttons[action]
		InputMap.action_add_event(action, event)
	var axes = {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0], "move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0], "look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0], "look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0], "attack": [JOY_AXIS_TRIGGER_RIGHT, 1.0]}
	for action in axes:
		if not InputMap.has_action(action): InputMap.add_action(action, 0.18)
		var event := InputEventJoypadMotion.new()
		event.axis = axes[action][0]
		event.axis_value = axes[action][1]
		InputMap.action_add_event(action, event)

func new_game() -> void:
	if FileAccess.file_exists(world.save_path):
		var archive = world.save_path + ".previous-" + str(int(Time.get_unix_time_from_system()))
		if DirAccess.copy_absolute(world.save_path, archive) != OK:
			ui.label("既存セーブを保管できません。新規開始を取り消しました。")
			return
	world.new_world()
	if not world.save(): ui.label("セーブ先へ書き込めません。設定を確認してください。"); return
	_start_play()
	ui.toast("エルム村へようこそ。まず北の掲示板で仕事を探そう。")

func continue_game() -> void:
	var result = world.load_world()
	if not result.ok: ui.label(result.message); return
	_start_play()
	if result.backup: ui.toast("直前のバックアップから復旧しました。")

func _start_play() -> void:
	started = true
	last_event_index = world.state.events.size()
	player.restore_pose()
	ui.close()
	if world.state.player.dead: ui.show_death()

func set_control(enabled: bool) -> void:
	if player != null: player.active = enabled and started

func act(action: String, args: Dictionary = {}) -> Dictionary:
	request_sequence += 1
	var result = world.command(session_id + ":" + str(request_sequence), action, args)
	ui.toast(result.message)
	if result.ok:
		if action == "attack": sound("swing")
		elif action == "gather": sound("gather")
		else: sound("ui")
	return result

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if not started:
			ui.show_title()
		elif ui.page == "": ui.show_pause()
		else: ui.close()
		get_viewport().set_input_as_handled()
		return
	if not started or world.state.player.dead: return
	if event.is_action_pressed("save"):
		ui.toast("旅を保存した。" if world.save() else "保存に失敗しました。")
	if ui.page != "": return
	if event.is_action_pressed("inventory"): ui.show_inventory()
	elif event.is_action_pressed("journal"): ui.show_journal()
	elif event.is_action_pressed("heal"): act("heal")
	elif event.is_action_pressed("attack"):
		player.swing = 1.0
		player.face_camera()
		act("attack")
	elif event.is_action_pressed("interact") and not target.is_empty(): _interact()

func _interact() -> void:
	if target.type == "resource": act("gather", {"kind": target.id}); return
	if target.type == "npc":
		var index = int(target.id)
		var result = act("talk", {"npc": index})
		if result.ok: ui.show_npc(index, result.message)
		return
	match target.id:
		"market": ui.show_market()
		"vault": ui.show_vault()
		"forge", "apothecary": ui.show_craft(target.id)
		"board": ui.show_quests()
		"trainer": ui.show_trainer()
		"wall": ui.toast("北門は修復され、村に落ち着きが戻った。" if world.state.repaired else "北門が嵐で壊れている。掲示板で修復の依頼を受けよう。")
		"chest": act("loot")

func _process(delta: float) -> void:
	if world == null: return
	elapsed += delta
	if started:
		world.advance(minf(delta, 0.25))
		auto_save += delta
		if auto_save > 30:
			auto_save = 0
			if not world.save(): ui.toast("自動保存に失敗しました。")
		if world.state.player.dead and ui.page != "death":
			world.save()
			ui.show_death()
		for i in range(last_event_index, world.state.events.size()):
			if world.state.events[i].type in ["CRAFT_COMPLETED", "QUEST_EXPIRED", "WALL_REPAIRED"]: ui.toast(world.state.events[i].message)
		last_event_index = world.state.events.size()
	village.update(world, elapsed)
	var target_danger = 1.0 if started and player.position.z < -27 else 0.0
	danger_mix = move_toward(danger_mix, target_danger, delta * 0.35)
	village_music.volume_db = linear_to_db(maxf(0.001, music_volume * (1.0 - danger_mix)))
	ruins_music.volume_db = linear_to_db(maxf(0.001, music_volume * danger_mix))
	target = village.nearest(player.position, player.forward(), world) if started else {}
	ui.update(delta, target)

func return_to_title() -> void:
	if not world.save(): ui.toast("保存できなかったため、旅を続けます。"); return
	started = false
	set_control(false)
	ui.show_title()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if started and not world.save(): ui.toast("保存できませんでした。F5で再試行してください。"); return
		_stop_audio()
		get_tree().quit()

func _stop_audio() -> void:
	if village_music != null:
		village_music.stop()
		village_music.stream = null
	if ruins_music != null:
		ruins_music.stop()
		ruins_music.stream = null
	if effects != null:
		effects.stop()
		effects.stream = null

func _exit_tree() -> void:
	_stop_audio()

func set_text_scale(value: float) -> void:
	text_scale = value
	get_tree().root.content_scale_factor = value
	save_settings()

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "text_scale", text_scale)
	config.set_value("input", "sensitivity", player.sensitivity)
	config.set_value("display", "fov", player.camera.fov)
	config.set_value("audio", "music_volume", music_volume)
	config.save(world.save_path.get_base_dir() + "/settings.cfg")

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(world.save_path.get_base_dir() + "/settings.cfg") != OK: return
	text_scale = clampf(float(config.get_value("display", "text_scale", 1.0)), 0.9, 1.15)
	player.sensitivity = clampf(float(config.get_value("input", "sensitivity", 0.0022)), 0.0008, 0.005)
	player.camera.fov = clampf(float(config.get_value("display", "fov", 78)), 65, 100)
	music_volume = clampf(float(config.get_value("audio", "music_volume", 0.55)), 0, 1)

func _smoke_run() -> void:
	# Scene integration test uses an isolated --save-dir supplied by scripts/check.sh.
	new_game()
	await get_tree().process_frame
	var spawn = player.position
	Input.action_press("move_forward")
	await get_tree().create_timer(0.4).timeout
	Input.action_release("move_forward")
	assert(spawn.distance_to(player.position) > 0.5, "Input must move the physics character")
	assert(player.visual_skeleton != null and village.skeletons.size() == 30, "Rigged human models must be present")
	var turn_start = player.position
	player.camera_rig.rotation.y = PI / 2
	Input.action_press("move_forward")
	await get_tree().create_timer(0.35).timeout
	Input.action_release("move_forward")
	assert(absf(player.position.x - turn_start.x) > 0.5, "Movement must follow the third-person camera")
	player.camera_rig.rotation.y = 0
	var cargo: RigidBody3D = village.find_children("*", "RigidBody3D", true, false).front()
	cargo.global_position = Vector3(0, 0.55, 8)
	cargo.linear_velocity = Vector3.ZERO
	player.position = Vector3(0, 0.1, 10)
	await get_tree().create_timer(0.35).timeout
	var cargo_start = cargo.global_position.z
	Input.action_press("move_forward")
	await get_tree().create_timer(0.9).timeout
	Input.action_release("move_forward")
	assert(cargo.global_position.z < cargo_start - 0.1, "CharacterBody must push rigid cargo")
	print("PHYSICS_SMOKE: PASS")
	assert(ui.vitals.get_global_rect().position.y > 0, "Vitals must be on screen")
	assert(ui.objective.get_global_rect().position.x > 0, "Objective must be on screen")
	assert(ui.objective.get_global_rect().end.x <= get_viewport().get_visible_rect().size.x, "Objective must fit viewport")
	for page in ["market", "vault", "board", "forge", "apothecary", "trainer"]:
		ui.show_page(page)
		await get_tree().process_frame
	ui.show_inventory()
	await get_tree().process_frame
	ui.show_journal()
	await get_tree().process_frame
	ui.show_settings()
	await get_tree().process_frame
	set_text_scale(1.15)
	await get_tree().process_frame
	assert(ui.modal.get_global_rect().position.y >= 0, "Enlarged menu must fit viewport")
	set_text_scale(1.0)
	ui.close()
	await get_tree().create_timer(1).timeout
	var issues = world.audit()
	print("SCENE_SMOKE: ", "PASS" if issues.is_empty() else issues)
	_stop_audio()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(0 if issues.is_empty() else 1)

func _capture() -> void:
	await get_tree().create_timer(2).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/living-world-title.png")
	# Capture uses an ephemeral world and does not overwrite the player's save.
	started = true
	last_event_index = world.state.events.size()
	ui.close()
	player.position = Vector3(3, 0.1, 16)
	player.rotation.y = 0.1
	player.camera_rig.rotation.y = 0.1
	await get_tree().create_timer(2).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/living-world-village.png")
	ui.show_market()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/living-world-market.png")
	_stop_audio()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()
