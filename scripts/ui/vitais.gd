extends Control
## As três barras do jogador (canto de cima, à direita): vida, fome e sede.
## Num cartão escuro com borda dourada fina; cada uma com o ícone num círculo (coração,
## fruta, gota), a barra lisa em degradê com brilho em cima, o trilho escuro da mesma cor
## atrás (e um rastro claro do que acabou de baixar) e a porcentagem. Baixa (menos
## de 25%), o ícone pulsa e a barra pisca. (Os valores vêm do jogo: 0 a 100.)

var vida := 100.0
var fome := 100.0
var sede := 100.0
var _mostra := {"vida": 100.0, "fome": 100.0, "sede": 100.0}     # anima suave até o valor
var _rastro := {"vida": 100.0, "fome": 100.0, "sede": 100.0}     # o que baixou: vai sumindo devagar

const W := 300.0
const ROW := 38.0

const CORES := {
	"vida": [Color(0.72, 0.1, 0.14), Color(1.0, 0.36, 0.32)],
	"fome": [Color(0.82, 0.42, 0.08), Color(1.0, 0.76, 0.3)],
	"sede": [Color(0.12, 0.42, 0.86), Color(0.42, 0.84, 1.0)],
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, ROW * 3 + 20)


func _process(delta: float) -> void:
	var alvo := {"vida": vida, "fome": fome, "sede": sede}
	for k in alvo:
		_mostra[k] = move_toward(float(_mostra[k]), float(alvo[k]), delta * 40.0)
		if float(_mostra[k]) >= float(_rastro[k]):
			_rastro[k] = _mostra[k]
		else:
			_rastro[k] = move_toward(float(_rastro[k]), float(_mostra[k]), delta * 6.0)
	queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var card := Rect2(Vector2.ZERO, Vector2(W, ROW * 3 + 18))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.035, 0.03, 0.62)
	sb.border_color = Color(0.86, 0.7, 0.38, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	draw_style_box(sb, card)
	var i := 0
	for k in ["vida", "fome", "sede"]:
		_linha(k, Vector2(12, 10 + i * ROW), float(_mostra[k]), t, float(_rastro[k]))
		i += 1


func _linha(k: String, o: Vector2, v: float, t: float, rastro := -1.0) -> void:
	var baixo := v < 25.0
	var pulse := (0.5 + 0.5 * sin(t * 7.0)) if baixo else 0.0
	var c: Array = CORES[k]
	var c0: Color = c[0]
	var c1: Color = c[1]
	# o ícone num círculo
	var ic := o + Vector2(15, ROW * 0.5 - 2)
	var r := 15.0 + pulse * 2.0
	draw_circle(ic, r + 2.0, Color(0, 0, 0, 0.5))
	draw_circle(ic, r, c0.darkened(0.35))
	draw_arc(ic, r, 0, TAU, 32, c1.lerp(Color(1, 1, 1), 0.2), 2.0, true)
	_icone(k, ic, 11.0)
	# a barra (cápsula)
	var bx := o + Vector2(38, ROW * 0.5 - 11)
	var bw := W - 12 - 38 - 56
	var bh := 18.0
	# o trilho: a mesma cor, bem escura (o que falta)
	_capsula(Rect2(bx, Vector2(bw, bh)), c0.darkened(0.72).lerp(Color(0, 0, 0), 0.15))
	var f := clampf(v / 100.0, 0.0, 1.0)
	# o rastro do que acabou de baixar (claro, vai sumindo)
	var fr := clampf(rastro / 100.0, 0.0, 1.0)
	if fr > f + 0.002:
		var rr := Rect2(bx + Vector2(2, 2), Vector2(maxf((bw - 4) * fr, bh - 4), bh - 4))
		_capsula(rr, c1.lerp(Color(1, 1, 1), 0.55))
	if f > 0.003:
		var fill := Rect2(bx + Vector2(2, 2), Vector2(maxf((bw - 4) * f, bh - 4), bh - 4))
		_capsula_degrade(fill, c0, c1)
		# o brilho em cima
		var hl := Rect2(fill.position + Vector2(4, 2), Vector2(maxf(fill.size.x - 8, 0), 3))
		if hl.size.x > 2:
			draw_rect(hl, Color(1, 1, 1, 0.28))
	# a borda (pisca vermelha baixa)
	var bc := Color(1, 1, 1, 0.25) if not baixo else Color(1.0, 0.25, 0.2, 0.4 + 0.6 * pulse)
	_capsula_borda(Rect2(bx, Vector2(bw, bh)), bc)
	# o número
	var font := ThemeDB.fallback_font
	var txt := "%d%%" % roundi(v)
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var tp := Vector2(W - 12 - 52 + (52 - tw) * 0.5, o.y + ROW * 0.5 + 5)
	draw_string(font, tp + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0, 0, 0, 0.7))
	draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(1, 0.96, 0.88) if not baixo else Color(1, 0.55, 0.5))


func _capsula(r: Rect2, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(r.size.y * 0.5))
	draw_style_box(sb, r)


func _capsula_borda(r: Rect2, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.draw_center = false
	sb.border_color = col
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(r.size.y * 0.5))
	draw_style_box(sb, r)


## Cápsula com o degradê da esquerda (escuro) para a direita (claro): a cápsula na cor
## do meio e, por cima, o degradê no miolo (sem as pontas redondas).
func _capsula_degrade(r: Rect2, c0: Color, c1: Color) -> void:
	var rad := r.size.y * 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = c0.lerp(c1, 0.5)
	sb.set_corner_radius_all(int(rad))
	sb.corner_detail = 6
	draw_style_box(sb, r)
	# as pontas com a cor de cada lado
	draw_circle(r.position + Vector2(rad, rad), rad, c0)
	draw_circle(Vector2(r.end.x - rad, r.position.y + rad), rad, c0.lerp(c1, clampf((r.size.x - rad) / maxf(r.size.x, 1.0), 0.0, 1.0)))
	var x0 := r.position.x + rad
	var x1 := r.end.x - rad
	if x1 > x0:
		var u1 := (x1 - r.position.x) / maxf(r.size.x, 1.0)
		draw_polygon(PackedVector2Array([Vector2(x0, r.position.y), Vector2(x1, r.position.y), Vector2(x1, r.end.y), Vector2(x0, r.end.y)]),
			PackedColorArray([c0, c0.lerp(c1, u1), c0.lerp(c1, u1), c0]))


## Os ícones: coração, fruta (com folhinha) e gota.
func _icone(k: String, c: Vector2, s: float) -> void:
	var branco := Color(1, 0.97, 0.92)
	match k:
		"vida":
			var pts := PackedVector2Array()
			for i in 33:
				var a := TAU * i / 32.0
				var x := 16.0 * pow(sin(a), 3)
				var y := -(13.0 * cos(a) - 5.0 * cos(2 * a) - 2.0 * cos(3 * a) - cos(4 * a))
				pts.append(c + Vector2(x, y) * s / 17.0)
			draw_colored_polygon(pts, branco)
		"fome":
			draw_circle(c + Vector2(0, 2), s * 0.72, branco)
			draw_line(c + Vector2(0, -s * 0.5), c + Vector2(1.5, -s * 0.95), Color(0.35, 0.22, 0.1), 2.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(1.5, -s * 0.8), c + Vector2(s * 0.7, -s * 1.05), c + Vector2(s * 0.45, -s * 0.6)]), Color(0.55, 0.85, 0.35))
		"sede":
			var g := PackedVector2Array()
			for i in 17:
				var a := PI * i / 16.0
				g.append(c + Vector2(cos(a) * s * 0.62, sin(a) * s * 0.62 + s * 0.25))
			g.append(c + Vector2(0, -s * 0.95))
			draw_colored_polygon(g, branco)
