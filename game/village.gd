extends Node3D
## A small, handcrafted procedural greybox. No downloaded art dependencies.
const Catalog = preload("res://game/core/catalog.gd")
var targets: Array = []
var villagers: Array = []
var guardian: Node3D
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
	_points_of_interest()
	for i in range(30):
		var color = [Color("60756b"), Color("b38759"), Color("786a80"), Color("6b8390"), Color("b6a17c")][i % 5]
		var person = _person(color)
		add_child(person)
		villagers.append(person)
	guardian = _person(Color("4a6057"), 1.4)
	add_child(guardian)
	guardian.position = Vector3(0, 0, -43)
	box(guardian, Vector3(0, 1.0, 0), Vector3(0.85, 0.7, 0.5), Color("657268"))

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
	sky_mat.sky_top_color = Color("719baf")
	sky_mat.sky_horizon_color = Color("dddac1")
	sky_mat.ground_horizon_color = Color("b8bea4")
	sky_mat.ground_bottom_color = Color("4b625a")
	sky.sky_material = sky_mat
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c1d1c8")
	environment.ambient_light_energy = 0.35
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("b6c6b4")
	environment.fog_density = 0.003
	env.environment = environment
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -32, 0)
	sun.light_color = Color("ffe0a5")
	sun.light_energy = 0.75
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90
	add_child(sun)

func _ground() -> void:
	box(self, Vector3(0, -0.55, -15), Vector3(180, 1, 180), Color("677456"), true)
	box(self, Vector3(0, -0.025, -14), Vector3(5.8, 0.08, 90), Color("ad9d7b"))
	box(self, Vector3(0, 0.01, -2), Vector3(28, 0.07, 4.5), Color("b2a17f"))
	cylinder(self, Vector3(0, 0.02, 2), 7.6, 7.6, 0.1, Color("b2a383"), 24)
	# A low stone well at the centre, with a passable plaza around it.
	cylinder(self, Vector3(0, 0.45, 1), 1.2, 1.2, 0.9, Color("81887d"), 10)
	cylinder(self, Vector3(0, 0.92, 1), 0.9, 0.9, 0.05, Color("34585c"), 10)
	for x in [-1.25, 1.25]: box(self, Vector3(x, 1.6, 1), Vector3(0.18, 3.0, 0.18), Color("574b3a"), true)
	box(self, Vector3(0, 3.05, 1), Vector3(2.8, 0.2, 0.3), Color("574b3a"))
	# Soft silhouettes enclose the playable area without external terrain assets.
	for i in range(18):
		var angle = i * TAU / 18.0
		var hill := SphereMesh.new()
		hill.radius = rng.randf_range(14, 23)
		hill.height = hill.radius * 1.3
		hill.radial_segments = 10
		hill.rings = 5
		_mesh(self, hill, Vector3(sin(angle)*75, -2, cos(angle)*65 - 20), Color("73816c"))
	for x in [-43, 43]: box(self, Vector3(x, 2, -10), Vector3(1, 5, 110), Color("6b7560"), true)
	for z in [-62, 35]: box(self, Vector3(0, 2, z), Vector3(86, 5, 1), Color("6b7560"), true)

func _building(pos: Vector3, size: Vector3, roof_color: Color) -> void:
	var house := Node3D.new()
	house.position = pos
	add_child(house)
	box(house, Vector3(0, size.y/2, 0), size, Color("d2c5a2"), true)
	box(house, Vector3(0, 0.25, 0), Vector3(size.x + 0.15, 0.5, size.z + 0.15), Color("87877a"))
	for x in [-size.x/2, 0, size.x/2]:
		box(house, Vector3(x, size.y/2, size.z/2 + 0.03), Vector3(0.15, size.y, 0.12), Color("574d3d"))
	for y in [1.0, size.y - 0.15]:
		box(house, Vector3(0, y, size.z/2 + 0.05), Vector3(size.x, 0.12, 0.14), Color("574d3d"))
	for side in [-1, 1]:
		var roof = box(house, Vector3(side * size.x/4, size.y + 0.8, 0), Vector3(size.x * 0.66, 0.18, size.z + 1), roof_color)
		roof.rotation.z = side * deg_to_rad(32)
	for x in [-size.x/3, size.x/3]:
		var window = box(house, Vector3(x, 1.9, size.z/2 + 0.09), Vector3(0.75, 0.9, 0.07), Color("edbd6e"))
		window.material_override = material(Color("e4ba77"), true)
		box(house, Vector3(x, 1.9, size.z/2 + 0.15), Vector3(0.07, 0.95, 0.07), Color("66543f"))
	box(house, Vector3(0, 0.95, size.z/2 + 0.08), Vector3(0.95, 1.9, 0.08), Color("65523e"))
	box(house, Vector3(-size.x/3, size.y + 1.0, -1), Vector3(0.7, 2, 0.7), Color("8b8a7b"))

func _buildings() -> void:
	_building(Vector3(-12, 0, -12), Vector3(7, 3.6, 6), Color("845c43"))
	_building(Vector3(12, 0, -12), Vector3(7, 4.4, 6), Color("607177"))
	_building(Vector3(-13, 0, 2), Vector3(5, 3.2, 5), Color("6a5847"))
	_building(Vector3(13, 0, 2), Vector3(5, 3.2, 5), Color("8c6c52"))
	for pos in [Vector3(-25, 0, 17), Vector3(-15, 0, 24), Vector3(25, 0, 20), Vector3(14, 0, 26)]:
		_building(pos, Vector3(5, 3, 4), Color("8c7857"))
	# Market awning and finite goods on display.
	for x in [-11, -5]: box(self, Vector3(x, 1.5, -7), Vector3(0.15, 3, 0.15), Color("64513b"), true)
	box(self, Vector3(-8, 3, -7), Vector3(6.3, 0.15, 3), Color("b5a168"))
	for x in [-10, -8, -6]:
		box(self, Vector3(x, 1, -7), Vector3(1.5, 1.1, 1.1), Color("8a704e"), true)
		cylinder(self, Vector3(x, 1.7, -7), 0.35, 0.3, 0.35, Color("a5a273"))
	box(self, Vector3(-8, 0.55, 5), Vector3(1.3, 1.1, 1), Color("626b6b"), true)
	box(self, Vector3(-8, 1.2, 5), Vector3(1.9, 0.25, 0.65), Color("596368"))
	for i in range(4):
		var particle = cylinder(self, Vector3(-14.6, 5.3 + i * 0.7, 1), 0.3 + i*0.2, 0.4 + i*0.2, 0.5, Color("bab8a6"))
		smoke.append(particle)
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

func _tree(pos: Vector3, height: float) -> void:
	cylinder(self, pos + Vector3(0, height*0.25, 0), 0.25, 0.18, height * 0.5, Color("66533e"), 6)
	for i in range(3):
		var color = [Color("3e5e48"), Color("4e6a4e"), Color("5c7656")][i]
		cylinder(self, pos + Vector3(0, height*(0.45+i*0.18), 0), height*(0.32-i*0.07), 0, height*0.55, color, 7)

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

func _person(color: Color, scale_factor: float = 1.0) -> Node3D:
	var person := Node3D.new()
	person.scale = Vector3.ONE * scale_factor
	cylinder(person, Vector3(0, 0.92, 0), 0.25, 0.3, 0.7, color)
	var head := SphereMesh.new()
	head.radius = 0.21
	head.height = 0.45
	head.radial_segments = 8
	head.rings = 4
	_mesh(person, head, Vector3(0, 1.5, 0), Color("c6a681"))
	cylinder(person, Vector3(0, 1.7, 0), 0.24, 0.16, 0.15, color.darkened(0.3))
	for x in [-0.13, 0.13]: box(person, Vector3(x, 0.33, 0), Vector3(0.18, 0.65, 0.22), Color("555647"))
	for x in [-0.36, 0.36]: box(person, Vector3(x, 1, 0), Vector3(0.16, 0.65, 0.18), color)
	return person

func update(world: RefCounted, elapsed: float) -> void:
	for i in range(villagers.size()):
		var node: Node3D = villagers[i]
		var previous = node.position
		node.position = world.npc_position(i)
		var motion = node.position - previous
		if motion.length() > 0.005: node.rotation.y = atan2(motion.x, motion.z)
		node.position.y = absf(sin(elapsed * 3.5 + i)) * 0.045 if world.state.npcs[i].action != "休息" else 0
	guardian.visible = world.state.enemy.hp > 0
	guardian.position = Catalog.vec(world.state.enemy.position)
	var toward = Catalog.vec(world.state.player.position) - guardian.position
	guardian.rotation.y = atan2(toward.x, toward.z)
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
