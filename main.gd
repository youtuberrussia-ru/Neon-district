extends Node2D
## Главный экран: сетка города, камера (перетаскивание и зум), строительство, интерфейс.

const CELL := 96
const DEMOLISH := "demolish"

var camera: Camera2D
var selected: String = "house"
var money_label: Label
var income_label: Label
var toast: Label
var toast_tween: Tween

var pressing := false
var dragging := false
var pinching := false
var press_pos := Vector2.ZERO
var touches := {}
var pinch_dist := 0.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#0b0b1a"))
	camera = Camera2D.new()
	add_child(camera)
	var half := GameState.GRID * CELL / 2.0
	camera.position = Vector2(half, half)
	camera.zoom = Vector2(0.8, 0.8)
	_build_ui()
	GameState.money_changed.connect(_update_ui)
	GameState.city_changed.connect(queue_redraw)
	_update_ui()


# ---------- Отрисовка ----------

func _draw() -> void:
	var size := GameState.GRID * CELL
	draw_rect(Rect2(0, 0, size, size), Color("#14142b"))
	for i in range(GameState.GRID + 1):
		draw_line(Vector2(i * CELL, 0), Vector2(i * CELL, size), Color("#2a2a55"), 2.0)
		draw_line(Vector2(0, i * CELL), Vector2(size, i * CELL), Color("#2a2a55"), 2.0)
	draw_rect(Rect2(0, 0, size, size), Color("#00e5ff"), false, 4.0)

	var font := ThemeDB.fallback_font
	for c in GameState.cells:
		var data: Dictionary = GameState.BUILDINGS[GameState.cells[c]]
		var col: Color = data["color"]
		var origin := Vector2(c.x * CELL, c.y * CELL)
		# неоновое свечение
		draw_rect(Rect2(origin + Vector2(2, 2), Vector2(CELL - 4, CELL - 4)), Color(col, 0.25))
		# корпус
		draw_rect(Rect2(origin + Vector2(10, 10), Vector2(CELL - 20, CELL - 20)), col.darkened(0.55))
		draw_rect(Rect2(origin + Vector2(10, 10), Vector2(CELL - 20, CELL - 20)), col, false, 3.0)
		# светящиеся окна
		for wx in range(3):
			for wy in range(3):
				var wp := origin + Vector2(24 + wx * 20, 24 + wy * 20)
				draw_rect(Rect2(wp, Vector2(10, 10)), Color("#fff59d"))
		draw_string(font, origin + Vector2(0, CELL - 14), data["name"].substr(0, 1),
			HORIZONTAL_ALIGNMENT_CENTER, CELL, 22, Color.WHITE)


# ---------- Ввод ----------

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			touches[e.index] = e.position
		else:
			touches.erase(e.index)
			if touches.size() < 2:
				pinching = false
				pinch_dist = 0.0
		if touches.size() == 2:
			pinching = true
			dragging = true  # чтобы отпускание пальца не считалось тапом
			var pts := touches.values()
			pinch_dist = pts[0].distance_to(pts[1])
	elif e is InputEventScreenDrag:
		touches[e.index] = e.position
		if touches.size() == 2:
			var pts := touches.values()
			var d: float = pts[0].distance_to(pts[1])
			if pinch_dist > 0.0:
				_zoom_by(d / pinch_dist)
			pinch_dist = d
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / 1.1)
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				pressing = true
				dragging = false
				press_pos = e.position
			else:
				if pressing and not dragging and not pinching:
					_tap(get_global_mouse_position())
				pressing = false
	elif e is InputEventMouseMotion and pressing and not pinching:
		if not dragging and e.position.distance_to(press_pos) > 16.0:
			dragging = true
		if dragging:
			camera.position -= e.relative / camera.zoom.x
			_clamp_camera()


func _zoom_by(factor: float) -> void:
	var z := clampf(camera.zoom.x * factor, 0.3, 2.0)
	camera.zoom = Vector2(z, z)


func _clamp_camera() -> void:
	var size := float(GameState.GRID * CELL)
	camera.position = camera.position.clamp(Vector2.ZERO, Vector2(size, size))


func _tap(world_pos: Vector2) -> void:
	var c := Vector2i(floori(world_pos.x / CELL), floori(world_pos.y / CELL))
	if not GameState.in_bounds(c):
		return
	if selected == DEMOLISH:
		GameState.demolish(c)
	else:
		var err := GameState.build(c, selected)
		if err != "":
			_show_toast(err)


# ---------- Интерфейс ----------

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	# верхняя панель
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	ui.add_child(top)
	var top_box := VBoxContainer.new()
	top.add_child(top_box)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)  # место под вырез экрана
	top_box.add_child(spacer)
	money_label = Label.new()
	money_label.add_theme_font_size_override("font_size", 56)
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_box.add_child(money_label)
	income_label = Label.new()
	income_label.add_theme_font_size_override("font_size", 32)
	income_label.add_theme_color_override("font_color", Color("#00e5ff"))
	income_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_box.add_child(income_label)

	# нижняя панель со зданиями
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ui.add_child(bottom)
	var grid := GridContainer.new()
	grid.columns = 3
	bottom.add_child(grid)

	var group := ButtonGroup.new()
	for id in GameState.ORDER:
		var data: Dictionary = GameState.BUILDINGS[id]
		var b := _make_button("%s\n%d $" % [data["name"], data["cost"]], group)
		b.button_pressed = (id == selected)
		b.pressed.connect(func(): selected = id)
		grid.add_child(b)
	var del := _make_button("Снос\n+50%", group)
	del.pressed.connect(func(): selected = DEMOLISH)
	grid.add_child(del)

	# всплывающее сообщение
	toast = Label.new()
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	toast.add_theme_font_size_override("font_size", 44)
	toast.add_theme_color_override("font_color", Color("#ff5252"))
	toast.modulate.a = 0.0
	ui.add_child(toast)


func _make_button(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(340, 150)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 34)
	return b


func _update_ui() -> void:
	money_label.text = "$ %d" % int(GameState.money)
	income_label.text = "+%.1f в секунду" % GameState.income_per_sec()


func _show_toast(text: String) -> void:
	toast.text = text
	toast.position.x = (get_viewport_rect().size.x - toast.size.x) / 2.0
	if toast_tween:
		toast_tween.kill()
	toast.modulate.a = 1.0
	toast_tween = create_tween()
	toast_tween.tween_interval(0.6)
	toast_tween.tween_property(toast, "modulate:a", 0.0, 0.5)
