extends CharacterBody3D
const Catalog = preload("res://game/core/catalog.gd")
var camera: Camera3D
var weapon: Node3D
var world: RefCounted
var active := false
var sensitivity := 0.0022
var swing := 0.0

func setup(authority: RefCounted) -> void:
	world = authority
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.7
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 0.85
	add_child(collision)
	camera = Camera3D.new()
	camera.position.y = 1.58
	camera.fov = 78
	camera.near = 0.08
	add_child(camera)
	weapon = Node3D.new()
	camera.add_child(weapon)
	weapon.position = Vector3(0.45, -0.42, -0.7)
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
	camera.rotation.x = world.state.player.pitch
	velocity = Vector3.ZERO

func _input(event: InputEvent) -> void:
	if active and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * sensitivity)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * sensitivity, -1.35, 1.35)

func _physics_process(delta: float) -> void:
	if world == null: return
	if active and not world.state.player.dead:
		var input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var direction = (transform.basis * Vector3(input.x, 0, input.y)).normalized()
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
		position.x = clampf(position.x, -41.5, 41.5)
		position.z = clampf(position.z, -60.5, 33.5)
		world.state.player.position = Catalog.array_vec(position)
		world.state.player.yaw = rotation.y
		world.state.player.pitch = camera.rotation.x
		# Standard right stick support; Steam Input can map to these actions.
		var look = Input.get_vector("look_left", "look_right", "look_up", "look_down", 0.18)
		rotate_y(-look.x * delta * 2.2)
		camera.rotation.x = clampf(camera.rotation.x - look.y * delta * 1.8, -1.35, 1.35)
	weapon.visible = not world.items_at("inventory", "sword").is_empty()
	swing = maxf(0, swing - delta * 3)
	weapon.rotation = Vector3(-0.2 - sin(swing * PI) * 1.4, 0, -0.1 - sin(swing * PI) * 0.7)

func forward() -> Vector3:
	return -global_transform.basis.z
