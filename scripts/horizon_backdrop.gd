extends Control
## Fundo animado: céu da noite caindo, sol se pondo no horizonte,
## serras com pinheiros em silhueta e brasas subindo.

const SKY_TOP := Color("0b0f1a")
const SKY_MID := Color("2b1b33")
const SKY_LOW := Color("c4532a")
const SUN_CORE := Color("ffc27a")
const SUN_GLOW := Color("ff8a3d")
const RIDGE_FAR := Color("1c1524")
const RIDGE_NEAR := Color("0d1015")

const SKY_BANDS := 48
const RIDGE_POINTS := 64
const EMBER_COUNT := 42

## Altura do horizonte, como fração da altura da tela.
@export_range(0.3, 0.9) var horizon := 0.64

var _t := 0.0
var _far := PackedFloat32Array()
var _near := PackedFloat32Array()
var _trees: Array[Vector2] = []  # x (0..1), altura relativa
var _embers: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var noise := FastNoiseLite.new()
	noise.seed = randi()
	noise.frequency = 0.06
	for i in RIDGE_POINTS + 1:
		_far.append(noise.get_noise_1d(i * 1.0) * 0.5 + 0.5)
		_near.append(noise.get_noise_1d(i * 1.7 + 300.0) * 0.5 + 0.5)
	for i in 36:
		_trees.append(Vector2(randf(), randf_range(0.6, 1.0)))
	for i in EMBER_COUNT:
		_embers.append(_new_ember(true))
	resized.connect(queue_redraw)


func _new_ember(anywhere: bool) -> Dictionary:
	return {
		"x": randf(),
		"y": randf() if anywhere else 1.05,
		"speed": randf_range(0.03, 0.09),
		"sway": randf_range(0.004, 0.012),
		"phase": randf() * TAU,
		"size": randf_range(1.2, 3.2),
	}


func _process(delta: float) -> void:
	_t += delta
	for i in _embers.size():
		var e: Dictionary = _embers[i]
		e.y -= e.speed * delta
		if e.y < 0.25:
			_embers[i] = _new_ember(false)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var hy := h * horizon

	# Céu em faixas: topo escuro -> roxo -> brasa no horizonte.
	var band_h := hy / SKY_BANDS
	for i in SKY_BANDS:
		var k := float(i) / (SKY_BANDS - 1)
		var c := SKY_TOP.lerp(SKY_MID, clampf(k * 1.6, 0.0, 1.0))
		c = c.lerp(SKY_LOW, pow(k, 3.2))
		draw_rect(Rect2(0, i * band_h, w, band_h + 1.0), c)

	# Sol pulsando devagar sobre o horizonte.
	var pulse := 1.0 + sin(_t * 1.3) * 0.03
	var sun_r := h * 0.15 * pulse
	var sun_c := Vector2(w * 0.5, hy + h * 0.02)
	for i in range(18, 0, -1):
		var g := SUN_GLOW
		g.a = 0.018
		draw_circle(sun_c, sun_r * (1.0 + i * 0.15), g)
	draw_circle(sun_c, sun_r, SUN_GLOW)
	draw_circle(sun_c, sun_r * 0.72, SUN_CORE)

	# Serras: distante (roxa) e próxima (preta, com pinheiros).
	_draw_ridge(_far, hy, h * 0.07, RIDGE_FAR, 0.0)
	_draw_ridge(_near, hy + h * 0.035, h * 0.05, RIDGE_NEAR, 0.0)
	for tr in _trees:
		var x := tr.x * w
		var base := hy + h * 0.035 - _sample(_near, tr.x) * h * 0.05 + 2.0
		var th := h * 0.055 * tr.y
		var tw := th * 0.32
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - tw, base), Vector2(x, base - th), Vector2(x + tw, base)
		]), RIDGE_NEAR)
	draw_rect(Rect2(0, hy + h * 0.035, w, h), RIDGE_NEAR)

	# Brasas subindo.
	for e in _embers:
		var ex: float = e.x * w + sin(_t * 2.0 + e.phase) * e.sway * w
		var ey: float = e.y * h
		var fade := clampf((e.y - 0.25) / 0.35, 0.0, 1.0)
		var c := SUN_GLOW.lerp(SUN_CORE, 0.5 + 0.5 * sin(_t * 6.0 + e.phase))
		c.a = 0.85 * fade
		draw_circle(Vector2(ex, ey), e.size, c)


func _sample(arr: PackedFloat32Array, x: float) -> float:
	var f := clampf(x, 0.0, 1.0) * RIDGE_POINTS
	var i := mini(int(f), RIDGE_POINTS - 1)
	return lerpf(arr[i], arr[i + 1], f - i)


func _draw_ridge(arr: PackedFloat32Array, base_y: float, amp: float, color: Color, _offset: float) -> void:
	var w := size.x
	var pts := PackedVector2Array()
	pts.append(Vector2(0, base_y + amp))
	for i in RIDGE_POINTS + 1:
		pts.append(Vector2(w * i / RIDGE_POINTS, base_y - arr[i] * amp))
	pts.append(Vector2(w, base_y + amp))
	draw_colored_polygon(pts, color)
