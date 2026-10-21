extends CharacterBody3D
const Catalog = preload("res://game/core/catalog.gd")
const FARMER = preload("res://game/assets/characters/farmer.glb")
var camera: Camera3D
var camera_rig: Node3D
var spring_arm: SpringArm3D
var visual: Node3D
var visual_skeleton: Skeleton3D
var base_rotations: Dictionary = {}
var weapon: Node3D
var world: RefCounted
var active := false
var sensitivity := 0.0022
var swing := 0.0
var step_clock := 0.0

func setup(authority: RefCounted) -> void:
	world = authority
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.7
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 0.85
	add_child(collision)
	visual = FARMER.instantiate()
	add_child(visual)
	visual_skeleton = visual.find_children("*", "Skeleton3D", true, false).front()
	for name in ["Thigh_L", "Thigh_R", "UpperArm_L", "UpperArm_R"]:
		var bone = visual_skeleton.find_bone(name)
		if bone >= 0: base_rotations[name] = visual_skeleton.get_bone_pose_rotation(bone)
	camera_rig = Node3D.new()
	get_parent().add_child(camera_rig)
	spring_arm = SpringArm3D.new()
	spring_arm.spring_length = 4.1
	spring_arm.margin = 0.22
	camera_rig.add_child(spring_arm)
	spring_arm.add_excluded_object(get_rid())
	camera = Camera3D.new()
	camera.fov = 72
	camera.near = 0.12
	spring_arm.add_child(camera)
	weapon = Node3D.new()
	add_child(weapon)
	weapon.position = Vector3(0.49, 1.16, -0.07)
	var blade := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.075, 0.7, 0.035)
	blade.mesh = mesh
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("b5c5bf")
	steel.metallic = 0.6
	steel.roughness = 0.4
	blade.material_override = steel
	weapon.add_child(blade)
	var cross := MeshInstance3D.new()
	var cross_mesh := BoxMesh.new()
	cross_mesh.size = Vector3(0.28, 0.06, 0.06)
	cross.mesh = cross_mesh
	cross.position.y = -0.22
	cross.material_override = steel
	weapon.add_child(cross)
	restore_pose()

func restore_pose() -> void:
	position = Catalog.vec(world.state.player.position)
	rotation.y = world.state.player.yaw
	camera_rig.global_position = position + Vector3(0, 1.43, 0)
	camera_rig.rotation.y = world.state.player.yaw
	spring_arm.rotation.x = clampf(world.state.player.pitch, -0.7, 0.55)
	velocity = Vector3.ZERO

func _input(event: InputEvent) -> void:
	if active and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_rig.rotate_y(-event.relative.x * sensitivity)
		spring_arm.rotation.x = clampf(spring_arm.rotation.x - event.relative.y * sensitivity, -0.7, 0.55)

func face_camera() -> void:
	rotation.y = camera_rig.rotation.y
	world.state.player.yaw = rotation.y

func _physics_process(delta: float) -> void:
	if world == null: return
	if active and not world.state.player.dead:
		var input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var direction = camera_rig.global_transform.basis * Vector3(input.x, 0, input.y)
		direction.y = 0
		direction = direction.normalized()
		var load_info = world.load_for()
		var speed = 4.5 * load_info.tier.speed
		if Input.is_action_pressed("sprint") and world.state.player.stamina > 5 and load_info.ratio <= 1.0 and input.length() > 0:
			speed *= 1.55
			world.state.player.stamina = maxf(0, world.state.player.stamina - delta * 15 * load_info.tier.stamina)
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		if not is_on_floor(): velocity.y -= 20 * delta
		else: velocity.y = -0.1
		move_and_slide()
		for slide in range(get_slide_collision_count()):
			var hit = get_slide_collision(slide)
			var pushed = hit.get_collider()
			if pushed is RigidBody3D and direction.dot(-hit.get_normal()) > 0.3:
				pushed.sleeping = false
				pushed.apply_central_impulse(direction * 2.5)
		if is_on_floor() and input.length() > 0.3:
			step_clock += delta
			if step_clock > (0.38 if speed > 6 else 0.57):
				step_clock = 0
				get_parent().sound("step")
		position.x = clampf(position.x, -41.5, 41.5)
		position.z = clampf(position.z, -60.5, 33.5)
		if input.length() > 0.05:
			rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(1, delta * 9))
		world.state.player.position = Catalog.array_vec(position)
		world.state.player.yaw = rotation.y
		world.state.player.pitch = spring_arm.rotation.x
		# Standard right stick support; Steam Input can map to these actions.
		var look = Input.get_vector("look_left", "look_right", "look_up", "look_down", 0.18)
		camera_rig.rotate_y(-look.x * delta * 2.2)
		spring_arm.rotation.x = clampf(spring_arm.rotation.x - look.y * delta * 1.8, -0.7, 0.55)
	camera_rig.global_position = position + Vector3(0, 1.43, 0)
	weapon.visible = not world.items_at("inventory", "sword").is_empty()
	swing = maxf(0, swing - delta * 3)
	weapon.rotation = Vector3(0.06 - sin(swing * PI) * 1.3, 0, -0.2 - sin(swing * PI) * 0.5)
	if visual_skeleton != null:
		var stride := sin(Time.get_ticks_msec() * 0.011) * (0.40 if active and Vector2(velocity.x, velocity.z).length() > 0.5 else 0.018)
		for name in ["Thigh_L", "UpperArm_R"]:
			var index := visual_skeleton.find_bone(name)
			if index >= 0: visual_skeleton.set_bone_pose_rotation(index, base_rotations[name] * Quaternion(Vector3.RIGHT, stride))
		for name in ["Thigh_R", "UpperArm_L"]:
			var index := visual_skeleton.find_bone(name)
			if index >= 0: visual_skeleton.set_bone_pose_rotation(index, base_rotations[name] * Quaternion(Vector3.RIGHT, -stride))

func forward() -> Vector3:
	return -camera_rig.global_transform.basis.z
