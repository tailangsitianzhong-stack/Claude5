extends Camera3D
## 追従カメラ。位置は機体に固定し、向きだけを滑らかに追従させる（ワープ時も遅れない）

enum Mode { CHASE, FAR, COCKPIT }

const OFFSETS := [Vector3(0, 3.4, 15.0), Vector3(0, 8.0, 36.0), Vector3(0, 0.95, -3.3)]
const SMOOTH := [7.0, 4.5, 40.0]
const NAMES := ["追従カメラ", "遠景カメラ", "コックピット"]

@export var base_fov := 70.0

var ship: Node3D
var mode := Mode.CHASE
var shake := 0.0
var _q := Quaternion.IDENTITY
var _initialized := false


func _ready() -> void:
	near = 0.3
	far = 600000.0
	fov = base_fov
	process_priority = 100  # 機体の更新後に処理


func cycle_mode() -> String:
	mode = ((mode + 1) % 3) as Mode
	if ship.has_method("set_model_visible"):
		ship.set_model_visible(mode != Mode.COCKPIT)
	return NAMES[mode]


func add_shake(amount: float) -> void:
	shake = clampf(shake + amount, 0.0, 2.5)


func _process(delta: float) -> void:
	if ship == null:
		return
	var dt := minf(delta, 0.05)
	var target_q := ship.global_basis.get_rotation_quaternion()
	if not _initialized:
		_q = target_q
		_initialized = true
	_q = _q.slerp(target_q, 1.0 - exp(-SMOOTH[mode] * dt))
	var b := Basis(_q)

	var speed_ratio := 0.0
	var warp: float = ship.warp_amount
	var boost: float = ship.boost_amount
	if "velocity" in ship:
		speed_ratio = clampf(ship.velocity.length() / 750.0, 0.0, 1.0)

	var off: Vector3 = OFFSETS[mode]
	if mode != Mode.COCKPIT:
		off.z += speed_ratio * 3.0 + boost * 2.0
	var pos: Vector3 = ship.global_position + b * off

	var look_basis := b
	if mode != Mode.COCKPIT:
		var look_pt: Vector3 = ship.global_position + b * Vector3(0, 1.5, -40.0)
		look_basis = Basis.looking_at(look_pt - pos, b.y)

	# 揺れ
	var spool: float = 0.0
	if ship.warp_state == 1:
		spool = 0.15
	var s := shake + spool + warp * 0.05
	if s > 0.0:
		pos += look_basis * Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * s * 0.4
	shake = maxf(shake - dt * 2.5, 0.0)

	global_transform = Transform3D(look_basis, pos)
	var target_fov := base_fov + boost * 10.0 + warp * 30.0
	fov = lerpf(fov, target_fov, 1.0 - exp(-4.0 * dt))
