extends Node3D
## 宇宙船の見た目（プリミティブメッシュで組み立て）とエンジン演出

const FLAME_SHADER := preload("res://shaders/engine_flame.gdshader")

const COLOR_NORMAL := Color(0.3, 0.8, 1.0)
const COLOR_BOOST := Color(1.0, 0.55, 0.2)
const COLOR_WARP := Color(0.6, 0.4, 1.0)

var flame_pivots: Array[Node3D] = []
var flame_mats: Array[ShaderMaterial] = []
var engine_light: OmniLight3D
var glow_mat: StandardMaterial3D
var nav_mats: Array[StandardMaterial3D] = []
var _t := 0.0
var _flame_len := 0.0
var _flame_color := COLOR_NORMAL


func _ready() -> void:
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.82, 0.85, 0.9)
	hull.metallic = 0.7
	hull.roughness = 0.35

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.13, 0.16)
	dark.metallic = 0.8
	dark.roughness = 0.45

	var accent := _emissive(Color(0.2, 0.9, 1.0), 3.0)

	var canopy := StandardMaterial3D.new()
	canopy.albedo_color = Color(0.03, 0.1, 0.18)
	canopy.metallic = 1.0
	canopy.roughness = 0.05
	canopy.emission_enabled = true
	canopy.emission = Color(0.1, 0.4, 0.6)
	canopy.emission_energy_multiplier = 0.4

	glow_mat = _emissive(COLOR_NORMAL, 4.0)

	# 胴体
	var body := CapsuleMesh.new()
	body.radius = 1.1
	body.height = 10.0
	_part(body, hull, Vector3(0, 0, 0.5), Vector3(90, 0, 0), Vector3(1.3, 1.0, 0.65))

	# 機首
	var nose := CylinderMesh.new()
	nose.top_radius = 0.0
	nose.bottom_radius = 1.0
	nose.height = 4.0
	_part(nose, hull, Vector3(0, 0, -6.4), Vector3(-90, 0, 0), Vector3(1.2, 1.0, 0.55))

	# キャノピー
	var cp := SphereMesh.new()
	cp.radius = 0.8
	cp.height = 1.6
	_part(cp, canopy, Vector3(0, 0.55, -3.0), Vector3.ZERO, Vector3(0.8, 0.55, 2.0))

	# 主翼（後退翼）
	for side in [-1.0, 1.0]:
		var wing_mesh := BoxMesh.new()
		wing_mesh.size = Vector3(5.5, 0.18, 2.6)
		var wing := _part(wing_mesh, hull, Vector3(3.4 * side, -0.1, 1.8), Vector3(0, -18.0 * side, -6.0 * side), Vector3.ONE)
		var strip_mesh := BoxMesh.new()
		strip_mesh.size = Vector3(5.0, 0.08, 0.14)
		_part(strip_mesh, accent, Vector3(0.2 * side, 0.06, -1.25), Vector3.ZERO, Vector3.ONE, wing)
		var under_mesh := BoxMesh.new()
		under_mesh.size = Vector3(4.0, 0.1, 1.6)
		_part(under_mesh, dark, Vector3(-0.4 * side, -0.1, 0.3), Vector3.ZERO, Vector3.ONE, wing)

		# 垂直尾翼
		var fin_mesh := BoxMesh.new()
		fin_mesh.size = Vector3(0.15, 1.9, 2.2)
		_part(fin_mesh, hull, Vector3(1.25 * side, 1.0, 4.0), Vector3(-20, 0, -18.0 * side), Vector3.ONE)

		# エンジンナセル
		var nac := CylinderMesh.new()
		nac.top_radius = 0.55
		nac.bottom_radius = 0.6
		nac.height = 4.2
		_part(nac, dark, Vector3(1.6 * side, 0.0, 4.2), Vector3(90, 0, 0), Vector3.ONE)
		var ring := CylinderMesh.new()
		ring.top_radius = 0.62
		ring.bottom_radius = 0.66
		ring.height = 0.3
		_part(ring, accent, Vector3(1.6 * side, 0.0, 3.0), Vector3(90, 0, 0), Vector3.ONE)
		var glow := CylinderMesh.new()
		glow.top_radius = 0.45
		glow.bottom_radius = 0.45
		glow.height = 0.05
		_part(glow, glow_mat, Vector3(1.6 * side, 0.0, 6.32), Vector3(90, 0, 0), Vector3.ONE)

		# 噴射炎
		var pivot := Node3D.new()
		pivot.position = Vector3(1.6 * side, 0.0, 6.35)
		pivot.rotation_degrees = Vector3(-90, 0, 0)
		add_child(pivot)
		var flame := CylinderMesh.new()
		flame.top_radius = 0.45
		flame.bottom_radius = 0.05
		flame.height = 1.0
		flame.cap_top = false
		flame.cap_bottom = false
		var fm := ShaderMaterial.new()
		fm.shader = FLAME_SHADER
		var fmi := MeshInstance3D.new()
		fmi.mesh = flame
		fmi.material_override = fm
		fmi.position = Vector3(0, -0.5, 0)
		fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(fmi)
		flame_pivots.append(pivot)
		flame_mats.append(fm)

		# 翼端灯
		var nav := _emissive(Color(1, 0.1, 0.1) if side < 0 else Color(0.1, 1, 0.2), 6.0)
		nav_mats.append(nav)
		var nl := SphereMesh.new()
		nl.radius = 0.15
		nl.height = 0.3
		_part(nl, nav, Vector3(6.0 * side, -0.1, 2.65), Vector3.ZERO, Vector3.ONE)

	engine_light = OmniLight3D.new()
	engine_light.position = Vector3(0, 0, 8)
	engine_light.omni_range = 18.0
	engine_light.light_color = COLOR_NORMAL
	add_child(engine_light)


func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _part(mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3, scl: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	if parent:
		parent.add_child(mi)
	else:
		add_child(mi)
	return mi


## throttle: -1..1 / boost, warp: 0..1
func update_engine(delta: float, throttle: float, boost: float, warp: float) -> void:
	_t += delta
	var target_len := 0.4 + maxf(throttle, 0.0) * 3.0 + boost * 4.0 + warp * 10.0
	_flame_len = lerpf(_flame_len, target_len, 1.0 - exp(-10.0 * delta))
	var target_col := COLOR_NORMAL.lerp(COLOR_BOOST, boost).lerp(COLOR_WARP, warp)
	_flame_color = _flame_color.lerp(target_col, 1.0 - exp(-6.0 * delta))

	for i in flame_pivots.size():
		var flicker := 1.0 + sin(_t * 47.0 + i * 2.0) * 0.06
		flame_pivots[i].scale = Vector3(1.0 + boost * 0.3, _flame_len * flicker, 1.0 + boost * 0.3)
		flame_mats[i].set_shader_parameter("color", _flame_color)
	glow_mat.emission = _flame_color
	glow_mat.albedo_color = _flame_color
	engine_light.light_color = _flame_color
	engine_light.light_energy = 0.5 + maxf(throttle, 0.0) * 2.0 + boost * 3.0 + warp * 4.0

	var blink := 1.0 if fmod(_t, 1.2) < 0.12 else 0.0
	for m in nav_mats:
		m.emission_energy_multiplier = 1.0 + blink * 10.0
