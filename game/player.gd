extends CharacterBody3D
const Catalog = preload("res://game/core/catalog.gd")
const FARMER = preload("res://game/assets/characters/farmer.glb")
const SWORD = preload("res://game/assets/equipment/sword.glb")
const CharacterAnimation = preload("res://game/character_animation.gd")
var camera: Camera3D
var camera_rig: Node3D
var spring_arm: SpringArm3D
var visual: Node3D
var visual_skeleton: Skeleton3D
var character_animation: RefCounted
var weapon: Node3D
var world: RefCounted
var active := false
var sensitivity := 0.0022
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
	character_animation = CharacterAnimation.new()
	character_animation.setup(visual)
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
	var grip := BoneAttachment3D.new()
	grip.bone_name = "Hand_R"
	visual_skeleton.add_child(grip)
	weapon = SWORD.instantiate()
	grip.add_child(weapon)
	weapon.position = Vector3(0, 0.04, 0)
	weapon.rotation_degrees = Vector3(-35, 0, 0)
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

func begin_attack() -> void:
	character_animation.attack()

func _physics_process(delta: float) -> void:
	if world == null: return
	if active and not world.state.player.dead:
		var input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var direction = camera_rig.global_transform.basis * Vector3(input.x, 0, input.y)
		direction.y = 0
		direction = direction.normalized() * input.length()
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
	character_animation.update(Vector2(get_real_velocity().x, get_real_velocity().z).length() if active else 0.0)

func forward() -> Vector3:
	return -camera_rig.global_transform.basis.z
