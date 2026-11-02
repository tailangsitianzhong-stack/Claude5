extends Control
## スマホ用タッチ操作（マルチタッチ対応）
## 左: フローティング仮想スティック（機首の向き） / 右: スロットルスライダーとボタン

const C_LINE := Color(0.45, 0.9, 1.0, 0.55)
const C_FILL := Color(0.45, 0.9, 1.0, 0.12)
const C_ACTIVE := Color(0.45, 0.9, 1.0, 0.45)
const C_TEXT := Color(0.85, 0.97, 1.0, 0.95)

@export var stick_radius := 110.0
@export var stick_expo := 1.6   ## 大きいほど中心付近が繊細になる

var ship: Node3D

## index -> {"role": String, "origin": Vector2, "pos": Vector2}
var _touches := {}
var _buttons: Array = []
var _font: Font
var _slider_rect := Rect2()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	if visible:
		_layout()
		queue_redraw()


func _layout() -> void:
	var sz := get_viewport_rect().size
	var r := 52.0
	var s := 44.0
	_slider_rect = Rect2(sz.x - 120.0, sz.y - 420.0, 80.0, 360.0)
	# hold: 押している間だけ有効 / tap: 押した瞬間に1回
	_buttons = [
		{"id": "boost", "label": "BOOST", "pos": Vector2(sz.x - 250, sz.y - 120), "r": r + 10, "action": "boost", "hold": true},
		{"id": "warp", "label": "WARP", "pos": Vector2(sz.x - 250, sz.y - 270), "r": r, "action": "warp", "hold": false},
		{"id": "align", "label": "自動旋回", "pos": Vector2(sz.x - 385, sz.y - 190), "r": r, "action": "align", "hold": true},
		{"id": "roll_l", "label": "↺", "pos": Vector2(90, sz.y - 400), "r": s, "action": "roll_left", "hold": true},
		{"id": "roll_r", "label": "↻", "pos": Vector2(200, sz.y - 400), "r": s, "action": "roll_right", "hold": true},
		{"id": "up", "label": "▲", "pos": Vector2(310, sz.y - 400), "r": 36.0, "action": "strafe_up", "hold": true},
		{"id": "down", "label": "▼", "pos": Vector2(390, sz.y - 400), "r": 36.0, "action": "strafe_down", "hold": true},
		{"id": "target", "label": "TGT", "pos": Vector2(sz.x - 450, 45), "r": 34.0, "action": "target_next", "hold": false},
		{"id": "cam", "label": "CAM", "pos": Vector2(sz.x - 530, 45), "r": 34.0, "action": "camera_mode", "hold": false},
		{"id": "fa", "label": "FA", "pos": Vector2(sz.x - 610, 45), "r": 34.0, "action": "flight_assist", "hold": false},
		{"id": "reset", "label": "↩", "pos": Vector2(sz.x - 690, 45), "r": 34.0, "action": "reset", "hold": false},
	]


func _input(event: InputEvent) -> void:
	if not visible or ship == null:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_down(event.index, event.position)
		else:
			_on_up(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if _touches.has(event.index):
			_touches[event.index].pos = event.position
			_on_move(event.index)
		get_viewport().set_input_as_handled()


func _on_down(index: int, p: Vector2) -> void:
	_layout()
	var sz := get_viewport_rect().size
	for b in _buttons:
		if p.distance_to(b.pos) <= b.r * 1.15:
			_touches[index] = {"role": b.id, "origin": p, "pos": p}
			if b.hold:
				Input.action_press(b.action)
			else:
				_tap_action(b.action)
			return
	if _slider_rect.grow(30.0).has_point(p):
		_touches[index] = {"role": "throttle", "origin": p, "pos": p}
		_on_move(index)
		return
	if p.x < sz.x * 0.5:
		# 左半分: タッチした位置にスティックを出す
		_touches[index] = {"role": "stick", "origin": p, "pos": p}
		return


func _on_move(index: int) -> void:
	var t: Dictionary = _touches[index]
	match t.role:
		"stick":
			var d: Vector2 = (t.pos - t.origin) / stick_radius
			if d.length() > 1.0:
				# 指が離れすぎたらスティックの中心を追従させる
				t.origin = t.pos - d.normalized() * stick_radius
				d = d.normalized()
			var l := d.length()
			ship.touch_steer = d.normalized() * pow(l, stick_expo) if l > 0.0 else Vector2.ZERO
		"throttle":
			var ratio := 1.0 - clampf((t.pos.y - _slider_rect.position.y) / _slider_rect.size.y, 0.0, 1.0)
			# 下端 = 後退上限、上端 = 100%
			var rev: float = ship.reverse_ratio
			var thr := lerpf(-rev, 1.0, ratio)
			if absf(thr) < 0.04:
				thr = 0.0  # 0付近に吸着
			ship.throttle = thr


func _on_up(index: int) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	_touches.erase(index)
	if t.role == "stick":
		ship.touch_steer = Vector2.ZERO
		return
	for b in _buttons:
		if b.id == t.role and b.hold:
			# 同じボタンを他の指が押していなければ離す
			var still := false
			for other in _touches.values():
				if other.role == b.id:
					still = true
			if not still:
				Input.action_release(b.action)


func _tap_action(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	var e2 := InputEventAction.new()
	e2.action = action
	e2.pressed = false
	Input.parse_input_event(e2)


func release_all() -> void:
	for t in _touches.values():
		for b in _buttons:
			if b.id == t.role and b.hold:
				Input.action_release(b.action)
	_touches.clear()
	if ship:
		ship.touch_steer = Vector2.ZERO


func _is_pressed(id: String) -> bool:
	for t in _touches.values():
		if t.role == id:
			return true
	return false


func _draw() -> void:
	if ship == null:
		return
	var sz := get_viewport_rect().size

	# スティック
	var stick_drawn := false
	for t in _touches.values():
		if t.role == "stick":
			draw_circle(t.origin, stick_radius, C_FILL)
			draw_arc(t.origin, stick_radius, 0, TAU, 48, C_LINE, 2.0)
			var knob: Vector2 = t.origin + (t.pos - t.origin).limit_length(stick_radius)
			draw_circle(knob, 34, C_ACTIVE)
			stick_drawn = true
	if not stick_drawn:
		var hint := Vector2(230, sz.y - 190)
		draw_arc(hint, stick_radius, 0, TAU, 48, Color(C_LINE, 0.25), 2.0)
		draw_circle(hint, 30, Color(C_FILL, 0.1))
		_center_text(hint + Vector2(0, stick_radius + 28), "ドラッグで旋回", 15, Color(C_TEXT, 0.4))

	# スロットル
	var sr := _slider_rect
	draw_rect(sr, C_FILL, true)
	draw_rect(sr, C_LINE, false, 2.0)
	var rev: float = ship.reverse_ratio
	var zero_y := sr.position.y + sr.size.y * (1.0 - rev / (1.0 + rev))
	draw_line(Vector2(sr.position.x - 8, zero_y), Vector2(sr.end.x + 8, zero_y), C_LINE, 2.0)
	var ty: float = sr.position.y + sr.size.y * (1.0 - (ship.throttle + rev) / (1.0 + rev))
	var fill_col := C_ACTIVE if ship.throttle >= 0.0 else Color(1.0, 0.35, 0.25, 0.45)
	draw_rect(Rect2(sr.position.x, minf(ty, zero_y), sr.size.x, absf(zero_y - ty)), fill_col, true)
	draw_rect(Rect2(sr.position.x - 6, ty - 5, sr.size.x + 12, 10), C_TEXT, true)
	_center_text(Vector2(sr.get_center().x, sr.position.y - 14), "THR", 16, C_TEXT)

	# ボタン
	for b in _buttons:
		var pressed: bool = _is_pressed(b.id) or (b.hold and Input.is_action_pressed(b.action))
		draw_circle(b.pos, b.r, C_ACTIVE if pressed else C_FILL)
		draw_arc(b.pos, b.r, 0, TAU, 40, C_LINE, 2.0)
		var fs := 18 if b.r > 40.0 else 15
		if b.label.length() <= 1:
			fs = 30
		_center_text(b.pos + Vector2(0, fs * 0.35), b.label, fs, C_TEXT)


func _center_text(p: Vector2, s: String, fs: int, col: Color) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, p - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
