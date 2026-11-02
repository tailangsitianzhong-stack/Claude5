extends Control
## HUD（_drawで描画）

const C_MAIN := Color(0.45, 0.9, 1.0, 0.9)
const C_DIM := Color(0.45, 0.9, 1.0, 0.35)
const C_WARN := Color(1.0, 0.35, 0.25, 0.95)
const C_TARGET := Color(1.0, 0.85, 0.3, 0.95)
const C_GATE := Color(1.0, 0.55, 0.15, 0.95)
const C_PROGRADE := Color(0.5, 1.0, 0.5, 0.9)

var ship: Node3D
var camera: Camera3D
var world: Node
var show_help := true

var _msg := ""
var _msg_time := 0.0
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func show_message(text: String, duration := 3.0) -> void:
	_msg = text
	_msg_time = duration


func _process(delta: float) -> void:
	_msg_time = maxf(_msg_time - delta, 0.0)
	queue_redraw()


func _text(pos: Vector2, s: String, size := 16, col := C_MAIN, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(_font, pos + Vector2(1, 1), s, align, width, size, Color(0, 0, 0, col.a * 0.6))
	draw_string(_font, pos, s, align, width, size, col)


static func fmt_dist(d: float) -> String:
	if d >= 1000.0:
		return "%.1f km" % (d / 1000.0)
	return "%d m" % int(d)


static func fmt_time(t: float) -> String:
	if t > 3600.0:
		return "--:--"
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


func _draw() -> void:
	if ship == null or camera == null:
		return
	var sz := get_viewport_rect().size
	if sz.x < 200.0 or sz.y < 200.0:
		return
	var center := sz * 0.5

	# クロスヘア
	draw_line(center + Vector2(-14, 0), center + Vector2(-5, 0), C_MAIN, 2)
	draw_line(center + Vector2(5, 0), center + Vector2(14, 0), C_MAIN, 2)
	draw_line(center + Vector2(0, 5), center + Vector2(0, 12), C_MAIN, 2)

	# 仮想ジョイスティック表示
	if ship.virtual_joystick:
		var r := 110.0
		draw_arc(center, r, 0, TAU, 64, C_DIM, 1.5)
		draw_arc(center, r * ship.mouse_deadzone, 0, TAU, 24, C_DIM, 1.0)
		var p: Vector2 = center + ship.steer * r
		draw_line(center, p, C_DIM, 1.5)
		draw_circle(p, 5, C_MAIN)

	# 進行方向マーカー
	if ship.velocity.length() > 5.0:
		var pp: Vector3 = camera.global_position + ship.velocity.normalized() * 5000.0
		if not camera.is_position_behind(pp):
			var sp := camera.unproject_position(pp)
			draw_arc(sp, 9, 0, TAU, 24, C_PROGRADE, 2)
			draw_line(sp + Vector2(-16, 0), sp + Vector2(-9, 0), C_PROGRADE, 2)
			draw_line(sp + Vector2(9, 0), sp + Vector2(16, 0), C_PROGRADE, 2)
			draw_line(sp + Vector2(0, -9), sp + Vector2(0, -15), C_PROGRADE, 2)

	# ゲートマーカー
	var gate_pos = world.get_next_gate_position()
	if gate_pos != null:
		_draw_marker(gate_pos, "GATE %d/%d" % [world.gate_index + 1, world.gates.size()], C_GATE, sz, -20.0)

	# ターゲットマーカー
	var tgt = world.get_target()
	if tgt != null:
		var tp: Vector3 = tgt.node.global_position
		var d: float = (tp - ship.global_position).length() - tgt.radius
		_draw_marker(tp, "%s  %s" % [tgt.name, fmt_dist(maxf(d, 0.0))], C_TARGET, sz)

	_draw_status_panel(sz)
	_draw_target_panel(sz)
	_draw_gate_panel(sz)

	# 近接警告
	var near: Dictionary = world.get_nearest_body(ship.global_position)
	if near.size() > 0:
		var to_center: Vector3 = (near.node.global_position - ship.global_position).normalized()
		var closing: float = ship.velocity.dot(to_center)
		if near.surface < 600.0 and closing > 20.0 and int(Time.get_ticks_msec() / 250) % 2 == 0:
			_text(Vector2(0, center.y - 140), "⚠ 近接警告  %s  高度 %s" % [near.name, fmt_dist(near.surface)], 24, C_WARN, HORIZONTAL_ALIGNMENT_CENTER, sz.x)

	# ワープ充填
	if ship.warp_state == 1:
		var w := 300.0
		var ratio: float = ship.warp_timer / ship.warp_spool_time
		var rect := Rect2(center.x - w * 0.5, center.y + 80, w, 8)
		draw_rect(rect, C_DIM, false, 1.5)
		draw_rect(Rect2(rect.position, Vector2(w * ratio, 8)), Color(0.7, 0.5, 1.0), true)
		_text(Vector2(0, center.y + 72), "WARP CHARGING", 16, Color(0.8, 0.65, 1.0), HORIZONTAL_ALIGNMENT_CENTER, sz.x)

	# メッセージ
	if _msg_time > 0.0:
		var a := clampf(_msg_time, 0.0, 1.0)
		_text(Vector2(0, 90), _msg, 24, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, sz.x)

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_text(Vector2(0, center.y + 160), "クリックで操縦再開", 22, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, sz.x)

	if show_help:
		_draw_help(sz)
	else:
		_text(Vector2(sz.x - 200, sz.y - 20), "H: 操作説明", 14, C_DIM)


func _draw_marker(world_pos: Vector3, label: String, col: Color, sz: Vector2, label_dy := 0.0) -> void:
	var margin := 40.0
	var behind := camera.is_position_behind(world_pos)
	var sp := camera.unproject_position(world_pos)
	var on_screen := not behind and Rect2(Vector2(margin, margin), sz - Vector2(margin, margin) * 2).has_point(sp)
	if on_screen:
		var s := 14.0
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var c: Vector2 = sp + corner * s
			draw_line(c, c - Vector2(corner.x * 6, 0), col, 2)
			draw_line(c, c - Vector2(0, corner.y * 6), col, 2)
		_text(sp + Vector2(20, -6 + label_dy), label, 15, col)
	else:
		# 画面外: 端に矢印
		var center := sz * 0.5
		var local: Vector3 = camera.global_basis.inverse() * (world_pos - camera.global_position)
		var dir := Vector2(local.x, -local.y)
		if dir.length() < 0.001:
			dir = Vector2(0, 1)
		dir = dir.normalized()
		var half := center - Vector2(margin, margin)
		var t := minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
		var p := center + dir * t
		var perp := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([p + dir * 14, p - dir * 6 + perp * 9, p - dir * 6 - perp * 9]), col)
		var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var lp := p - dir * 36 - Vector2(tw * 0.5, -5.0 - label_dy)
		lp.x = clampf(lp.x, 8.0, sz.x - tw - 8.0)
		lp.y = clampf(lp.y, 20.0, sz.y - 8.0)
		_text(lp, label, 14, col)


func _draw_status_panel(sz: Vector2) -> void:
	var x := 30.0
	var y := sz.y - 200.0
	var spd: float = ship.velocity.length()
	_text(Vector2(x, y), "SPEED", 14, C_DIM)
	_text(Vector2(x, y + 34), "%d m/s" % int(spd), 32, C_MAIN)

	# スロットル
	var bx := x
	var by := y + 60
	var bw := 220.0
	draw_rect(Rect2(bx, by, bw, 10), C_DIM, false, 1.5)
	var zero_x: float = bx + bw * (ship.reverse_ratio / (1.0 + ship.reverse_ratio))
	draw_line(Vector2(zero_x, by - 3), Vector2(zero_x, by + 13), C_MAIN, 1.5)
	var tw: float = bw / (1.0 + ship.reverse_ratio) * ship.throttle
	var tcol := C_MAIN if ship.throttle >= 0.0 else C_WARN
	draw_rect(Rect2(minf(zero_x, zero_x + tw), by, absf(tw), 10), tcol, true)
	_text(Vector2(bx + bw + 10, by + 10), "THR %d%%" % int(ship.throttle * 100), 14, C_MAIN)

	# ブースト
	by += 26
	draw_rect(Rect2(bx, by, bw, 6), C_DIM, false, 1.0)
	draw_rect(Rect2(bx, by, bw * ship.boost_energy, 6), Color(1.0, 0.6, 0.2, 0.9), true)
	_text(Vector2(bx + bw + 10, by + 7), "BOOST", 13, Color(1.0, 0.6, 0.2, 0.9))

	by += 30
	var fa := "FA: ON" if ship.flight_assist else "FA: OFF"
	_text(Vector2(bx, by), fa, 15, C_MAIN if ship.flight_assist else C_WARN)
	var warp_txt: String = ["WARP: 待機", "WARP: 充填中", "WARP: 航行中"][ship.warp_state]
	_text(Vector2(bx + 90, by), warp_txt, 15, Color(0.8, 0.65, 1.0) if ship.warp_state > 0 else C_DIM)
	if ship.aligning:
		_text(Vector2(bx, by + 22), "AUTO-ALIGN", 15, C_TARGET)


func _draw_target_panel(sz: Vector2) -> void:
	var tgt = world.get_target()
	if tgt == null:
		return
	var x := sz.x - 330.0
	var y := sz.y - 200.0
	var d: float = maxf((tgt.node.global_position - ship.global_position).length() - tgt.radius, 0.0)
	var dir: Vector3 = (tgt.node.global_position - ship.global_position).normalized()
	var closing: float = ship.velocity.dot(dir)
	_text(Vector2(x, y), "TARGET  (T: 切替 / Y長押し: 自動旋回)", 13, C_DIM)
	_text(Vector2(x, y + 30), tgt.name, 26, C_TARGET)
	_text(Vector2(x, y + 56), "距離  " + fmt_dist(d), 16, C_MAIN)
	var eta := "--:--"
	if closing > 1.0:
		eta = fmt_time(d / closing)
	_text(Vector2(x, y + 78), "接近速度  %d m/s   ETA %s" % [int(closing), eta], 16, C_MAIN)
	_text(Vector2(x, y + 100), "半径  " + fmt_dist(tgt.radius), 14, C_DIM)


func _draw_gate_panel(sz: Vector2) -> void:
	if world.gates.is_empty():
		return
	var x := sz.x - 330.0
	var y := 40.0
	_text(Vector2(x, y), "GATE COURSE", 14, C_DIM)
	if world.gate_finished:
		_text(Vector2(x, y + 26), "完走！ タイム %.2f 秒" % world.gate_time, 20, C_GATE)
		if world.gate_best > 0.0:
			_text(Vector2(x, y + 48), "ベスト %.2f 秒   (Backspaceで再挑戦)" % world.gate_best, 14, C_MAIN)
	else:
		_text(Vector2(x, y + 26), "%d / %d   %.2f 秒" % [world.gate_index, world.gates.size(), world.gate_time], 20, C_GATE)
		if world.gate_best > 0.0:
			_text(Vector2(x, y + 48), "ベスト %.2f 秒" % world.gate_best, 14, C_MAIN)


func _draw_help(sz: Vector2) -> void:
	var lines := [
		"■ 操作説明 (Hで閉じる)",
		"マウス : 機首の向き (ピッチ/ヨー)",
		"W / S : スロットル増減   X : スロットル0   ホイール : 微調整",
		"A / D : ロール      Q / E : 左右平行移動",
		"Space / Ctrl : 上下平行移動   矢印キー : ピッチ/ヨー",
		"Shift : ブースト    Tab : ワープ (天体の近くでは不可)",
		"T : ターゲット切替   Y(長押し) : ターゲットへ自動旋回",
		"Z : フライトアシスト切替    C : カメラ切替",
		"V / 中クリック : 照準センタリング   M : マウス方式切替",
		"I : 上下反転    Backspace : リスタート    Esc : マウス解放",
	]
	var w := 560.0
	var h := 24.0 * lines.size() + 20.0
	var rect := Rect2(30, 30, w, h)
	draw_rect(rect, Color(0.0, 0.05, 0.1, 0.55), true)
	draw_rect(rect, C_DIM, false, 1.0)
	for i in lines.size():
		_text(Vector2(44, 56 + i * 24), lines[i], 15 if i > 0 else 17, C_MAIN if i > 0 else C_TARGET)
