extends MultiMeshInstance3D
## カメラ周囲に漂う宇宙塵。速度に応じて伸びて速度感を出す

@export var count := 500
@export var extent := 260.0

var camera: Camera3D
var ship: Node3D
var _points := PackedVector3Array()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_priority = 110
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0

	var m := BoxMesh.new()
	m.size = Vector3(0.12, 0.12, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 0.85, 1.0, 0.7)
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = extent
	mat.distance_fade_max_distance = extent * 0.4
	m.material = mat

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = m
	multimesh.instance_count = count

	var origin := Vector3.ZERO
	if camera:
		origin = camera.global_position
	_points.resize(count)
	for i in count:
		_points[i] = origin + Vector3(randf_range(-extent, extent), randf_range(-extent, extent), randf_range(-extent, extent))


func _process(_delta: float) -> void:
	if camera == null or ship == null:
		return
	var c := camera.global_position
	var vel: Vector3 = ship.velocity
	var spd := vel.length()
	var dir := vel / spd if spd > 1.0 else -ship.global_basis.z
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var stretch := clampf(spd * 0.015, 0.3, 80.0)
	var b := Basis.looking_at(dir, up) * Basis.from_scale(Vector3(1, 1, stretch))
	for i in count:
		var rel := _points[i] - c
		rel.x = wrapf(rel.x, -extent, extent)
		rel.y = wrapf(rel.y, -extent, extent)
		rel.z = wrapf(rel.z, -extent, extent)
		_points[i] = c + rel
		multimesh.set_instance_transform(i, Transform3D(b, _points[i]))
