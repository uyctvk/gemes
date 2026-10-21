extends Node3D
## Blender-authored Elm village, with simple collision volumes independent of art.
const Catalog = preload("res://game/core/catalog.gd")
const CharacterAnimation = preload("res://game/character_animation.gd")
const FARMER = preload("res://game/assets/characters/farmer.glb")
const MERCHANT = preload("res://game/assets/characters/merchant.glb")
const HEALER = preload("res://game/assets/characters/healer.glb")
const GUARD = preload("res://game/assets/characters/guard.glb")
const COTTAGE = preload("res://game/assets/village/cottage.glb")
const WORKSHOP = preload("res://game/assets/village/workshop.glb")
const TOWNHOUSE = preload("res://game/assets/village/townhouse.glb")
const MARKET = preload("res://game/assets/village/market_stall.glb")
const WELL = preload("res://game/assets/village/well.glb")
const BARREL = preload("res://game/assets/village/barrel.glb")
const CART = preload("res://game/assets/village/handcart.glb")
const OAK = preload("res://game/assets/village/oak.glb")
const CRATE = preload("res://game/assets/village/crate.glb")
var targets: Array = []
var villagers: Array = []
var skeletons: Array = []
var character_animations: Array = []
var guardian_animation: RefCounted
var last_update_time := 0.0
var last_enemy_attack := 0.0
var guardian: Node3D
var guardian_skeleton: Skeleton3D
var gate: Node3D
var smoke: Array = []
var materials: Dictionary = {}
var rng := RandomNumberGenerator.new()
var font: Font

func build(ui_font: Font) -> void:
	font = ui_font
	rng.seed = 20261021
	_make_environment()
	_ground()
	_buildings()
	_forest()
	_detail_village()
	_points_of_interest()
	for i in range(30):
		var role = i % 10
		var appearance = "healer" if role == 1 else "merchant" if role in [2, 3] else "guard" if role == 4 else "farmer"
		var person = _person(appearance, 0.95 + (i % 6) * 0.02)
		add_child(person)
		villagers.append(person)
		skeletons.append(person.find_children("*", "Skeleton3D", true, false).front())
		var animation = CharacterAnimation.new()
		animation.setup(person)
		character_animations.append(animation)
	guardian = _person("guard", 1.12)
	add_child(guardian)
	guardian_skeleton = guardian.find_children("*", "Skeleton3D", true, false).front()
	guardian.position = Vector3(0, 0, -43)
	guardian_animation = CharacterAnimation.new()
	guardian_animation.setup(guardian)

func material(color: Color, emission: bool = false) -> StandardMaterial3D:
	var key = color.to_html() + str(emission)
	if materials.has(key): return materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	if emission:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.4
	materials[key] = mat
	return mat

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, collision: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node = _mesh(parent, mesh, pos, color)
	if collision:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cube := BoxShape3D.new()
		cube.size = size
		shape.shape = cube
		body.add_child(shape)
		node.add_child(body)
	return node

func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(color)
	node.position = pos
	parent.add_child(node)
	return node

func cylinder(parent: Node3D, pos: Vector3, radius: float, top: float, height: float, color: Color, sides: int = 8) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = sides
	return _mesh(parent, mesh, pos, color)

func _make_environment() -> void:
	var env := WorldEnvironment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("6592ad")
	sky_mat.sky_horizon_color = Color("bed0ce")
	sky_mat.ground_horizon_color = Color("8e9c7e")
	sky_mat.ground_bottom_color = Color("4b625a")
	sky.sky_material = sky_mat
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("91aaa3")
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("86938a")
	environment.fog_density = 0.002
	env.environment = environment
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -32, 0)
	sun.light_color = Color("f5d6aa")
	sun.light_energy = 0.72
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90
	add_child(sun)

func _asset(scene: PackedScene, pos: Vector3, angle: float = 0.0, scale_factor: float = 1.0, parent: Node3D = null) -> Node3D:
	var model := scene.instantiate() as Node3D
	model.position = pos
	model.rotation.y = angle
	model.scale = Vector3.ONE * scale_factor
	(parent if parent != null else self).add_child(model)
	return model

func _solid(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)

func _ground_material(kind: String, repeats: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://game/assets/village/" + kind + "_albedo.png")
	mat.normal_enabled = true
	mat.normal_texture = load("res://game/assets/village/" + kind + "_normal.png")
	mat.normal_scale = 0.65
	mat.roughness = 0.95
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE * repeats
	return mat

func _ground() -> void:
	var grass := box(self, Vector3(0, -0.55, -15), Vector3(180, 1, 180), Color.WHITE, true)
	grass.material_override = _ground_material("grass_ground", 0.7)
	var road_material := _ground_material("cobble_ground", 0.7)
	var road := box(self, Vector3(0, -0.085, -14), Vector3(5.8, 0.08, 90), Color.WHITE)
	road.material_override = road_material
	var crossing := box(self, Vector3(0, -0.08, -2), Vector3(28, 0.07, 4.5), Color.WHITE)
	crossing.material_override = road_material
	var plaza := cylinder(self, Vector3(0, -0.095, 2), 7.6, 7.6, 0.1, Color.WHITE, 48)
	plaza.material_override = road_material
	for z in range(-21, 29):
		for side in [-1, 1]:
			if z > -5 and z < 9: continue
			box(self, Vector3(side * 3.0, 0.06, z), Vector3(0.25, 0.16, 0.9), Color("646b5c"))
	_asset(WELL, Vector3(0, 0, 1))
	_solid(self, Vector3(0, 0.52, 1), Vector3(2.15, 1.04, 2.15))
	for x in [-1.24, 1.24]: _solid(self, Vector3(x, 1.5, 1), Vector3(.18, 3, .2))
	for i in range(18):
		var angle = i * TAU / 18.0
		var hill := SphereMesh.new()
		hill.radius = rng.randf_range(14, 23)
		hill.height = hill.radius * 1.3
		hill.radial_segments = 24
		hill.rings = 12
		_mesh(self, hill, Vector3(sin(angle)*75, -2, cos(angle)*65 - 20), Color("64755a"))
	for x in [-43, 43]: _solid(self, Vector3(x, 2, -10), Vector3(1, 5, 110))
	for z in [-62, 35]: _solid(self, Vector3(0, 2, z), Vector3(86, 5, 1))

func _building(scene: PackedScene, pos: Vector3, size: Vector3, angle: float = 0.0) -> void:
	var house := _asset(scene, pos, angle)
	_solid(house, Vector3(0, size.y/2, 0), size)
	# Roof camera collision follows the ridge, while door access stays outside the shell.
	_solid(house, Vector3(0, size.y + 0.55, 0), Vector3(size.x * 0.62, 1.1, size.z))

func _buildings() -> void:
	_building(WORKSHOP, Vector3(-12, 0, -12), Vector3(7, 3.6, 5.6))
	_building(TOWNHOUSE, Vector3(12, 0, -12), Vector3(5.5, 4.25, 4.7))
	_building(WORKSHOP, Vector3(-13, 0, 2), Vector3(7, 3.6, 5.6))
	_building(COTTAGE, Vector3(13, 0, 2), Vector3(5, 3.15, 4))
	for pos in [Vector3(-25, 0, 17), Vector3(-15, 0, 24), Vector3(25, 0, 20), Vector3(14, 0, 26)]:
		_building(COTTAGE, pos, Vector3(5, 3.15, 4))
	_building(TOWNHOUSE, Vector3(-29, 0, -10), Vector3(5.5, 4.25, 4.7), 0.18)
	_building(COTTAGE, Vector3(29, 0, -8), Vector3(5, 3.15, 4), -0.15)
	_asset(MARKET, Vector3(-8, 0, -7))
	for x in [-10.7, -5.3]:
		for z in [-8.15, -5.85]: _solid(self, Vector3(x, 1.55, z), Vector3(.14, 3.1, .14))
	for x in [-9.8, -8, -6.2]: _solid(self, Vector3(x, .52, -6.9), Vector3(1.7, 1.04, 1.2))
	# Workshop anvil and outdoor cargo make the service positions legible.
	box(self, Vector3(-8, 0.55, 5), Vector3(1.3, 1.1, 1), Color("434c49"), true)
	box(self, Vector3(-8, 1.2, 5), Vector3(1.9, 0.25, 0.65), Color("596368"))
	_asset(CART, Vector3(-18, 0, -4), 0.4)
	_solid(self, Vector3(-18, .75, -4), Vector3(1.7, 1.5, 1.9))
	_asset(CART, Vector3(18, 0, -4), -0.6)
	_solid(self, Vector3(18, .75, -4), Vector3(1.7, 1.5, 1.9))
	for pos in [Vector3(-16, 0, 5), Vector3(-17, 0, 4.5), Vector3(16, 0, 5), Vector3(10, 0, -8)]:
		_asset(BARREL, pos, rng.randf_range(0, TAU))
		_solid(self, pos + Vector3(0, .48, 0), Vector3(.67, .96, .67))
	# Palisade and northern road.
	for x in range(-17, 18):
		if absi(x) < 3: continue
		cylinder(self, Vector3(x, 1.55, -22), 0.45, 0.28, 3.1, Color("716044"), 6)
		box(self, Vector3(x, 1.2, -22), Vector3(0.9, 2.4, 0.8), Color("716044"), true)
	for x in [-3.4, 3.4]:
		box(self, Vector3(x, 2.1, -22), Vector3(0.7, 4.2, 1), Color("6a5942"), true)
	gate = Node3D.new()
	add_child(gate)
	box(gate, Vector3(0, 3.9, -22), Vector3(7.4, 0.6, 1), Color("796447"))
	# A compact ruin. The walls are static, indestructible collision bodies.
	for x in [-6, 6]:
		box(self, Vector3(x, 2.5, -46), Vector3(1.2, 5, 15), Color("6d7973"), true)
		for z in [-52, -48, -44, -40]: box(self, Vector3(x, 5.3, z), Vector3(1.4, 0.7, 1.5), Color("738078"))
	box(self, Vector3(0, 2.5, -53), Vector3(13, 5, 1.2), Color("6d7973"), true)
	for x in [-4, 4]: cylinder(self, Vector3(x, 2.7, -38), 1.0, 0.9, 5.4, Color("7b8279"), 8)
	box(self, Vector3(0, 0.5, -48), Vector3(1.8, 1, 1.1), Color("796443"), true)
	box(self, Vector3(0, 0.52, -48), Vector3(0.18, 1.1, 1.2), Color("c0a15e"))

func _detail_village() -> void:
	# Farms, fences, drying racks, lanterns and pushable cargo establish daily work.
	for side in [-1, 1]:
		for z in range(10, 26, 2):
			box(self, Vector3(side*21, .65, z), Vector3(.12, 1.3, .12), Color("634d36"), true)
			box(self, Vector3(side*21, .8, z+1), Vector3(.09, .12, 2), Color("745d40"))
		for row in range(3):
			var x = side * (17 + row * 1.3)
			box(self, Vector3(x, .07, 19), Vector3(.95, .12, 10), Color("574c39"))
			for z in range(15, 24):
				cylinder(self, Vector3(x, .36, z), .16, .04, .52, Color("647c4e"), 5)
	for pos in [Vector3(-6, 0, 0), Vector3(6, 0, 0), Vector3(-18, 0, 6), Vector3(18, 0, 6)]:
		box(self, pos + Vector3(0, 1.65, 0), Vector3(.13, 3.3, .13), Color("66533a"), true)
		box(self, pos + Vector3(.38, 2.9, 0), Vector3(.9, .11, .11), Color("66533a"))
		var lantern = box(self, pos + Vector3(.75, 2.44, 0), Vector3(.28, .47, .28), Color("d4a66d"))
		lantern.material_override = material(Color("a98254"), true)
	for i in range(30):
		var x = rng.randf_range(-28, 28)
		var z = rng.randf_range(-16, 29)
		if absf(x) < 3.6 or absf(z+2) < 3: continue
		cylinder(self, Vector3(x, .09, z), .15, .15, .16, Color("b49d80"), 7)
		for n in range(3):
			cylinder(self, Vector3(x + sin(n*TAU/3)*.08, .2, z+cos(n*TAU/3)*.08), .05, .02, .2,
				[Color("987b81"), Color("d2b783"), Color("9da9a1")][i%3], 5)
	for pos in [Vector3(-12, .47, -5), Vector3(-10.8, .47, -4.4), Vector3(11, .47, -5), Vector3(-9, .47, 7)]:
		var cargo := RigidBody3D.new()
		cargo.position = pos
		cargo.mass = 12
		cargo.linear_damp = 1.8
		cargo.angular_damp = 2.0
		var physical_material := PhysicsMaterial.new()
		physical_material.friction = 0.5
		physical_material.bounce = 0.03
		cargo.physics_material_override = physical_material
		add_child(cargo)
		_asset(CRATE, Vector3(0, -.36, 0), 0.0, 1.0, cargo)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(.65, .72, .65)
		collision.shape = shape
		cargo.add_child(collision)

func _tree(pos: Vector3, height: float) -> void:
	_asset(OAK, pos, rng.randf_range(0, TAU), height / 5.5)

func _forest() -> void:
	for i in range(90):
		var pos = Vector3(rng.randf_range(-50, 50), 0, rng.randf_range(-62, 35))
		if absf(pos.x) < 27 and pos.z > -26: continue
		if absf(pos.x) < 12 and pos.z < -25: continue
		_tree(pos, rng.randf_range(5.0, 9.5))
	for i in range(100):
		var pos = Vector3(rng.randf_range(-30, 30), 0.1, rng.randf_range(-28, 30))
		if absf(pos.x) < 4 or absf(pos.z + 2) < 3: continue
		cylinder(self, pos, 0.2, 0.05, rng.randf_range(0.2, 0.5), Color("839061"), 4)
	var stone := SphereMesh.new()
	stone.radius = 1.4
	stone.height = 2
	stone.radial_segments = 7
	stone.rings = 3
	for i in range(5): _mesh(self, stone, Catalog.RESOURCES.ore + Vector3(rng.randf_range(-2,2), 0.4, rng.randf_range(-2,2)), Color("85928e"))
	for i in range(4):
		var log_mesh = cylinder(self, Catalog.RESOURCES.wood + Vector3(i*0.5, 0.35, 0), 0.3, 0.3, 3, Color("93744d"))
		log_mesh.rotation.x = PI/2
	for i in range(9):
		var pos = Catalog.RESOURCES.herb + Vector3(rng.randf_range(-1.8,1.8), 0.25, rng.randf_range(-1.8,1.8))
		cylinder(self, pos, 0.3, 0.1, 0.5, Color("92a575"), 5)
		cylinder(self, pos + Vector3(0, 0.35, 0), 0.16, 0.13, 0.16, Color("ccbb8d"), 5)

func _sign(pos: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = font
	label.font_size = 48
	label.pixel_size = 0.009
	label.modulate = Color("fff1ce")
	label.outline_modulate = Color("273e36")
	label.outline_size = 10
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.position = pos
	add_child(label)

func _points_of_interest() -> void:
	var names = {"market": "市場", "vault": "貸金庫", "forge": "鍛冶場", "apothecary": "薬師の工房", "board": "村の依頼", "trainer": "訓練場", "wall": "北門", "chest": "遺品の回収箱"}
	for id in Catalog.STATIONS:
		var pos: Vector3 = Catalog.STATIONS[id]
		targets.append({"id": id, "name": names[id], "position": pos, "type": "station"})
		if id != "chest": _sign(pos + Vector3(0, 3.2 if id != "wall" else 5.2, 0), names[id])
	for kind in Catalog.RESOURCES:
		var pos: Vector3 = Catalog.RESOURCES[kind]
		targets.append({"id": kind, "name": Catalog.item_name(kind) + "を採集", "position": pos, "type": "resource"})
		_sign(pos + Vector3(0, 2.8, 0), Catalog.item_name(kind))
	box(self, Vector3(0, 1.6, -10), Vector3(2.3, 1.8, 0.22), Color("665941"), true)
	for x in [-0.85, 0.85]: box(self, Vector3(x, 0.6, -10), Vector3(0.14, 1.4, 0.18), Color("665941"))
	for x in [-0.55, 0.55]: box(self, Vector3(x, 1.6, -9.86), Vector3(0.65, 1.05, 0.02), Color("e0d3ac"))
	box(self, Vector3(-4, 1, 9), Vector3(0.25, 2, 0.25), Color("896c4c"), true)
	box(self, Vector3(-4, 1.5, 9), Vector3(1.4, 0.25, 0.25), Color("967c54"))

func _person(appearance: String, scale_factor: float = 1.0) -> Node3D:
	var person := Node3D.new()
	person.scale = Vector3.ONE * scale_factor
	var scene: PackedScene = {"farmer": FARMER, "merchant": MERCHANT, "healer": HEALER, "guard": GUARD}[appearance]
	person.add_child(scene.instantiate())
	var physical := AnimatableBody3D.new()
	physical.position.y = 0.88
	person.add_child(physical)
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.25
	shape.height = 1.72
	collider.shape = shape
	physical.add_child(collider)
	return person

func update(world: RefCounted, elapsed: float) -> void:
	var delta = maxf(elapsed - last_update_time, 0.001)
	last_update_time = elapsed
	for i in range(villagers.size()):
		var node: Node3D = villagers[i]
		var previous = node.position
		node.position = world.npc_position(i)
		node.position.y = -0.05 # Match the ground collider and the authored sole origin.
		var motion = node.position - previous
		if motion.length() > 0.001: node.rotation.y = atan2(-motion.x, -motion.z)
		character_animations[i].update(motion.length() / delta)
	guardian.visible = world.state.enemy.hp > 0
	var previous_guardian_position = guardian.position
	guardian.position = Catalog.vec(world.state.enemy.position)
	guardian.position.y = -0.05
	var toward = Catalog.vec(world.state.player.position) - guardian.position
	guardian.rotation.y = atan2(-toward.x, -toward.z)
	if world.state.enemy.next_attack > last_enemy_attack:
		last_enemy_attack = world.state.enemy.next_attack
		guardian_animation.attack()
	guardian_animation.update(guardian.position.distance_to(previous_guardian_position) / delta)
	gate.rotation.z = 0 if world.state.repaired else 0.12
	for i in range(smoke.size()): smoke[i].position.x = -14.6 + sin(elapsed * 0.45 + i) * 0.3

func nearest(pos: Vector3, forward: Vector3, world: RefCounted) -> Dictionary:
	var best: Dictionary = {}
	var score := 99.0
	var candidates = targets.duplicate()
	for i in range(world.state.npcs.size()):
		candidates.append({"id": str(i), "name": world.state.npcs[i].name + "と話す", "position": world.npc_position(i), "type": "npc"})
	for target in candidates:
		var delta: Vector3 = target.position - pos
		delta.y = 0
		var distance = delta.length()
		if distance > 4 or forward.dot(delta.normalized()) < 0.15: continue
		var value = distance + (1.0 - forward.dot(delta.normalized())) * 1.5
		if value < score: best = target; score = value
	return best
