extends Node3D
## ゲーム全体の構築と進行（星系・小惑星・ゲートコース・入力設定）

const SKY_SHADER := preload("res://shaders/space_sky.gdshader")
const PLANET_SHADER := preload("res://shaders/planet.gdshader")
const ATMO_SHADER := preload("res://shaders/atmosphere.gdshader")
const RING_SHADER := preload("res://shaders/rings.gdshader")
const SUN_SHADER := preload("res://shaders/sun.gdshader")
const CORONA_SHADER := preload("res://shaders/corona.gdshader")

## 惑星データ（ここを編集すると星系を変えられます）
## type: 0=地球型 2=ガス 3=氷 4=溶岩 5=岩石
const PLANETS := [
	{"name": "ヴァルカン", "type": 4, "radius": 700.0, "orbit": 9000.0, "angle": 2.4, "orbit_speed": 0.0008, "spin": 0.02,
		"a": Color(0.1, 0.07, 0.06), "b": Color(0.28, 0.14, 0.1), "c": Color(1.0, 0.35, 0.05),
		"atmo": Color(1.0, 0.4, 0.1), "atmo_strength": 0.5, "seed": 3.0},
	{"name": "アクア", "type": 0, "radius": 1000.0, "orbit": 15000.0, "angle": -0.5, "orbit_speed": 0.0005, "spin": 0.012,
		"a": Color(0.03, 0.18, 0.5), "b": Color(0.75, 0.7, 0.5), "c": Color(0.2, 0.5, 0.25), "sea": 0.66,
		"atmo": Color(0.35, 0.65, 1.0), "atmo_strength": 1.1, "seed": 11.0},
	{"name": "テラノヴァ", "type": 0, "radius": 1300.0, "orbit": 22000.0, "angle": 0.35, "orbit_speed": 0.0003, "spin": 0.01,
		"a": Color(0.04, 0.17, 0.42), "b": Color(0.18, 0.38, 0.14), "c": Color(0.55, 0.45, 0.33), "sea": 0.5,
		"atmo": Color(0.4, 0.7, 1.0), "atmo_strength": 1.0, "seed": 27.0},
	{"name": "ジュピタス", "type": 2, "radius": 4200.0, "orbit": 46000.0, "angle": 0.9, "orbit_speed": 0.0001, "spin": 0.006,
		"a": Color(0.78, 0.62, 0.46), "b": Color(0.55, 0.33, 0.22), "c": Color(0.92, 0.88, 0.78),
		"atmo": Color(0.9, 0.75, 0.55), "atmo_strength": 0.7, "seed": 5.0, "rings": true},
	{"name": "グレイシア", "type": 3, "radius": 1100.0, "orbit": 64000.0, "angle": 0.15, "orbit_speed": 0.00008, "spin": 0.008,
		"a": Color(0.7, 0.82, 0.92), "b": Color(0.2, 0.45, 0.7), "c": Color(0.95, 0.97, 1.0),
		"atmo": Color(0.6, 0.85, 1.0), "atmo_strength": 0.6, "seed": 41.0},
]
const MOONS := [
	{"name": "ルナリス", "parent": "テラノヴァ", "type": 5, "radius": 320.0, "orbit": 4200.0, "angle": 2.0, "orbit_speed": 0.01, "spin": 0.01,
		"a": Color(0.35, 0.34, 0.33), "b": Color(0.6, 0.58, 0.55), "c": Color(0.85, 0.85, 0.85), "seed": 7.0},
]
const SUN_RADIUS := 3000.0
const BELT_INNER := 29000.0
const BELT_OUTER := 33000.0
const BELT_COUNT := 1600
const GATE_COUNT := 10
const GATE_RADIUS := 40.0

## 衝突・ターゲット対象の天体 {name, node, radius, orbit, angle, orbit_speed, spin, parent}
var bodies: Array = []
var target_index := 0

var asteroid_pos := PackedVector3Array()
var asteroid_rad := PackedFloat32Array()

var gates: Array[MeshInstance3D] = []
var gate_mats: Array[StandardMaterial3D] = []
var gate_index := 0
var gate_time := 0.0
var gate_best := 0.0
var gate_running := false
var gate_finished := false
var _prev_gate_side := 0.0

var ship: Node3D
var camera: Camera3D
var hud: Control
var start_xform := Transform3D.IDENTITY
var _time := 0.0


func _ready() -> void:
	_setup_input()
	_build_environment()
	_build_sun()
	_build_planets()
	_update_orbits(0.0)
	_compute_start()
	_build_asteroids()
	_build_gates()
	_build_ship_and_camera()
	_build_hud()
	target_index = _find_body("テラノヴァ")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_message("Starward プロトタイプ — W でスロットルを上げて発進", 5.0)


# ================= 入力設定 =================

func _setup_input() -> void:
	_action("throttle_up", [KEY_W], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action("throttle_down", [KEY_S], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_action("throttle_zero", [KEY_X])
	_action("roll_left", [KEY_A], [JOY_BUTTON_LEFT_SHOULDER])
	_action("roll_right", [KEY_D], [JOY_BUTTON_RIGHT_SHOULDER])
	_action("strafe_left", [KEY_Q], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_action("strafe_right", [KEY_E], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_action("strafe_up", [KEY_SPACE], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_action("strafe_down", [KEY_CTRL], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_action("pitch_up", [KEY_UP], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_action("pitch_down", [KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("yaw_left", [KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("yaw_right", [KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("boost", [KEY_SHIFT], [JOY_BUTTON_A])
	_action("warp", [KEY_TAB], [JOY_BUTTON_Y])
	_action("flight_assist", [KEY_Z], [JOY_BUTTON_X])
	_action("camera_mode", [KEY_C], [JOY_BUTTON_B])
	_action("target_next", [KEY_T], [JOY_BUTTON_BACK])
	_action("align", [KEY_Y], [JOY_BUTTON_LEFT_STICK])
	_action("recenter", [KEY_V], [JOY_BUTTON_RIGHT_STICK])
	_action("mouse_mode", [KEY_M])
	_action("invert_y", [KEY_I])
	_action("help", [KEY_H])
	_action("reset", [KEY_BACKSPACE], [JOY_BUTTON_START])
	_action("release_mouse", [KEY_ESCAPE])
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_MIDDLE
	InputMap.action_add_event("recenter", mb)


func _action(action_name: String, keys: Array, joy_buttons: Array = [], joy_axes: Array = []) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action_name, e)
	for b in joy_buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action_name, jb)
	for a in joy_axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[0]
		jm.axis_value = a[1]
		InputMap.action_add_event(action_name, jm)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("camera_mode"):
		hud.show_message(camera.cycle_mode(), 1.5)
	elif event.is_action_pressed("target_next"):
		target_index = (target_index + 1) % bodies.size()
		hud.show_message("ターゲット: " + bodies[target_index].name, 1.5)
	elif event.is_action_pressed("help"):
		hud.show_help = not hud.show_help
	elif event.is_action_pressed("reset"):
		ship.reset(start_xform)
		_reset_gates()
		hud.show_message("リスタート", 1.5)


# ================= 環境 =================

func _build_environment() -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.09, 0.1, 0.16)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(0, 0.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(4, 1.0)
	env.set_glow_level(5, 0.6)

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_sun() -> void:
	var sun := Node3D.new()
	sun.name = "Sun"
	add_child(sun)

	var mesh := SphereMesh.new()
	mesh.radius = SUN_RADIUS
	mesh.height = SUN_RADIUS * 2.0
	mesh.radial_segments = 96
	mesh.rings = 48
	var mat := ShaderMaterial.new()
	mat.shader = SUN_SHADER
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sun.add_child(mi)

	var corona := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * SUN_RADIUS * 6.0
	corona.mesh = quad
	var cm := ShaderMaterial.new()
	cm.shader = CORONA_SHADER
	corona.material_override = cm
	corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	corona.extra_cull_margin = SUN_RADIUS * 4.0
	sun.add_child(corona)

	var light := OmniLight3D.new()
	light.omni_range = 400000.0
	light.omni_attenuation = 0.0
	light.light_energy = 1.6
	light.light_color = Color(1.0, 0.96, 0.9)
	light.light_specular = 0.6
	sun.add_child(light)

	bodies.append({"name": "太陽 ソル", "node": sun, "radius": SUN_RADIUS, "orbit": 0.0, "angle": 0.0,
		"orbit_speed": 0.0, "spin": 0.0, "parent": ""})


func _make_planet(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = p.name
	add_child(root)

	var r: float = p.radius
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 128
	mesh.rings = 64
	var mat := ShaderMaterial.new()
	mat.shader = PLANET_SHADER
	mat.set_shader_parameter("planet_type", p.type)
	mat.set_shader_parameter("color_a", p.a)
	mat.set_shader_parameter("color_b", p.b)
	mat.set_shader_parameter("color_c", p.c)
	mat.set_shader_parameter("seed", p.get("seed", 0.0))
	mat.set_shader_parameter("sea_level", p.get("sea", 0.5))
	var body := MeshInstance3D.new()
	body.name = "Surface"
	body.mesh = mesh
	body.material_override = mat
	body.rotation_degrees.z = randf_range(-20.0, 20.0)
	root.add_child(body)

	if p.has("atmo"):
		var am := SphereMesh.new()
		am.radius = r * 1.07
		am.height = r * 2.14
		am.radial_segments = 96
		am.rings = 48
		var amat := ShaderMaterial.new()
		amat.shader = ATMO_SHADER
		amat.set_shader_parameter("atmo_color", p.atmo)
		amat.set_shader_parameter("strength", p.get("atmo_strength", 1.0))
		var atmo := MeshInstance3D.new()
		atmo.mesh = am
		atmo.material_override = amat
		atmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(atmo)

	if p.get("rings", false):
		var rm := PlaneMesh.new()
		rm.size = Vector2.ONE * r * 5.0
		var rmat := ShaderMaterial.new()
		rmat.shader = RING_SHADER
		rmat.set_shader_parameter("inner", 0.5)
		rmat.set_shader_parameter("outer", 0.98)
		var ring := MeshInstance3D.new()
		ring.mesh = rm
		ring.material_override = rmat
		ring.rotation_degrees = Vector3(12.0, 0.0, 8.0)
		root.add_child(ring)
	return root


func _build_planets() -> void:
	for p in PLANETS:
		var node := _make_planet(p)
		bodies.append({"name": p.name, "node": node, "radius": p.radius, "orbit": p.orbit, "angle": p.angle,
			"orbit_speed": p.orbit_speed, "spin": p.spin, "parent": ""})
	for m in MOONS:
		var node := _make_planet(m)
		bodies.append({"name": m.name, "node": node, "radius": m.radius, "orbit": m.orbit, "angle": m.angle,
			"orbit_speed": m.orbit_speed, "spin": m.spin, "parent": m.parent})


func _update_orbits(delta: float) -> void:
	for b in bodies:
		if b.orbit <= 0.0:
			continue
		b.angle += b.orbit_speed * delta
		var center := Vector3.ZERO
		if b.parent != "":
			center = bodies[_find_body(b.parent)].node.global_position
		b.node.global_position = center + Vector3(cos(b.angle), 0.0, sin(b.angle)) * b.orbit
		b.node.rotate_y(b.spin * delta)


func _find_body(n: String) -> int:
	for i in bodies.size():
		if bodies[i].name == n:
			return i
	return 0


func _compute_start() -> void:
	var terra: Vector3 = bodies[_find_body("テラノヴァ")].node.global_position
	var pos := terra + Vector3(0.0, 400.0, 6000.0)
	start_xform = Transform3D(Basis.IDENTITY, pos)


# ================= 小惑星 =================

func _make_rock_mesh() -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.seed = 1234
	noise.frequency = 1.2
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		var v := verts[i].normalized()
		var d := 1.0 + noise.get_noise_3dv(v * 1.5) * 0.45
		st.add_vertex(v * d)
	st.generate_normals()
	return st.commit()


func _build_asteroids() -> void:
	var rock := _make_rock_mesh()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.38, 0.35)
	mat.roughness = 0.95
	rock.surface_set_material(0, mat)

	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var xforms: Array[Transform3D] = []

	# 小惑星帯
	for i in BELT_COUNT:
		var a := rng.randf() * TAU
		var rr := rng.randf_range(BELT_INNER, BELT_OUTER)
		var pos := Vector3(cos(a) * rr, rng.randfn(0.0, 350.0), sin(a) * rr)
		var s := rng.randf_range(15.0, 140.0) if rng.randf() > 0.05 else rng.randf_range(200.0, 400.0)
		xforms.append(_rock_xform(rng, pos, s))

	# スタート地点付近の練習用岩塊
	var cluster := start_xform.origin + Vector3(2600.0, 0.0, -2200.0)
	for i in 220:
		var pos := cluster + Vector3(rng.randfn(0, 1), rng.randfn(0, 0.5), rng.randfn(0, 1)) * 700.0
		xforms.append(_rock_xform(rng, pos, rng.randf_range(6.0, 60.0)))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rock
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _rock_xform(rng: RandomNumberGenerator, pos: Vector3, s: float) -> Transform3D:
	var scl := Vector3(rng.randf_range(0.7, 1.3), rng.randf_range(0.6, 1.1), rng.randf_range(0.7, 1.4)) * s
	var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)) * Basis.from_scale(scl)
	asteroid_pos.append(pos)
	asteroid_rad.append((scl.x + scl.y + scl.z) / 3.0 * 0.95)
	return Transform3D(b, pos)


func collide_asteroids(p: Vector3, r: float) -> Array:
	var hits := []
	for i in asteroid_pos.size():
		var rr := asteroid_rad[i] + r
		if p.distance_squared_to(asteroid_pos[i]) < rr * rr:
			hits.append([asteroid_pos[i], asteroid_rad[i]])
	return hits


# ================= ゲートコース =================

func _build_gates() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var pos := start_xform.origin + Vector3(0, 0, -350)
	var dir := Vector3(0.25, 0.15, -1.0).normalized()
	for i in GATE_COUNT:
		var torus := TorusMesh.new()
		torus.inner_radius = GATE_RADIUS - 3.0
		torus.outer_radius = GATE_RADIUS + 3.0
		torus.rings = 48
		torus.ring_segments = 12
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.2, 0.2)
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 2.5
		var g := MeshInstance3D.new()
		g.mesh = torus
		g.material_override = mat
		add_child(g)
		g.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), pos)
		gates.append(g)
		gate_mats.append(mat)
		# 次のゲート位置
		dir = dir.rotated(Vector3.UP, rng.randf_range(-0.6, 0.6))
		dir = dir.rotated(dir.cross(Vector3.UP).normalized(), rng.randf_range(-0.35, 0.35)).normalized()
		pos += dir * rng.randf_range(380.0, 520.0)
	_reset_gates()


func _reset_gates() -> void:
	gate_index = 0
	gate_time = 0.0
	gate_running = false
	gate_finished = false
	_prev_gate_side = _gate_side(0)
	_refresh_gate_colors()


func _refresh_gate_colors() -> void:
	for i in gates.size():
		var c := Color(0.25, 0.25, 0.3)
		if i < gate_index:
			c = Color(0.2, 1.0, 0.4)
		elif i == gate_index:
			c = Color(1.0, 0.55, 0.15)
		elif i == gate_index + 1:
			c = Color(0.5, 0.35, 0.15)
		gate_mats[i].emission = c
		gate_mats[i].emission_energy_multiplier = 3.0 if i == gate_index else 1.2


func _gate_side(i: int) -> float:
	if ship == null or i >= gates.size():
		return 0.0
	var g := gates[i]
	return (ship.global_position - g.global_position).dot(g.global_basis.y)


func _update_gates(delta: float) -> void:
	if gate_running:
		gate_time += delta
	if gate_finished or gate_index >= gates.size():
		return
	var g := gates[gate_index]
	var side := _gate_side(gate_index)
	if _prev_gate_side < 0.0 and side >= 0.0:
		var rel := ship.global_position - g.global_position
		var radial := rel - g.global_basis.y * rel.dot(g.global_basis.y)
		if radial.length() < GATE_RADIUS:
			if gate_index == 0:
				gate_running = true
				gate_time = 0.0
			gate_index += 1
			camera.add_shake(0.15)
			if gate_index >= gates.size():
				gate_running = false
				gate_finished = true
				if gate_best <= 0.0 or gate_time < gate_best:
					gate_best = gate_time
					hud.show_message("コース完走！ 新記録 %.2f 秒" % gate_time, 4.0)
				else:
					hud.show_message("コース完走！ %.2f 秒" % gate_time, 4.0)
			_refresh_gate_colors()
			side = _gate_side(gate_index)
	_prev_gate_side = side


func get_next_gate_position():
	if gate_finished or gate_index >= gates.size():
		return null
	return gates[gate_index].global_position


# ================= 機体・カメラ・HUD =================

func _build_ship_and_camera() -> void:
	ship = preload("res://scripts/ship.gd").new()
	ship.name = "Ship"
	ship.world = self
	add_child(ship)
	ship.reset(start_xform)

	camera = preload("res://scripts/chase_camera.gd").new()
	camera.ship = ship
	add_child(camera)
	camera.make_current()

	var dust: MultiMeshInstance3D = preload("res://scripts/space_dust.gd").new()
	dust.camera = camera
	dust.ship = ship
	add_child(dust)

	ship.collided.connect(_on_ship_collided)
	ship.message.connect(func(t: String) -> void: hud.show_message(t, 2.5))


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = preload("res://scripts/hud.gd").new()
	hud.ship = ship
	hud.camera = camera
	hud.world = self
	layer.add_child(hud)


func _on_ship_collided(strength: float) -> void:
	camera.add_shake(clampf(strength / 120.0, 0.1, 2.0))
	if strength > 60.0:
		hud.show_message("衝突！ (%d m/s)" % int(strength), 1.5)


# ================= 問い合わせ =================

func get_target():
	if bodies.is_empty():
		return null
	return bodies[target_index]


func get_target_position():
	var t = get_target()
	if t == null:
		return null
	return t.node.global_position


## 表面までの距離が最も近い天体
func get_nearest_body(p: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for b in bodies:
		var d: float = p.distance_to(b.node.global_position) - b.radius
		if d < best_d:
			best_d = d
			best = {"name": b.name, "node": b.node, "radius": b.radius, "surface": d}
	return best


func _process(delta: float) -> void:
	_time += delta
	_update_orbits(delta)
	_update_gates(delta)
