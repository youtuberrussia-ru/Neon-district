extends Node
## Глобальное состояние игры (autoload "GameState"): деньги, город, доход, сохранение.

signal money_changed
signal city_changed

const GRID := 12
const SAVE_PATH := "user://save.json"
const OFFLINE_CAP := 7200.0  # максимум 2 часа дохода в офлайне
const REFUND := 0.5          # при сносе возвращается 50% стоимости

const ORDER := ["house", "shop", "factory", "power", "tower"]
const BUILDINGS := {
	"house":   {"name": "Дом",          "cost": 100,  "income": 2.0,   "color": Color("#4fc3f7")},
	"shop":    {"name": "Магазин",      "cost": 250,  "income": 6.0,   "color": Color("#ffb74d")},
	"factory": {"name": "Завод",        "cost": 600,  "income": 16.0,  "color": Color("#ba68c8")},
	"power":   {"name": "Электростанция", "cost": 1200, "income": 35.0, "color": Color("#81c784")},
	"tower":   {"name": "Небоскрёб",    "cost": 3000, "income": 100.0, "color": Color("#ff4081")},
}

var money := 500.0
var cells := {}  # Vector2i -> String (id здания)

var _tick := 0.0
var _save_timer := 0.0


func _ready() -> void:
	load_game()


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		var n := floorf(_tick)
		_tick -= n
		money += income_per_sec() * n
		money_changed.emit()
	_save_timer += delta
	if _save_timer >= 10.0:
		_save_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < GRID and c.y < GRID


func income_per_sec() -> float:
	var total := 0.0
	for id in cells.values():
		total += BUILDINGS[id]["income"]
	return total


## Возвращает "" при успехе, иначе текст ошибки.
func build(c: Vector2i, id: String) -> String:
	if not in_bounds(c):
		return ""
	if cells.has(c):
		return "Клетка занята"
	var cost: float = BUILDINGS[id]["cost"]
	if money < cost:
		return "Не хватает денег"
	money -= cost
	cells[c] = id
	money_changed.emit()
	city_changed.emit()
	return ""


func demolish(c: Vector2i) -> void:
	if not cells.has(c):
		return
	money += floorf(BUILDINGS[cells[c]]["cost"] * REFUND)
	cells.erase(c)
	money_changed.emit()
	city_changed.emit()


func save_game() -> void:
	var data := {"money": money, "time": Time.get_unix_time_from_system(), "cells": {}}
	for c in cells:
		data["cells"]["%d,%d" % [c.x, c.y]] = cells[c]
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	money = float(data.get("money", money))
	cells.clear()
	var saved: Dictionary = data.get("cells", {})
	for key in saved:
		var parts: PackedStringArray = str(key).split(",")
		var id: String = saved[key]
		if parts.size() == 2 and BUILDINGS.has(id):
			cells[Vector2i(int(parts[0]), int(parts[1]))] = id
	var elapsed := clampf(Time.get_unix_time_from_system() - float(data.get("time", 0)), 0.0, OFFLINE_CAP)
	money += elapsed * income_per_sec()
