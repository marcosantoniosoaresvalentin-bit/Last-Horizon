extends Control
## Tela de carregamento. Primeiro procura e baixa atualizações do jogo
## (mostrando "MB / MB"), depois carrega a próxima cena em segundo plano
## enquanto mostra o progresso e dicas de sobrevivência.

const Updater := preload("res://scripts/updater.gd")
const Conta := preload("res://scripts/conta.gd")

## Cena que abre quando o carregamento termina.
@export_file("*.tscn") var next_scene_path := "res://scenes/main_menu.tscn"
## Tempo mínimo na tela, para a animação não piscar quando carrega rápido.
@export var min_duration := 3.0
## Segundos que cada dica fica na tela.
@export var tip_interval := 4.0
## Segundos que a mensagem do atualizador fica visível antes de carregar.
@export var update_message_time := 1.2

const TIPS := [
	"As Sombras temem o fogo. Mantenha a fogueira acesa.",
	"Junte madeira e pedra enquanto ainda há luz.",
	"Com a fome zerada, sua vida começa a cair.",
	"Juntos vocês duram mais. Não se afaste do grupo.",
	"Muros seguram as Sombras, mas não para sempre.",
	"Cada noite traz mais Sombras que a anterior.",
]

const STAGES := [
	[0.0, "Preparando o mundo"],
	[0.3, "Plantando as florestas"],
	[0.6, "Acendendo as fogueiras"],
	[0.85, "Despertando as Sombras"],
	[1.0, "Pronto"],
]

enum Phase { UPDATING, LOADING, DONE }

@onready var _progress: ProgressBar = %ProgressBar
@onready var _status: Label = %StatusLabel
@onready var _percent: Label = %PercentLabel
@onready var _tip: Label = %TipLabel
@onready var _version: Label = %VersionLabel

var _phase := Phase.UPDATING
var _elapsed := 0.0
var _shown := 0.0
var _tip_index := 0
var _tip_timer := 0.0
var _failed := false
var _updater: Node


func _ready() -> void:
	# Primeiro procura atualização nova; só depois carrega a versão baixada.
	# Assim, mesmo que uma versão baixada esteja com problema, a correção chega.
	Updater.check_last_boot()
	_set_version_label(Updater.base_build())

	_tip.visible = false          # sem dicas: o jogador aprende sozinho
	_progress.value = 0.0
	_percent.text = ""

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)

	_updater = Updater.new()
	add_child(_updater)
	_updater.status_changed.connect(func(t: String): _status.text = t)
	_updater.progress_changed.connect(_on_update_progress)
	_updater.finished.connect(_on_update_finished)
	_updater.start()


func _set_version_label(build: int) -> void:
	var v := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	_version.text = "v%s (build %d)" % [v, build]


func _on_update_progress(done: int, total: int) -> void:
	if total > 0:
		_progress.value = float(done) / float(total) * 100.0
		_percent.text = "%s / %s" % [_mb(done), _mb(total)]
	else:
		_percent.text = _mb(done)


static func _mb(bytes: int) -> String:
	return ("%.1f MB" % (bytes / 1048576.0)).replace(".", ",")


func _on_update_finished(updated: bool, message: String) -> void:
	_status.text = message
	var build := Updater.apply_installed()
	_set_version_label(build)
	await get_tree().create_timer(update_message_time if updated else 0.4).timeout
	_start_loading()


func _start_loading() -> void:
	_phase = Phase.LOADING
	_elapsed = 0.0
	_shown = 0.0
	_progress.value = 0.0
	_percent.text = "0%"
	_status.text = _stage_text(0.0)
	var err := ResourceLoader.load_threaded_request(next_scene_path)
	if err != OK:
		_fail("Não foi possível iniciar o carregamento (%s)." % error_string(err))


func _process(delta: float) -> void:
	_rotate_tips(delta)
	if _phase != Phase.LOADING or _failed:
		return
	_elapsed += delta

	var progress := []
	var status := ResourceLoader.load_threaded_get_status(next_scene_path, progress)
	var real := 0.0
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			real = 1.0
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			real = float(progress[0]) if progress.size() > 0 else 0.0
		_:
			_fail("Falha ao carregar o jogo. Feche e abra de novo.")
			return

	# A barra nunca passa do progresso real nem do tempo mínimo.
	var target := minf(real, _elapsed / min_duration)
	_shown = move_toward(_shown, target, delta * 0.9)
	_progress.value = _shown * 100.0
	_percent.text = "%d%%" % roundi(_shown * 100.0)
	_status.text = _stage_text(_shown)

	if _shown >= 1.0 and status == ResourceLoader.THREAD_LOAD_LOADED:
		_finish()


func _stage_text(p: float) -> String:
	var text: String = STAGES[0][1]
	for s in STAGES:
		if p >= s[0]:
			text = s[1]
	return text if p >= 1.0 else text + "…"


func _rotate_tips(delta: float) -> void:
	return
	_tip_timer += delta
	if _tip_timer < tip_interval:
		return
	_tip_timer = 0.0
	_tip_index = (_tip_index + 1) % TIPS.size()
	var tw := create_tween()
	tw.tween_property(_tip, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): _tip.text = TIPS[_tip_index])
	tw.tween_property(_tip, "modulate:a", 1.0, 0.3)


func _finish() -> void:
	_phase = Phase.DONE
	var scene := ResourceLoader.load_threaded_get(next_scene_path) as PackedScene
	# primeira vez (ou depois de sair da conta): criar conta ou entrar antes do menu
	if Conta.needs_login():
		scene = load("res://scenes/conta.tscn")
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	await tw.finished
	get_tree().change_scene_to_packed(scene)


func _fail(message: String) -> void:
	_failed = true
	_status.text = message
	_status.add_theme_color_override("font_color", Color("ff6b5b"))
	push_error(message)
