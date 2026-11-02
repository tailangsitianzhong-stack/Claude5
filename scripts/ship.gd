extends Node3D
## 宇宙船の操縦・飛行モデル（物理エンジン不使用のアーケード寄り6DoF）

signal collided(strength: float)
signal message(text: String)

enum Warp { OFF, SPOOL, ACTIVE }

@export_group("速度")
@export var max_speed := 300.0           ## 通常最高速度 (m/s)
@export var boost_multiplier := 2.5      ## ブースト時の最高速度倍率
@export var reverse_ratio := 0.35        ## 後退スロットルの上限
@export var assist_accel := 160.0        ## FA ON時の加減速度
@export var thrust_accel := 120.0        ## FA OFF時の推力
@export var strafe_speed := 90.0         ## 平行移動の速度
@export var throttle_rate := 0.7         ## W/S長押しでのスロットル変化/秒

@export_group("回転")
@export var pitch_rate := 1.5            ## rad/s
@export var yaw_rate := 1.1
@export var roll_rate := 2.6
@export var rot_response := 5.0          ## 回転の追従性（大きいほどキビキビ）

@export_group("ブースト")
@export var boost_drain := 0.22
@export var boost_regen := 0.12

@export_group("ワープ")
@export var warp_max_speed := 15000.0
@export var warp_spool_time := 2.0
@export var warp_accel := 6000.0

@export_group("マウス")
@export var mouse_sensitivity := 0.0022
@export var mouse_deadzone := 0.05
@export var direct_mouse_gain := 0.06

var world: Node = null
var velocity := Vector3.ZERO
var ang_vel := Vector3.ZERO
var throttle := 0.0
var boost_energy := 1.0
var boost_amount := 0.0            ## 0..1 演出用
var boosting := false
var flight_assist := true
var warp_state := Warp.OFF
var warp_timer := 0.0
var warp_speed := 0.0
var warp_amount := 0.0             ## 0..1 演出用
var steer := Vector2.ZERO          ## 仮想ジョイスティック (-1..1)
var virtual_joystick := true
var invert_y := false
var collision_radius := 6.0
var aligning := false
var touch_steer := Vector2.ZERO    ## タッチ操作の仮想スティック (-1..1)

var _direct_mouse := Vector2.ZERO
var _model: Node3D


func _ready() -> void:
	_model = preload("res://scripts/ship_model.gd").new()
	add_child(_model)


func set_model_visible(v: bool) -> void:
	_model.visible = v


func reset(xform: Transform3D) -> void:
	global_transform = xform
	velocity = Vector3.ZERO
	ang_vel = Vector3.ZERO
	throttle = 0.0
	boost_energy = 1.0
	warp_state = Warp.OFF
	warp_speed = 0.0
	steer = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if virtual_joystick:
			steer += event.relative * mouse_sensitivity
			steer = steer.limit_length(1.0)
		else:
			_direct_mouse += event.relative
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			throttle = clampf(throttle + 0.05, -reverse_ratio, 1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			throttle = clampf(throttle - 0.05, -reverse_ratio, 1.0)

	if event.is_action_pressed("recenter"):
		steer = Vector2.ZERO
	elif event.is_action_pressed("flight_assist"):
		flight_assist = not flight_assist
		message.emit("フライトアシスト: " + ("ON" if flight_assist else "OFF（慣性飛行）"))
	elif event.is_action_pressed("mouse_mode"):
		virtual_joystick = not virtual_joystick
		steer = Vector2.ZERO
		message.emit("マウス操作: " + ("仮想ジョイスティック" if virtual_joystick else "ダイレクト"))
	elif event.is_action_pressed("invert_y"):
		invert_y = not invert_y
		message.emit("上下反転: " + ("ON" if invert_y else "OFF"))
	elif event.is_action_pressed("throttle_zero"):
		throttle = 0.0
	elif event.is_action_pressed("warp"):
		_toggle_warp()


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	var input := _read_rotation_input(dt)
	_update_rotation(dt, input)
	_update_throttle(dt)
	_update_warp(dt)
	_update_translation(dt)
	global_position += velocity * dt
	_resolve_collisions()

	boost_amount = lerpf(boost_amount, 1.0 if boosting else 0.0, 1.0 - exp(-6.0 * dt))
	warp_amount = lerpf(warp_amount, clampf(warp_speed / 4000.0, 0.0, 1.0) if warp_state == Warp.ACTIVE else 0.0, 1.0 - exp(-4.0 * dt))
	_model.update_engine(dt, throttle, boost_amount, warp_amount)


func _read_rotation_input(dt: float) -> Vector3:
	var pitch := 0.0
	var yaw := 0.0
	if virtual_joystick:
		var s := steer
		var l := s.length()
		if l < mouse_deadzone:
			s = Vector2.ZERO
		else:
			s = s.normalized() * ((l - mouse_deadzone) / (1.0 - mouse_deadzone))
		pitch = -s.y
		yaw = -s.x
	else:
		var m := _direct_mouse * direct_mouse_gain
		_direct_mouse = Vector2.ZERO
		# ダイレクト操作はフレームレート依存を避けるためdtで正規化
		pitch = clampf(-m.y / maxf(dt * 60.0, 0.001), -1.0, 1.0)
		yaw = clampf(-m.x / maxf(dt * 60.0, 0.001), -1.0, 1.0)

	pitch += -touch_steer.y
	yaw += -touch_steer.x
	pitch += Input.get_axis("pitch_down", "pitch_up")
	yaw += Input.get_axis("yaw_right", "yaw_left")
	var roll := Input.get_axis("roll_right", "roll_left")
	if invert_y:
		pitch = -pitch

	# ターゲットへの自動旋回
	aligning = Input.is_action_pressed("align") and world != null and world.get_target_position() != null
	if aligning:
		var dir: Vector3 = (world.get_target_position() - global_position).normalized()
		var local := global_basis.inverse() * dir
		pitch = clampf(local.y * 4.0, -1.0, 1.0)
		yaw = clampf(-local.x * 4.0, -1.0, 1.0)
		if local.z > 0.0:  # 後方にある場合は最短方向へ全力旋回
			yaw = signf(-local.x) if absf(local.x) > 0.01 else 1.0

	return Vector3(clampf(pitch, -1, 1), clampf(yaw, -1, 1), clampf(roll, -1, 1))


func _update_rotation(dt: float, input: Vector3) -> void:
	var scale_rate := 0.3 if warp_state == Warp.ACTIVE else 1.0
	var target := Vector3(input.x * pitch_rate, input.y * yaw_rate, input.z * roll_rate) * scale_rate
	ang_vel = ang_vel.lerp(target, 1.0 - exp(-rot_response * dt))
	var b := global_basis
	b = b * Basis(Vector3.RIGHT, ang_vel.x * dt)
	b = b * Basis(Vector3.UP, ang_vel.y * dt)
	b = b * Basis(Vector3.BACK, ang_vel.z * dt)
	global_basis = b.orthonormalized()


func _update_throttle(dt: float) -> void:
	var t_in := Input.get_axis("throttle_down", "throttle_up")
	throttle = clampf(throttle + t_in * throttle_rate * dt, -reverse_ratio, 1.0)

	var want_boost := Input.is_action_pressed("boost") and throttle > 0.0 and warp_state == Warp.OFF
	if want_boost and boost_energy > 0.0:
		boosting = true
		boost_energy = maxf(boost_energy - boost_drain * dt, 0.0)
	else:
		boosting = false
		if not Input.is_action_pressed("boost"):
			boost_energy = minf(boost_energy + boost_regen * dt, 1.0)


func _update_translation(dt: float) -> void:
	if warp_state == Warp.ACTIVE:
		velocity = -global_basis.z * warp_speed
		return

	var fwd := -global_basis.z
	var right := global_basis.x
	var up := global_basis.y
	var strafe := Vector2(Input.get_axis("strafe_left", "strafe_right"), Input.get_axis("strafe_down", "strafe_up"))
	var cap := max_speed * (boost_multiplier if boosting else 1.0)

	if flight_assist:
		var desired := fwd * throttle * cap + right * strafe.x * strafe_speed + up * strafe.y * strafe_speed
		var a := assist_accel * (2.0 if boosting else 1.0)
		# 現在速度が上限を超えている場合（ワープ明けなど）は素早く減速
		if velocity.length() > cap * 1.05:
			a *= 3.0
		velocity = velocity.move_toward(desired, a * dt)
	else:
		var thrust := fwd * throttle * thrust_accel * (2.0 if boosting else 1.0)
		thrust += (right * strafe.x + up * strafe.y) * thrust_accel * 0.6
		velocity += thrust * dt
		velocity = velocity.limit_length(cap * 1.2)


# ---------------- ワープ ----------------

func _toggle_warp() -> void:
	if warp_state != Warp.OFF:
		_exit_warp("ワープ解除")
		return
	var near := _nearest_body_info()
	if near.size() > 0 and near.surface < near.radius * 1.0:
		message.emit("ワープ不可: %s の重力圏内" % near.name)
		return
	warp_state = Warp.SPOOL
	warp_timer = 0.0
	message.emit("ワープドライブ充填中…")


func _update_warp(dt: float) -> void:
	match warp_state:
		Warp.SPOOL:
			warp_timer += dt
			if warp_timer >= warp_spool_time:
				warp_state = Warp.ACTIVE
				warp_speed = maxf(velocity.length(), max_speed)
				message.emit("ワープ！")
		Warp.ACTIVE:
			var near := _nearest_body_info()
			var limit := warp_max_speed
			if near.size() > 0:
				# 天体に近づくと自動減速
				limit = clampf(near.surface * 0.7, 400.0, warp_max_speed)
				if near.surface < near.radius * 0.5:
					_exit_warp("重力井戸に捕捉 — %s 付近でワープ離脱" % near.name)
					return
			if warp_speed < limit:
				warp_speed = minf(warp_speed + warp_accel * dt, limit)
			else:
				warp_speed = lerpf(warp_speed, limit, 1.0 - exp(-5.0 * dt))


func _exit_warp(msg: String) -> void:
	var was_active := warp_state == Warp.ACTIVE
	warp_state = Warp.OFF
	warp_speed = 0.0
	if was_active:
		velocity = -global_basis.z * max_speed * 1.5
	message.emit(msg)


func _nearest_body_info() -> Dictionary:
	if world == null:
		return {}
	return world.get_nearest_body(global_position)


# ---------------- 衝突 ----------------

func _resolve_collisions() -> void:
	if world == null:
		return
	for b in world.bodies:
		var c: Vector3 = b.node.global_position
		var r: float = b.radius + collision_radius
		_push_out(c, r, 0.4)
	if warp_state != Warp.ACTIVE:
		for hit in world.collide_asteroids(global_position, collision_radius):
			_push_out(hit[0], hit[1] + collision_radius, 0.5)


func _push_out(center: Vector3, r: float, bounce: float) -> void:
	var d := global_position - center
	var l := d.length()
	if l >= r or l < 0.001:
		return
	var n := d / l
	global_position = center + n * r
	var vn := velocity.dot(n)
	if vn < 0.0:
		velocity -= n * vn * (1.0 + bounce)
		velocity *= 0.8
		if warp_state != Warp.OFF:
			_exit_warp("衝突によりワープ中断")
		collided.emit(-vn)
