is_simple_direct_prompt() {
  prompt_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_trimmed=$(trim "$prompt_lower")
  [ -n "$prompt_trimmed" ] || return 1

  case "$prompt_trimmed" in
    *$'\n'*|*';'*|*'&&'*|*'||'*)
      return 1
      ;;
  esac

  case "$prompt_trimmed" in
    *"file"*|*"folder"*|*"workspace"*|*"repo"*|*"git "*|*"commit"*|*"branch"*|*"diff"*|*"patch"*|*"refactor"*|*"function"*|*"class"*|*"script"*|*"shell"*|*"posix"*|*"bug"*|*"error"*|*"trace"*|*"stack"*|*"test"*|*"build"*|*"deploy"*|*"ssh"*|*"terminal"*|*"api"*|*"http"*|*"json"*|*"yaml"*|*"sql"*|*"regex"*|*"code"*)
      return 1
      ;;
  esac

  word_count=$(printf '%s\n' "$prompt_trimmed" | awk '{print NF}')
  case "$word_count" in
    ""|*[!0-9]*)
      word_count=0
      ;;
  esac
  if [ "$word_count" -gt 24 ]; then
    return 1
  fi

  return 0
}

requires_agent_execution_prompt() {
  if prompt_prefers_compact_reasoning_contract "$1"; then
    return 1
  fi
  if prompt_prefers_reasoning_completion "$1" && ! prompt_requires_code_implementation "$1"; then
    return 1
  fi

  prompt_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_trimmed=$(trim "$prompt_lower")
  [ -n "$prompt_trimmed" ] || return 1

  case "$prompt_trimmed" in
    *"create "*|*"make "*|*"write "*|*"edit "*|*"update "*|*"modify "*|*"refactor "*|*"delete "*|*"rename "*|*"move "*|*"add "*|*"remove "*|*"fix "*|*"implement "*|*"compile "*|*"build "*|*"run "*|*"execute "*|*"test "*|*"deploy "*|*"install "*|*"chmod "*|*"script"*|*"file"*|*"workspace"*|*"repo"*|*"git "*|*"branch"*|*"commit"*|*"patch"*|*"diff"*)
      return 0
      ;;
  esac

  return 1
}

chat_prompt_needs_deep_reasoning() {
  prompt_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_trimmed=$(trim "$prompt_lower")
  [ -n "$prompt_trimmed" ] || return 1

  if printf '%s' "$prompt_trimmed" | grep -Eq 'higher[- ]?order|meta[- ]?cogn|metacogn|epistem|ontology|theorize|theorise|axiom|first principles|identity|self|values|meaning|purpose|worldview|core belief|beliefs'; then
    return 0
  fi
  if printf '%s' "$prompt_trimmed" | grep -Eq 'what would be prior to|what is prior to|prior to .* app|more prior|more fundamental|center of who i am|centre of who i am'; then
    return 0
  fi
  if printf '%s' "$prompt_trimmed" | grep -Eq '^(no|not exactly|not quite|that.s not|i mean|rather)\b|^no,|^no\.'; then
    return 0
  fi

  return 1
}

is_hello_world_script_task() {
  prompt_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  prompt_trimmed=$(trim "$prompt_lower")
  [ -n "$prompt_trimmed" ] || return 1

  case "$prompt_trimmed" in
    *hello.sh*hello*world*|*"hello, world"*|*"hello world"*)
      return 0
      ;;
  esac

  return 1
}

godot_gravity_template_patch() {
  requested_planets_raw=${1:-80}
  case "$requested_planets_raw" in
    *[!0-9]*|'')
      requested_planets=80
      ;;
    *)
      requested_planets=$requested_planets_raw
      ;;
  esac
  if [ "$requested_planets" -lt 5 ]; then
    requested_planets=5
  fi
  if [ "$requested_planets" -gt 240 ]; then
    requested_planets=240
  fi

  tmp_dir=$(mktemp -d)
  patch_text=""

  cat > "$tmp_dir/project.godot" <<'EOF'
; Engine configuration file.
; It's best edited using the editor and not directly.
config_version=5

[application]
config/name="Orbital Gravity Sim"
run/main_scene="res://Main.tscn"

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
EOF

  cat > "$tmp_dir/Main.tscn" <<'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://Main.gd" id="1"]

[node name="Main" type="Node2D"]
script = ExtResource("1")
EOF

  cat > "$tmp_dir/Main.gd" <<'EOF'
extends Node2D

const DEFAULT_G := 1200.0
const DEFAULT_TIME_SCALE := 1.0
const DEFAULT_TRAIL_LEN := 180
const DEFAULT_SOFTENING := 20.0
const DEFAULT_BARNES_HUT_THETA := 0.6
const START_PLANETS := __START_PLANETS__
const DELETE_PICK_RADIUS := 24.0
const ADAPTIVE_STEP_MIN := 0.002
const ADAPTIVE_STEP_MAX := 0.033
const STEP_ONCE_DELTA := 1.0 / 60.0
const VELOCITY_VECTOR_SCALE := 0.08
const DRAG_SPAWN_MIN_DISTANCE := 6.0
const DRAG_VELOCITY_SCALE := 1.35
const SAVE_PATH := "user://gravity_preset.json"
const TELEMETRY_PATH := "user://gravity_telemetry.csv"
const REPLAY_PATH := "user://gravity_replay_events.json"
const REGRESSION_REPORT_PATH := "user://regression_report.json"
const BENCHMARK_PATH := "user://benchmark_results.csv"
const BENCHMARK_SECONDS := 8.0
const BENCHMARK_STEP := 1.0 / 120.0
const CHALLENGE_DURATION := 120.0
const CHALLENGE_TARGET_SCORE := 800.0
const CHALLENGE_MIN_STABLE_ORBITERS := 6
const SCORE_SAMPLE_INTERVAL := 0.5
const SHOCKWAVE_RADIUS := 260.0
const SHOCKWAVE_FORCE := 220.0
const SHOCKWAVE_COOLDOWN := 3.0
const SHOCKWAVE_VISUAL_DURATION := 0.42
const BACKGROUND_STAR_COUNT := 160

enum IntegratorMode {
    EULER,
    LEAPFROG,
    RK4
}

enum ForceMode {
    DIRECT,
    BARNES_HUT
}

enum GameplayMode {
    SANDBOX,
    CHALLENGE
}

class Planet:
    var pos: Vector2
    var vel: Vector2
    var mass: float
    var radius: float
    var color: Color
    var trail: PackedVector2Array = PackedVector2Array()

    func _init(p: Vector2, v: Vector2, m: float, r: float, c: Color) -> void:
        pos = p
        vel = v
        mass = m
        radius = r
        color = c
        trail.push_back(pos)

class BHNode:
    var center: Vector2
    var half_size: float
    var mass: float = 0.0
    var com: Vector2 = Vector2.ZERO
    var body_index: int = -1
    var children: Array = []

    func _init(c: Vector2, h: float) -> void:
        center = c
        half_size = h
        children = []

var planets: Array[Planet] = []
var initial_state: Array[Dictionary] = []
var initial_total_energy: float = 0.0
var telemetry_time: float = 0.0
var telemetry_rows: Array[String] = []
var record_events_enabled: bool = false
var replay_active: bool = false
var replay_events: Array[Dictionary] = []
var replay_cursor: int = 0
var replay_elapsed: float = 0.0
var replay_checksum_state: String = "n/a"
var replay_expected_final_state_checksum: String = ""
var last_self_test_summary: String = "not run"
var gameplay_mode: int = GameplayMode.SANDBOX
var challenge_active: bool = false
var challenge_time_left: float = CHALLENGE_DURATION
var challenge_score: float = 0.0
var challenge_combo: float = 1.0
var challenge_goal_score: float = CHALLENGE_TARGET_SCORE
var score_sample_elapsed: float = 0.0
var challenge_status_text: String = "Sandbox mode"
var challenge_message: String = ""
var challenge_message_time: float = 0.0
var shockwave_cooldown_left: float = 0.0
var visual_time: float = 0.0
var shockwave_visual_active: bool = false
var shockwave_visual_time: float = 0.0
var shockwave_visual_origin: Vector2 = Vector2.ZERO
var background_stars: Array[Dictionary] = []

var gravity_constant: float = DEFAULT_G
var time_scale_factor: float = DEFAULT_TIME_SCALE
var softening: float = DEFAULT_SOFTENING
var barnes_hut_theta: float = DEFAULT_BARNES_HUT_THETA
var trail_limit: int = DEFAULT_TRAIL_LEN
var trails_enabled: bool = true
var simulation_paused: bool = false
var adaptive_timestep_enabled: bool = false
var merge_enabled: bool = true
var show_velocity_vectors: bool = false
var integrator_mode: int = IntegratorMode.LEAPFROG
var force_mode: int = ForceMode.DIRECT
var seed_value: int = 1337
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var cam: Camera2D
var panning_camera: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO
var drag_spawn_active: bool = false
var drag_start_world: Vector2 = Vector2.ZERO
var drag_current_world: Vector2 = Vector2.ZERO

var pause_button: Button
var trail_button: Button
var adaptive_button: Button
var merge_button: Button
var vectors_button: Button
var record_button: Button
var replay_button: Button
var force_mode_button: Button
var self_test_button: Button
var gameplay_mode_button: Button
var shockwave_button: Button
var gravity_slider: HSlider
var time_slider: HSlider
var softening_slider: HSlider
var theta_slider: HSlider
var trail_slider: HSlider
var integrator_option: OptionButton
var hud_label: Label
var challenge_label: Label
var seed_input: LineEdit

func _ready() -> void:
    _apply_seed(seed_value)
    _setup_camera()
    _build_background_stars(BACKGROUND_STAR_COUNT)
    _setup_ui()
    _set_gameplay_mode(GameplayMode.SANDBOX, false)
    _seed_default_system(START_PLANETS)
    _capture_initial_state()
    set_process(true)
    set_process_input(true)

func _setup_camera() -> void:
    cam = Camera2D.new()
    cam.position = Vector2(640, 360)
    cam.zoom = Vector2.ONE
    add_child(cam)
    cam.make_current()

func _setup_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)

    var panel := PanelContainer.new()
    panel.position = Vector2(12, 12)
    panel.custom_minimum_size = Vector2(700, 520)
    layer.add_child(panel)

    var box := VBoxContainer.new()
    panel.add_child(box)

    var button_row := HBoxContainer.new()
    box.add_child(button_row)

    pause_button = Button.new()
    pause_button.text = "Pause"
    pause_button.pressed.connect(_toggle_pause)
    button_row.add_child(pause_button)

    var reset_button := Button.new()
    reset_button.text = "Reset"
    reset_button.pressed.connect(_reset_system)
    button_row.add_child(reset_button)

    var step_once_button := Button.new()
    step_once_button.text = "Step Once"
    step_once_button.pressed.connect(_step_once)
    button_row.add_child(step_once_button)

    var action_row := HBoxContainer.new()
    box.add_child(action_row)

    trail_button = Button.new()
    trail_button.text = "Trails: On"
    trail_button.pressed.connect(_toggle_trails)
    action_row.add_child(trail_button)

    var clear_trails_button := Button.new()
    clear_trails_button.text = "Clear Trails"
    clear_trails_button.pressed.connect(_clear_trails)
    action_row.add_child(clear_trails_button)

    adaptive_button = Button.new()
    adaptive_button.text = "Adaptive Step: Off"
    adaptive_button.pressed.connect(_toggle_adaptive_step)
    action_row.add_child(adaptive_button)

    merge_button = Button.new()
    merge_button.text = "Merge: On"
    merge_button.pressed.connect(_toggle_merge)
    action_row.add_child(merge_button)

    vectors_button = Button.new()
    vectors_button.text = "Vectors: Off"
    vectors_button.pressed.connect(_toggle_vectors)
    action_row.add_child(vectors_button)

    var save_button := Button.new()
    save_button.text = "Save Preset"
    save_button.pressed.connect(_save_preset)
    action_row.add_child(save_button)

    var load_button := Button.new()
    load_button.text = "Load Preset"
    load_button.pressed.connect(_load_preset)
    action_row.add_child(load_button)

    var export_csv_button := Button.new()
    export_csv_button.text = "Export CSV"
    export_csv_button.pressed.connect(_export_telemetry_csv)
    action_row.add_child(export_csv_button)

    record_button = Button.new()
    record_button.text = "Record: Off"
    record_button.pressed.connect(_toggle_recording)
    action_row.add_child(record_button)

    replay_button = Button.new()
    replay_button.text = "Replay"
    replay_button.pressed.connect(_start_replay_from_file)
    action_row.add_child(replay_button)

    var benchmark_button := Button.new()
    benchmark_button.text = "Benchmark Integrators"
    benchmark_button.pressed.connect(_run_integrator_benchmark_export)
    action_row.add_child(benchmark_button)

    force_mode_button = Button.new()
    force_mode_button.text = "Force: Direct"
    force_mode_button.pressed.connect(_toggle_force_mode)
    action_row.add_child(force_mode_button)

    self_test_button = Button.new()
    self_test_button.text = "Run Self-Tests"
    self_test_button.pressed.connect(_run_self_tests_export_report)
    action_row.add_child(self_test_button)

    var gameplay_row := HBoxContainer.new()
    box.add_child(gameplay_row)

    gameplay_mode_button = Button.new()
    gameplay_mode_button.text = "Mode: Sandbox"
    gameplay_mode_button.pressed.connect(_toggle_gameplay_mode)
    gameplay_row.add_child(gameplay_mode_button)

    shockwave_button = Button.new()
    shockwave_button.text = "Shockwave"
    shockwave_button.pressed.connect(_on_shockwave_pressed)
    gameplay_row.add_child(shockwave_button)

    var gravity_title := Label.new()
    gravity_title.text = "Gravitational Constant"
    box.add_child(gravity_title)

    gravity_slider = HSlider.new()
    gravity_slider.min_value = 200.0
    gravity_slider.max_value = 5000.0
    gravity_slider.step = 10.0
    gravity_slider.value = gravity_constant
    gravity_slider.value_changed.connect(_on_gravity_slider_changed)
    box.add_child(gravity_slider)

    var softening_title := Label.new()
    softening_title.text = "Softening"
    box.add_child(softening_title)

    softening_slider = HSlider.new()
    softening_slider.min_value = 2.0
    softening_slider.max_value = 80.0
    softening_slider.step = 0.5
    softening_slider.value = softening
    softening_slider.value_changed.connect(_on_softening_slider_changed)
    box.add_child(softening_slider)

    var theta_title := Label.new()
    theta_title.text = "Barnes-Hut Theta"
    box.add_child(theta_title)

    theta_slider = HSlider.new()
    theta_slider.min_value = 0.25
    theta_slider.max_value = 1.2
    theta_slider.step = 0.01
    theta_slider.value = barnes_hut_theta
    theta_slider.value_changed.connect(_on_theta_slider_changed)
    box.add_child(theta_slider)

    var time_title := Label.new()
    time_title.text = "Time Scale"
    box.add_child(time_title)

    time_slider = HSlider.new()
    time_slider.min_value = 0.1
    time_slider.max_value = 3.0
    time_slider.step = 0.05
    time_slider.value = time_scale_factor
    time_slider.value_changed.connect(_on_time_slider_changed)
    box.add_child(time_slider)

    var trail_title := Label.new()
    trail_title.text = "Trail Length"
    box.add_child(trail_title)

    trail_slider = HSlider.new()
    trail_slider.min_value = 20.0
    trail_slider.max_value = 800.0
    trail_slider.step = 5.0
    trail_slider.value = float(trail_limit)
    trail_slider.value_changed.connect(_on_trail_slider_changed)
    box.add_child(trail_slider)

    var integrator_row := HBoxContainer.new()
    box.add_child(integrator_row)

    var integrator_label := Label.new()
    integrator_label.text = "Integrator"
    integrator_row.add_child(integrator_label)

    integrator_option = OptionButton.new()
    integrator_option.add_item("Leapfrog")
    integrator_option.add_item("Euler")
    integrator_option.add_item("RK4")
    integrator_option.item_selected.connect(_on_integrator_selected)
    integrator_row.add_child(integrator_option)
    _set_integrator_mode(integrator_mode)
    _set_force_mode(force_mode)

    var seed_row := HBoxContainer.new()
    box.add_child(seed_row)

    var seed_label := Label.new()
    seed_label.text = "Seed"
    seed_row.add_child(seed_label)

    seed_input = LineEdit.new()
    seed_input.custom_minimum_size = Vector2(130, 0)
    seed_input.text = str(seed_value)
    seed_row.add_child(seed_input)

    var seed_apply_button := Button.new()
    seed_apply_button.text = "Apply Seed"
    seed_apply_button.pressed.connect(_apply_seed_from_ui)
    seed_row.add_child(seed_apply_button)

    hud_label = Label.new()
    hud_label.position = Vector2(12, 456)
    hud_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    hud_label.custom_minimum_size = Vector2(1120, 44)
    layer.add_child(hud_label)

    challenge_label = Label.new()
    challenge_label.position = Vector2(12, 500)
    challenge_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    challenge_label.custom_minimum_size = Vector2(1120, 72)
    layer.add_child(challenge_label)

func _seed_default_system(body_count: int) -> void:
    planets.clear()

    var center := Vector2(640, 360)
    var star_mass := 9200.0
    planets.append(Planet.new(center, Vector2.ZERO, star_mass, 21.0, Color(1.0, 0.85, 0.3)))

    var orbiters := maxi(1, body_count - 1)
    for i in range(orbiters):
        var angle := TAU * float(i) / float(orbiters)
        var orbit_radius := 120.0 + 15.0 * float(i)
        var pos := center + Vector2(cos(angle), sin(angle)) * orbit_radius
        var tangent := Vector2(-sin(angle), cos(angle))
        var speed := sqrt((gravity_constant * star_mass) / orbit_radius)
        var vel := tangent * speed
        var mass := 28.0 + 12.0 * float(i)
        var radius := 4.5 + sqrt(mass) * 0.45
        var color := Color.from_hsv(float(i) / float(orbiters), 0.68, 0.95)
        planets.append(Planet.new(pos, vel, mass, radius, color))

func _build_background_stars(count: int) -> void:
    background_stars.clear()
    var star_rng := RandomNumberGenerator.new()
    star_rng.seed = int(seed_value) + 5012347
    var clamped_count := maxi(0, count)
    for i in range(clamped_count):
        background_stars.append({
            "pos": Vector2(star_rng.randf_range(-4200.0, 4200.0), star_rng.randf_range(-3200.0, 3200.0)),
            "r": star_rng.randf_range(0.8, 2.2),
            "a": star_rng.randf_range(0.15, 0.65),
            "phase": star_rng.randf_range(0.0, TAU),
            "speed": star_rng.randf_range(0.25, 1.2)
        })

func _toggle_gameplay_mode() -> void:
    if gameplay_mode == GameplayMode.SANDBOX:
        _set_gameplay_mode(GameplayMode.CHALLENGE, true)
    else:
        _set_gameplay_mode(GameplayMode.SANDBOX, true)

func _reset_challenge_session() -> void:
    challenge_active = gameplay_mode == GameplayMode.CHALLENGE
    challenge_time_left = CHALLENGE_DURATION
    challenge_score = 0.0
    challenge_combo = 1.0
    score_sample_elapsed = 0.0
    challenge_status_text = "Build stable orbits around your largest body"
    challenge_message = ""
    challenge_message_time = 0.0

func _set_challenge_message(text: String, duration: float = 2.0) -> void:
    challenge_message = text
    challenge_message_time = maxf(0.0, duration)

func _set_gameplay_mode(mode_value: int, record_event: bool = true) -> void:
    if mode_value != GameplayMode.SANDBOX && mode_value != GameplayMode.CHALLENGE:
        mode_value = GameplayMode.SANDBOX
    gameplay_mode = mode_value
    if gameplay_mode == GameplayMode.CHALLENGE:
        _reset_challenge_session()
        _set_challenge_message("Challenge started: reach %.0f points by sustaining stable orbits." % challenge_goal_score, 3.2)
    else:
        challenge_active = false
        challenge_time_left = CHALLENGE_DURATION
        challenge_score = 0.0
        challenge_combo = 1.0
        score_sample_elapsed = 0.0
        challenge_status_text = "Sandbox mode"
        challenge_message = ""
        challenge_message_time = 0.0
    _refresh_gameplay_ui()
    if record_event:
        _append_replay_event("set_gameplay_mode", {"mode": gameplay_mode})

func _on_shockwave_pressed() -> void:
    var origin := cam.position
    if !planets.is_empty():
        origin = _center_of_mass()
    if !_trigger_shockwave(origin, true) && shockwave_cooldown_left > 0.0:
        _set_challenge_message("Shockwave recharging: %.1fs" % shockwave_cooldown_left, 1.0)
    _refresh_gameplay_ui()

func _trigger_shockwave(origin: Vector2, record_event: bool = true) -> bool:
    if shockwave_cooldown_left > 0.001:
        return false

    var affected := 0
    for p in planets:
        var offset := p.pos - origin
        var dist := offset.length()
        if dist > SHOCKWAVE_RADIUS:
            continue
        var dir := Vector2.RIGHT
        if dist > 0.001:
            dir = offset / dist
        else:
            var angle := rng.randf_range(0.0, TAU)
            dir = Vector2(cos(angle), sin(angle))
        var falloff := 1.0 - clampf(dist / SHOCKWAVE_RADIUS, 0.0, 1.0)
        var impulse_strength := SHOCKWAVE_FORCE * falloff / maxf(p.mass, 12.0)
        p.vel += dir * impulse_strength
        affected += 1

    if affected <= 0:
        return false

    shockwave_cooldown_left = SHOCKWAVE_COOLDOWN
    shockwave_visual_active = true
    shockwave_visual_time = 0.0
    shockwave_visual_origin = origin
    _set_challenge_message("Shockwave fired (%d affected)." % affected, 1.4)
    if record_event:
        _append_replay_event("shockwave", {
            "ox": origin.x,
            "oy": origin.y
        })
    return true

func _largest_body() -> Planet:
    if planets.is_empty():
        return null
    var anchor := planets[0]
    for p in planets:
        if p.mass > anchor.mass:
            anchor = p
    return anchor

func _count_stable_orbiters() -> int:
    if planets.size() < 2:
        return 0

    var anchor := _largest_body()
    if anchor == null:
        return 0

    var stable := 0
    for p in planets:
        if p == anchor:
            continue
        var offset := p.pos - anchor.pos
        var radius := offset.length()
        if radius < 60.0:
            continue

        var radial_dir := offset / maxf(radius, 0.001)
        var tangent := Vector2(-radial_dir.y, radial_dir.x)
        var speed := p.vel.length()
        var expected_speed := sqrt((gravity_constant * anchor.mass) / maxf(radius, 30.0))
        if expected_speed <= 0.0001:
            continue
        var speed_ratio := speed / expected_speed
        var velocity_dir := p.vel / maxf(speed, 0.001)
        var tangential_alignment := absf(velocity_dir.dot(tangent))
        var radial_ratio := absf(p.vel.dot(radial_dir)) / expected_speed
        if speed_ratio >= 0.55 && speed_ratio <= 1.6 && tangential_alignment >= 0.55 && radial_ratio <= 0.6:
            stable += 1

    return stable

func _sample_challenge_score() -> void:
    if gameplay_mode != GameplayMode.CHALLENGE || !challenge_active:
        return

    var stable := _count_stable_orbiters()
    if stable >= CHALLENGE_MIN_STABLE_ORBITERS:
        challenge_combo = clampf(challenge_combo + 0.12 + float(stable) * 0.02, 1.0, 6.0)
        var gain := (float(stable) * 8.0) * challenge_combo
        challenge_score += gain
        challenge_status_text = "Stable orbit chain: %d (combo x%.2f)." % [stable, challenge_combo]
    else:
        challenge_combo = maxf(1.0, challenge_combo - 0.28)
        if stable <= 1:
            challenge_status_text = "Orbit collapse: add bodies with tangential velocity."
        else:
            challenge_status_text = "Need %d stable orbiters (%d now)." % [CHALLENGE_MIN_STABLE_ORBITERS, stable]

func _update_gameplay_state(delta_sim: float, delta_real: float) -> void:
    visual_time += delta_real
    if shockwave_cooldown_left > 0.0:
        shockwave_cooldown_left = maxf(0.0, shockwave_cooldown_left - delta_real)
    if shockwave_visual_active:
        shockwave_visual_time += delta_real
        if shockwave_visual_time >= SHOCKWAVE_VISUAL_DURATION:
            shockwave_visual_active = false
    if challenge_message_time > 0.0:
        challenge_message_time = maxf(0.0, challenge_message_time - delta_real)
        if challenge_message_time <= 0.0:
            challenge_message = ""

    if gameplay_mode != GameplayMode.CHALLENGE || !challenge_active:
        return
    if delta_sim <= 0.0:
        return

    challenge_time_left = maxf(0.0, challenge_time_left - delta_sim)
    score_sample_elapsed += delta_sim
    while score_sample_elapsed >= SCORE_SAMPLE_INTERVAL:
        score_sample_elapsed -= SCORE_SAMPLE_INTERVAL
        _sample_challenge_score()

    if challenge_score >= challenge_goal_score:
        challenge_active = false
        challenge_status_text = "Challenge complete."
        _set_challenge_message("Great orbit engineering. Final score %.1f." % challenge_score, 3.8)
    elif challenge_time_left <= 0.001:
        challenge_active = false
        challenge_status_text = "Challenge failed."
        _set_challenge_message("Time up: %.1f / %.1f points. Tune velocities and retry." % [challenge_score, challenge_goal_score], 3.8)

func _refresh_gameplay_ui() -> void:
    if gameplay_mode_button != null:
        gameplay_mode_button.text = "Mode: Challenge" if gameplay_mode == GameplayMode.CHALLENGE else "Mode: Sandbox"
    if shockwave_button != null:
        if shockwave_cooldown_left > 0.0:
            shockwave_button.text = "Shockwave: %.1fs" % shockwave_cooldown_left
        else:
            shockwave_button.text = "Shockwave"
    if challenge_label != null:
        if gameplay_mode == GameplayMode.SANDBOX:
            challenge_label.text = "Sandbox: left-click or drag to spawn, right-click to delete, middle-drag to pan, wheel to zoom, space for shockwave."
        else:
            var state_text := "active" if challenge_active else "complete"
            challenge_label.text = "Challenge (%s) score %.1f / %.1f | combo x%.2f | time %.1fs | %s" % [
                state_text, challenge_score, challenge_goal_score, challenge_combo, challenge_time_left, challenge_status_text
            ]
            if !challenge_message.is_empty():
                challenge_label.text += "\n" + challenge_message

func _capture_initial_state() -> void:
    initial_state.clear()
    for p in planets:
        initial_state.append(_planet_to_dict(p))
    initial_total_energy = _total_system_energy()
    _reset_telemetry()

func _reset_system() -> void:
    planets.clear()
    for entry in initial_state:
        planets.append(_planet_from_dict(entry))
    if planets.is_empty():
        _seed_default_system(START_PLANETS)
        _capture_initial_state()
    simulation_paused = false
    pause_button.text = "Pause"
    drag_spawn_active = false
    shockwave_cooldown_left = 0.0
    shockwave_visual_active = false
    if gameplay_mode == GameplayMode.CHALLENGE:
        _reset_challenge_session()
        _set_challenge_message("Challenge reset.", 1.4)
    _refresh_gameplay_ui()

func _toggle_pause() -> void:
    simulation_paused = !simulation_paused
    pause_button.text = "Resume" if simulation_paused else "Pause"
    _append_replay_event("toggle_pause", {})

func _toggle_trails() -> void:
    trails_enabled = !trails_enabled
    trail_button.text = "Trails: On" if trails_enabled else "Trails: Off"
    if !trails_enabled:
        _clear_trails()
    _append_replay_event("toggle_trails", {})

func _clear_trails() -> void:
    for p in planets:
        p.trail = PackedVector2Array([p.pos])

func _reset_telemetry() -> void:
    telemetry_time = 0.0
    telemetry_rows.clear()
    telemetry_rows.append("time,energy,angular_momentum,drift_percent")

func _record_telemetry_sample(energy: float, angular_momentum: float, drift_pct: float) -> void:
    telemetry_rows.append("%.6f,%.8f,%.8f,%.8f" % [telemetry_time, energy, angular_momentum, drift_pct])
    if telemetry_rows.size() > 20001:
        telemetry_rows.remove_at(1)

func _append_replay_event(kind: String, data: Dictionary) -> void:
    if replay_active || !record_events_enabled:
        return
    replay_events.append({
        "t": telemetry_time,
        "kind": kind,
        "data": data
    })

func _apply_replay_event(event: Dictionary) -> void:
    var kind := str(event.get("kind", ""))
    var data: Dictionary = event.get("data", {})
    match kind:
        "spawn":
            _spawn_planet_from_record(data)
        "delete":
            var p := Vector2(float(data.get("px", 0.0)), float(data.get("py", 0.0)))
            _delete_planet_near(p)
        "toggle_pause":
            _toggle_pause()
        "toggle_trails":
            _toggle_trails()
        "toggle_adaptive":
            _toggle_adaptive_step()
        "toggle_merge":
            _toggle_merge()
        "toggle_vectors":
            _toggle_vectors()
        "set_gameplay_mode":
            _set_gameplay_mode(int(data.get("mode", gameplay_mode)), false)
        "shockwave":
            var shock_origin := Vector2(float(data.get("ox", cam.position.x)), float(data.get("oy", cam.position.y)))
            _trigger_shockwave(shock_origin, false)
        "set_force_mode":
            _set_force_mode(int(data.get("mode", force_mode)))
        "set_theta":
            var theta_value := clampf(float(data.get("v", barnes_hut_theta)), 0.25, 1.2)
            barnes_hut_theta = theta_value
            if theta_slider != null:
                theta_slider.value = theta_value
        "set_gravity":
            var gv := float(data.get("v", gravity_constant))
            gravity_constant = gv
            if gravity_slider != null:
                gravity_slider.value = gv
        "set_softening":
            var sv := float(data.get("v", softening))
            softening = sv
            if softening_slider != null:
                softening_slider.value = sv
        "set_time_scale":
            var tv := float(data.get("v", time_scale_factor))
            time_scale_factor = tv
            if time_slider != null:
                time_slider.value = tv
        "set_integrator":
            _set_integrator_mode(int(data.get("mode", integrator_mode)))
        "step_once":
            var was_paused := simulation_paused
            if !simulation_paused:
                simulation_paused = true
            _step_once()
            simulation_paused = was_paused
        "run_benchmark":
            _run_integrator_benchmark_export(false)
        "run_self_tests":
            _run_self_tests_export_report(false)
        _:
            pass

func _save_replay_events_file() -> void:
    var final_snapshot := _snapshot_planets()
    var payload := {
        "seed_value": seed_value,
        "gravity_constant": gravity_constant,
        "time_scale_factor": time_scale_factor,
        "softening": softening,
        "trail_limit": trail_limit,
        "trails_enabled": trails_enabled,
        "adaptive_timestep_enabled": adaptive_timestep_enabled,
        "merge_enabled": merge_enabled,
        "show_velocity_vectors": show_velocity_vectors,
        "gameplay_mode": gameplay_mode,
        "integrator_mode": integrator_mode,
        "force_mode": force_mode,
        "barnes_hut_theta": barnes_hut_theta,
        "initial_state": initial_state,
        "events": replay_events,
        "final_state_checksum": _state_checksum_for_snapshot(final_snapshot)
    }
    payload["checksum"] = _replay_checksum_for_payload(payload)
    var file := FileAccess.open(REPLAY_PATH, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(payload))
        replay_checksum_state = "ok"
        replay_expected_final_state_checksum = str(payload.get("final_state_checksum", ""))

func _replay_checksum_material(data: Dictionary) -> String:
    var pieces: Array[String] = []
    pieces.append("seed=%d" % int(data.get("seed_value", seed_value)))
    pieces.append("g=%.8f" % float(data.get("gravity_constant", gravity_constant)))
    pieces.append("time=%.8f" % float(data.get("time_scale_factor", time_scale_factor)))
    pieces.append("soft=%.8f" % float(data.get("softening", softening)))
    pieces.append("trail=%d" % int(data.get("trail_limit", trail_limit)))
    pieces.append("trails=%s" % str(bool(data.get("trails_enabled", trails_enabled))))
    pieces.append("adaptive=%s" % str(bool(data.get("adaptive_timestep_enabled", adaptive_timestep_enabled))))
    pieces.append("merge=%s" % str(bool(data.get("merge_enabled", merge_enabled))))
    pieces.append("vectors=%s" % str(bool(data.get("show_velocity_vectors", show_velocity_vectors))))
    pieces.append("gameplay=%d" % int(data.get("gameplay_mode", gameplay_mode)))
    pieces.append("integrator=%d" % int(data.get("integrator_mode", integrator_mode)))
    pieces.append("force=%d" % int(data.get("force_mode", force_mode)))
    pieces.append("theta=%.6f" % float(data.get("barnes_hut_theta", barnes_hut_theta)))
    pieces.append("initial=%s" % JSON.stringify(data.get("initial_state", [])))
    pieces.append("events=%s" % JSON.stringify(data.get("events", [])))
    return "|".join(pieces)

func _replay_checksum_for_payload(data: Dictionary) -> String:
    return _replay_checksum_material(data).sha256_text()

func _state_checksum_for_snapshot(snapshot: Array[Dictionary]) -> String:
    var material := JSON.stringify(snapshot)
    return material.sha256_text()

func _load_replay_events_file() -> bool:
    if !FileAccess.file_exists(REPLAY_PATH):
        return false
    var file := FileAccess.open(REPLAY_PATH, FileAccess.READ)
    if file == null:
        return false
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return false
    var data: Dictionary = parsed
    var stored_checksum := str(data.get("checksum", ""))
    if stored_checksum.is_empty():
        replay_checksum_state = "missing"
    else:
        var expected_checksum := _replay_checksum_for_payload(data)
        if stored_checksum != expected_checksum:
            replay_checksum_state = "mismatch"
            return false
        replay_checksum_state = "ok"
    replay_expected_final_state_checksum = str(data.get("final_state_checksum", ""))

    _apply_seed(int(data.get("seed_value", seed_value)))
    gravity_constant = float(data.get("gravity_constant", gravity_constant))
    time_scale_factor = float(data.get("time_scale_factor", time_scale_factor))
    softening = float(data.get("softening", softening))
    barnes_hut_theta = clampf(float(data.get("barnes_hut_theta", barnes_hut_theta)), 0.25, 1.2)
    trail_limit = maxi(10, int(data.get("trail_limit", trail_limit)))
    trails_enabled = bool(data.get("trails_enabled", trails_enabled))
    adaptive_timestep_enabled = bool(data.get("adaptive_timestep_enabled", adaptive_timestep_enabled))
    merge_enabled = bool(data.get("merge_enabled", merge_enabled))
    show_velocity_vectors = bool(data.get("show_velocity_vectors", show_velocity_vectors))
    var loaded_gameplay_mode := int(data.get("gameplay_mode", gameplay_mode))
    _set_integrator_mode(int(data.get("integrator_mode", integrator_mode)))
    _set_force_mode(int(data.get("force_mode", force_mode)))

    if gravity_slider != null:
        gravity_slider.value = gravity_constant
    if time_slider != null:
        time_slider.value = time_scale_factor
    if softening_slider != null:
        softening_slider.value = softening
    if theta_slider != null:
        theta_slider.value = barnes_hut_theta
    if trail_slider != null:
        trail_slider.value = float(trail_limit)
    if trail_button != null:
        trail_button.text = "Trails: On" if trails_enabled else "Trails: Off"
    if adaptive_button != null:
        adaptive_button.text = "Adaptive Step: On" if adaptive_timestep_enabled else "Adaptive Step: Off"
    if merge_button != null:
        merge_button.text = "Merge: On" if merge_enabled else "Merge: Off"
    if vectors_button != null:
        vectors_button.text = "Vectors: On" if show_velocity_vectors else "Vectors: Off"
    if seed_input != null:
        seed_input.text = str(seed_value)
    _set_gameplay_mode(loaded_gameplay_mode, false)

    var loaded_initial: Array[Dictionary] = []
    var raw_initial: Variant = data.get("initial_state", [])
    if raw_initial is Array:
        for entry in raw_initial:
            if typeof(entry) == TYPE_DICTIONARY:
                loaded_initial.append(entry)
    initial_state = loaded_initial
    planets.clear()
    for entry in initial_state:
        planets.append(_planet_from_dict(entry))
    if planets.is_empty():
        _seed_default_system(START_PLANETS)
        _capture_initial_state()
    else:
        initial_total_energy = _total_system_energy()
        _reset_telemetry()

    replay_events.clear()
    var raw_events: Variant = data.get("events", [])
    if raw_events is Array:
        for event in raw_events:
            if typeof(event) == TYPE_DICTIONARY:
                replay_events.append(event)
    _refresh_gameplay_ui()
    return replay_events.size() > 0

func _toggle_recording() -> void:
    if replay_active:
        return
    record_events_enabled = !record_events_enabled
    if record_events_enabled:
        replay_events.clear()
        replay_expected_final_state_checksum = ""
        replay_checksum_state = "recording"
    else:
        _save_replay_events_file()
    if record_button != null:
        record_button.text = "Record: On" if record_events_enabled else "Record: Off"

func _start_replay_from_file() -> void:
    if record_events_enabled:
        record_events_enabled = false
        if record_button != null:
            record_button.text = "Record: Off"
    if !_load_replay_events_file():
        return
    replay_active = true
    replay_cursor = 0
    replay_elapsed = 0.0
    replay_checksum_state = "replaying"
    simulation_paused = false
    if pause_button != null:
        pause_button.text = "Pause"
    if replay_button != null:
        replay_button.text = "Replay: On"
    _set_challenge_message("Replay running.", 1.0)
    _refresh_gameplay_ui()

func _stop_replay() -> void:
    var replay_was_active := replay_active
    replay_active = false
    replay_cursor = 0
    replay_elapsed = 0.0
    if replay_was_active && !replay_expected_final_state_checksum.is_empty():
        var actual_state_checksum := _state_checksum_for_snapshot(_snapshot_planets())
        if actual_state_checksum == replay_expected_final_state_checksum:
            replay_checksum_state = "ok+final"
        else:
            replay_checksum_state = "final-mismatch"
    if replay_button != null:
        replay_button.text = "Replay"
    _refresh_gameplay_ui()

func _advance_replay(delta_sim: float) -> void:
    if !replay_active:
        return
    replay_elapsed += delta_sim
    while replay_cursor < replay_events.size():
        var event: Dictionary = replay_events[replay_cursor]
        var event_t := float(event.get("t", 0.0))
        if event_t > replay_elapsed:
            break
        _apply_replay_event(event)
        replay_cursor += 1
    if replay_cursor >= replay_events.size():
        _stop_replay()

func _toggle_adaptive_step() -> void:
    adaptive_timestep_enabled = !adaptive_timestep_enabled
    adaptive_button.text = "Adaptive Step: On" if adaptive_timestep_enabled else "Adaptive Step: Off"
    _append_replay_event("toggle_adaptive", {})

func _toggle_merge() -> void:
    merge_enabled = !merge_enabled
    merge_button.text = "Merge: On" if merge_enabled else "Merge: Off"
    _append_replay_event("toggle_merge", {})

func _toggle_vectors() -> void:
    show_velocity_vectors = !show_velocity_vectors
    vectors_button.text = "Vectors: On" if show_velocity_vectors else "Vectors: Off"
    _append_replay_event("toggle_vectors", {})

func _set_force_mode(mode_value: int) -> void:
    if mode_value != ForceMode.DIRECT && mode_value != ForceMode.BARNES_HUT:
        mode_value = ForceMode.DIRECT
    force_mode = mode_value
    if force_mode_button != null:
        force_mode_button.text = "Force: Barnes-Hut" if force_mode == ForceMode.BARNES_HUT else "Force: Direct"

func _toggle_force_mode() -> void:
    if force_mode == ForceMode.DIRECT:
        _set_force_mode(ForceMode.BARNES_HUT)
    else:
        _set_force_mode(ForceMode.DIRECT)
    _append_replay_event("set_force_mode", {"mode": force_mode})

func _set_integrator_mode(mode_value: int) -> void:
    if mode_value != IntegratorMode.EULER && mode_value != IntegratorMode.LEAPFROG && mode_value != IntegratorMode.RK4:
        mode_value = IntegratorMode.LEAPFROG
    integrator_mode = mode_value
    if integrator_option != null:
        if integrator_mode == IntegratorMode.EULER:
            integrator_option.select(1)
        elif integrator_mode == IntegratorMode.RK4:
            integrator_option.select(2)
        else:
            integrator_option.select(0)

func _apply_seed(seed: int) -> void:
    seed_value = seed
    rng.seed = seed_value
    _build_background_stars(BACKGROUND_STAR_COUNT)

func _apply_seed_from_ui() -> void:
    var text := ""
    if seed_input != null:
        text = seed_input.text.strip_edges()
    if text.is_valid_int():
        _apply_seed(int(text))
        _seed_default_system(START_PLANETS)
        _capture_initial_state()
    if seed_input != null:
        seed_input.text = str(seed_value)

func _step_once() -> void:
    if !simulation_paused:
        return
    var step_seconds := _effective_step_seconds(STEP_ONCE_DELTA)
    _simulate_step(step_seconds * time_scale_factor)
    telemetry_time += step_seconds * time_scale_factor
    _update_gameplay_state(step_seconds * time_scale_factor, step_seconds)
    _append_replay_event("step_once", {})
    _update_hud()
    queue_redraw()

func _on_gravity_slider_changed(value: float) -> void:
    gravity_constant = value
    _append_replay_event("set_gravity", {"v": gravity_constant})

func _on_softening_slider_changed(value: float) -> void:
    softening = value
    _append_replay_event("set_softening", {"v": softening})

func _on_theta_slider_changed(value: float) -> void:
    barnes_hut_theta = clampf(value, 0.25, 1.2)
    _append_replay_event("set_theta", {"v": barnes_hut_theta})

func _on_time_slider_changed(value: float) -> void:
    time_scale_factor = value
    _append_replay_event("set_time_scale", {"v": time_scale_factor})

func _on_trail_slider_changed(value: float) -> void:
    trail_limit = maxi(10, int(value))

func _on_integrator_selected(index: int) -> void:
    if index == 1:
        _set_integrator_mode(IntegratorMode.EULER)
    elif index == 2:
        _set_integrator_mode(IntegratorMode.RK4)
    else:
        _set_integrator_mode(IntegratorMode.LEAPFROG)
    _append_replay_event("set_integrator", {"mode": integrator_mode})

func _planet_to_dict(p: Planet) -> Dictionary:
    return {
        "px": p.pos.x,
        "py": p.pos.y,
        "vx": p.vel.x,
        "vy": p.vel.y,
        "mass": p.mass,
        "radius": p.radius,
        "color": p.color.to_html()
    }

func _planet_from_dict(entry: Dictionary) -> Planet:
    var pos := Vector2(float(entry.get("px", 0.0)), float(entry.get("py", 0.0)))
    var vel := Vector2(float(entry.get("vx", 0.0)), float(entry.get("vy", 0.0)))
    var mass := float(entry.get("mass", 10.0))
    var radius := float(entry.get("radius", 6.0))
    var color := Color.from_string(str(entry.get("color", "#ffffff")), Color.WHITE)
    return Planet.new(pos, vel, mass, radius, color)

func _save_preset() -> void:
    var planets_data: Array[Dictionary] = []
    for p in planets:
        planets_data.append(_planet_to_dict(p))
    var payload := {
        "gravity_constant": gravity_constant,
        "time_scale_factor": time_scale_factor,
        "softening": softening,
        "trail_limit": trail_limit,
        "trails_enabled": trails_enabled,
        "adaptive_timestep_enabled": adaptive_timestep_enabled,
        "merge_enabled": merge_enabled,
        "show_velocity_vectors": show_velocity_vectors,
        "gameplay_mode": gameplay_mode,
        "integrator_mode": integrator_mode,
        "force_mode": force_mode,
        "barnes_hut_theta": barnes_hut_theta,
        "seed_value": seed_value,
        "planets": planets_data
    }
    var json := JSON.stringify(payload)
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file != null:
        file.store_string(json)

func _load_preset() -> void:
    if !FileAccess.file_exists(SAVE_PATH):
        return
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return

    var data: Dictionary = parsed
    gravity_constant = float(data.get("gravity_constant", gravity_constant))
    time_scale_factor = float(data.get("time_scale_factor", time_scale_factor))
    softening = float(data.get("softening", softening))
    trail_limit = maxi(10, int(data.get("trail_limit", trail_limit)))
    trails_enabled = bool(data.get("trails_enabled", trails_enabled))
    adaptive_timestep_enabled = bool(data.get("adaptive_timestep_enabled", adaptive_timestep_enabled))
    merge_enabled = bool(data.get("merge_enabled", merge_enabled))
    show_velocity_vectors = bool(data.get("show_velocity_vectors", show_velocity_vectors))
    var loaded_gameplay_mode := int(data.get("gameplay_mode", gameplay_mode))
    _set_integrator_mode(int(data.get("integrator_mode", integrator_mode)))
    _set_force_mode(int(data.get("force_mode", force_mode)))
    barnes_hut_theta = clampf(float(data.get("barnes_hut_theta", barnes_hut_theta)), 0.25, 1.2)
    seed_value = int(data.get("seed_value", seed_value))
    _apply_seed(seed_value)

    gravity_slider.value = gravity_constant
    time_slider.value = time_scale_factor
    softening_slider.value = softening
    if theta_slider != null:
        theta_slider.value = barnes_hut_theta
    trail_slider.value = float(trail_limit)
    trail_button.text = "Trails: On" if trails_enabled else "Trails: Off"
    adaptive_button.text = "Adaptive Step: On" if adaptive_timestep_enabled else "Adaptive Step: Off"
    merge_button.text = "Merge: On" if merge_enabled else "Merge: Off"
    vectors_button.text = "Vectors: On" if show_velocity_vectors else "Vectors: Off"
    if seed_input != null:
        seed_input.text = str(seed_value)
    _set_gameplay_mode(loaded_gameplay_mode, false)

    var raw_planets: Variant = data.get("planets", [])
    if raw_planets is Array:
        planets.clear()
        for entry in raw_planets:
            if typeof(entry) != TYPE_DICTIONARY:
                continue
            planets.append(_planet_from_dict(entry))
    if planets.is_empty():
        _seed_default_system(START_PLANETS)
    _capture_initial_state()
    _refresh_gameplay_ui()

func _export_telemetry_csv() -> void:
    var file := FileAccess.open(TELEMETRY_PATH, FileAccess.WRITE)
    if file == null:
        return
    for row in telemetry_rows:
        file.store_line(row)

func _snapshot_planets() -> Array[Dictionary]:
    var snapshot: Array[Dictionary] = []
    for p in planets:
        snapshot.append(_planet_to_dict(p))
    return snapshot

func _restore_planets_from_snapshot(snapshot: Array[Dictionary]) -> void:
    planets.clear()
    for entry in snapshot:
        planets.append(_planet_from_dict(entry))

func _integrator_name(mode_value: int) -> String:
    if mode_value == IntegratorMode.EULER:
        return "Euler"
    if mode_value == IntegratorMode.RK4:
        return "RK4"
    return "Leapfrog"

func _run_integrator_benchmark_export(record_event: bool = true) -> void:
    if record_event:
        _append_replay_event("run_benchmark", {})

    var original_snapshot := _snapshot_planets()
    var benchmark_seed_snapshot: Array[Dictionary] = []
    if !initial_state.is_empty():
        for entry in initial_state:
            benchmark_seed_snapshot.append(entry)
    else:
        for entry in original_snapshot:
            benchmark_seed_snapshot.append(entry)

    var original_integrator := integrator_mode
    var original_paused := simulation_paused
    var original_trails := trails_enabled
    var original_recording := record_events_enabled
    var original_replay := replay_active

    if replay_active:
        _stop_replay()
    record_events_enabled = false
    if record_button != null:
        record_button.text = "Record: Off"

    trails_enabled = false
    if trail_button != null:
        trail_button.text = "Trails: Off"
    simulation_paused = false
    if pause_button != null:
        pause_button.text = "Pause"

    var csv_lines: Array[String] = []
    csv_lines.append("integrator,simulated_seconds,steps,final_energy_drift_percent")
    for mode_value in [IntegratorMode.EULER, IntegratorMode.LEAPFROG, IntegratorMode.RK4]:
        _restore_planets_from_snapshot(benchmark_seed_snapshot)
        _set_integrator_mode(mode_value)
        var start_energy := _total_system_energy()
        var simulated_seconds := 0.0
        var steps := 0
        while simulated_seconds < BENCHMARK_SECONDS:
            _simulate_step(BENCHMARK_STEP)
            simulated_seconds += BENCHMARK_STEP
            steps += 1
        var end_energy := _total_system_energy()
        var drift_pct := 0.0
        if absf(start_energy) > 0.0001:
            drift_pct = ((end_energy - start_energy) / absf(start_energy)) * 100.0
        csv_lines.append("%s,%.3f,%d,%.6f" % [_integrator_name(mode_value), simulated_seconds, steps, drift_pct])

    var benchmark_file := FileAccess.open(BENCHMARK_PATH, FileAccess.WRITE)
    if benchmark_file != null:
        for line in csv_lines:
            benchmark_file.store_line(line)

    _restore_planets_from_snapshot(original_snapshot)
    _set_integrator_mode(original_integrator)
    simulation_paused = original_paused
    if pause_button != null:
        pause_button.text = "Resume" if simulation_paused else "Pause"
    trails_enabled = original_trails
    if trail_button != null:
        trail_button.text = "Trails: On" if trails_enabled else "Trails: Off"
    record_events_enabled = original_recording
    if record_button != null:
        record_button.text = "Record: On" if record_events_enabled else "Record: Off"
    if original_replay && replay_button != null:
        replay_button.text = "Replay"

func _run_self_tests_export_report(record_event: bool = true) -> void:
    if record_event:
        _append_replay_event("run_self_tests", {})

    var original_snapshot := _snapshot_planets()
    var original_initial := initial_state.duplicate(true)
    var original_initial_energy := initial_total_energy
    var original_integrator := integrator_mode
    var original_force_mode := force_mode
    var original_theta := barnes_hut_theta
    var original_merge := merge_enabled
    var original_trails := trails_enabled
    var original_paused := simulation_paused
    var original_recording := record_events_enabled
    var original_replay := replay_active
    var original_gameplay_mode := gameplay_mode
    var original_challenge_active := challenge_active
    var original_challenge_time_left := challenge_time_left
    var original_challenge_score := challenge_score
    var original_challenge_combo := challenge_combo
    var original_score_sample_elapsed := score_sample_elapsed
    var original_challenge_status := challenge_status_text
    var original_challenge_message := challenge_message
    var original_challenge_message_time := challenge_message_time
    var original_shockwave_cooldown := shockwave_cooldown_left
    var original_shockwave_visual_active := shockwave_visual_active
    var original_shockwave_visual_time := shockwave_visual_time
    var original_shockwave_visual_origin := shockwave_visual_origin

    if replay_active:
        _stop_replay()
    record_events_enabled = false
    if record_button != null:
        record_button.text = "Record: Off"

    var tests: Array[Dictionary] = []
    tests.append(_self_test_two_body_energy_drift())
    tests.append(_self_test_barnes_hut_approximation_accuracy())
    tests.append(_self_test_replay_checksum_validation())
    tests.append(_self_test_challenge_scoring_rules())

    var passed := 0
    for test in tests:
        if bool(test.get("pass", false)):
            passed += 1

    var report := {
        "generated_at": Time.get_datetime_string_from_system(true, true),
        "pass_count": passed,
        "total_count": tests.size(),
        "all_passed": passed == tests.size(),
        "tests": tests
    }

    var report_file := FileAccess.open(REGRESSION_REPORT_PATH, FileAccess.WRITE)
    if report_file != null:
        report_file.store_string(JSON.stringify(report, "\t"))

    last_self_test_summary = "%d/%d passed (%s)" % [passed, tests.size(), "ok" if passed == tests.size() else "needs attention"]

    _restore_planets_from_snapshot(original_snapshot)
    initial_state = original_initial
    initial_total_energy = original_initial_energy
    _set_integrator_mode(original_integrator)
    _set_force_mode(original_force_mode)
    barnes_hut_theta = original_theta
    if theta_slider != null:
        theta_slider.value = barnes_hut_theta
    merge_enabled = original_merge
    trails_enabled = original_trails
    simulation_paused = original_paused
    if pause_button != null:
        pause_button.text = "Resume" if simulation_paused else "Pause"
    if trail_button != null:
        trail_button.text = "Trails: On" if trails_enabled else "Trails: Off"
    if merge_button != null:
        merge_button.text = "Merge: On" if merge_enabled else "Merge: Off"
    record_events_enabled = original_recording
    if record_button != null:
        record_button.text = "Record: On" if record_events_enabled else "Record: Off"
    if original_replay && replay_button != null:
        replay_button.text = "Replay"
    _set_gameplay_mode(original_gameplay_mode, false)
    challenge_active = original_challenge_active
    challenge_time_left = original_challenge_time_left
    challenge_score = original_challenge_score
    challenge_combo = original_challenge_combo
    score_sample_elapsed = original_score_sample_elapsed
    challenge_status_text = original_challenge_status
    challenge_message = original_challenge_message
    challenge_message_time = original_challenge_message_time
    shockwave_cooldown_left = original_shockwave_cooldown
    shockwave_visual_active = original_shockwave_visual_active
    shockwave_visual_time = original_shockwave_visual_time
    shockwave_visual_origin = original_shockwave_visual_origin
    _refresh_gameplay_ui()

func _self_test_two_body_energy_drift() -> Dictionary:
    var saved_merge := merge_enabled
    var saved_trails := trails_enabled
    merge_enabled = false
    trails_enabled = false

    planets.clear()
    var center := Vector2(640, 360)
    var primary_mass := 9000.0
    var secondary_mass := 48.0
    var radius := 240.0
    var secondary_speed := sqrt((gravity_constant * primary_mass) / radius)
    planets.append(Planet.new(center, Vector2.ZERO, primary_mass, 20.0, Color(1.0, 0.85, 0.3)))
    planets.append(Planet.new(center + Vector2(radius, 0.0), Vector2(0.0, secondary_speed), secondary_mass, 6.5, Color(0.6, 0.9, 1.0)))

    _set_integrator_mode(IntegratorMode.RK4)
    _set_force_mode(ForceMode.DIRECT)

    var start_energy := _total_system_energy()
    var simulated := 0.0
    var steps := 0
    while simulated < 6.0:
        _simulate_step(1.0 / 120.0)
        simulated += 1.0 / 120.0
        steps += 1
    var end_energy := _total_system_energy()
    var drift_pct := 0.0
    if absf(start_energy) > 0.0001:
        drift_pct = ((end_energy - start_energy) / absf(start_energy)) * 100.0

    merge_enabled = saved_merge
    trails_enabled = saved_trails

    return {
        "name": "two_body_energy_drift_rk4",
        "pass": absf(drift_pct) <= 1.5,
        "metric": drift_pct,
        "threshold_abs_percent": 1.5,
        "steps": steps
    }

func _self_test_barnes_hut_approximation_accuracy() -> Dictionary:
    var local_rng := RandomNumberGenerator.new()
    local_rng.seed = 240513
    var positions: Array[Vector2] = []
    var masses: Array[float] = []
    for i in range(64):
        positions.append(Vector2(local_rng.randf_range(-920.0, 920.0), local_rng.randf_range(-640.0, 640.0)))
        masses.append(local_rng.randf_range(16.0, 140.0))

    var direct := _accelerations_direct(positions, masses)
    var approx := _accelerations_barnes_hut(positions, masses, 0.6)
    var avg_rel := 0.0
    var worst_rel := 0.0
    var count: int = mini(direct.size(), approx.size())
    for i in range(count):
        var denom := maxf(direct[i].length(), 1.0)
        var rel := (approx[i] - direct[i]).length() / denom
        avg_rel += rel
        worst_rel = maxf(worst_rel, rel)
    if count > 0:
        avg_rel /= float(count)

    return {
        "name": "barnes_hut_vs_direct_force",
        "pass": avg_rel <= 0.35 && worst_rel <= 1.2,
        "avg_relative_error": avg_rel,
        "worst_relative_error": worst_rel,
        "theta": 0.6,
        "samples": count
    }

func _self_test_replay_checksum_validation() -> Dictionary:
    var final_snapshot: Array[Dictionary] = [
        {"px": 4.0, "py": 6.0, "vx": 0.5, "vy": -0.2, "mass": 10.0, "radius": 2.0, "color": "#ffffff"}
    ]
    var payload := {
        "seed_value": 7,
        "gravity_constant": 1200.0,
        "time_scale_factor": 1.0,
        "softening": 20.0,
        "trail_limit": 180,
        "trails_enabled": true,
        "adaptive_timestep_enabled": false,
        "merge_enabled": true,
        "show_velocity_vectors": false,
        "gameplay_mode": GameplayMode.SANDBOX,
        "integrator_mode": IntegratorMode.RK4,
        "force_mode": ForceMode.BARNES_HUT,
        "barnes_hut_theta": 0.6,
        "initial_state": [
            {"px": 1.0, "py": 2.0, "vx": 0.0, "vy": 0.0, "mass": 10.0, "radius": 2.0, "color": "#ffffff"}
        ],
        "events": [
            {"t": 0.1, "kind": "toggle_pause", "data": {}}
        ],
        "final_state_checksum": _state_checksum_for_snapshot(final_snapshot)
    }
    var checksum := _replay_checksum_for_payload(payload)
    var validates := checksum == _replay_checksum_for_payload(payload)
    var final_state_validates := str(payload.get("final_state_checksum", "")) == _state_checksum_for_snapshot(final_snapshot)

    var tampered := payload.duplicate(true)
    var tampered_events: Array = tampered.get("events", [])
    tampered_events.append({"t": 0.2, "kind": "toggle_trails", "data": {}})
    tampered["events"] = tampered_events
    var tamper_detected := checksum != _replay_checksum_for_payload(tampered)
    var tampered_final := final_snapshot.duplicate(true)
    var first_entry: Dictionary = tampered_final[0]
    first_entry["px"] = 9.0
    tampered_final[0] = first_entry
    var final_tamper_detected := str(payload.get("final_state_checksum", "")) != _state_checksum_for_snapshot(tampered_final)

    return {
        "name": "replay_checksum_validation",
        "pass": validates && tamper_detected && final_state_validates && final_tamper_detected,
        "tamper_detected": tamper_detected,
        "roundtrip_validated": validates,
        "final_state_validated": final_state_validates,
        "final_state_tamper_detected": final_tamper_detected
    }

func _self_test_challenge_scoring_rules() -> Dictionary:
    var saved_seed := seed_value
    _apply_seed(99731)
    _set_gameplay_mode(GameplayMode.CHALLENGE, false)

    planets.clear()
    var center := Vector2(640, 360)
    var star_mass := 9000.0
    planets.append(Planet.new(center, Vector2.ZERO, star_mass, 20.0, Color(1.0, 0.85, 0.3)))
    for i in range(8):
        var angle := TAU * float(i) / 8.0
        var radius := 150.0 + float(i) * 26.0
        var tangent := Vector2(-sin(angle), cos(angle))
        var speed := sqrt((gravity_constant * star_mass) / radius)
        var pos := center + Vector2(cos(angle), sin(angle)) * radius
        planets.append(Planet.new(pos, tangent * speed, 28.0 + float(i) * 3.0, 5.4, Color.from_hsv(float(i) / 8.0, 0.65, 0.95)))

    challenge_active = true
    challenge_score = 0.0
    challenge_combo = 1.0
    challenge_time_left = 20.0
    var stable_before := _count_stable_orbiters()
    _sample_challenge_score()
    var score_after_stable := challenge_score
    var combo_after_stable := challenge_combo

    while planets.size() > 2:
        planets.remove_at(planets.size() - 1)
    _sample_challenge_score()
    var combo_after_collapse := challenge_combo

    _apply_seed(saved_seed)
    return {
        "name": "challenge_scoring_rules",
        "pass": stable_before >= CHALLENGE_MIN_STABLE_ORBITERS && score_after_stable > 0.0 && combo_after_stable > 1.0 && combo_after_collapse <= combo_after_stable,
        "stable_before": stable_before,
        "score_after_stable": score_after_stable,
        "combo_after_stable": combo_after_stable,
        "combo_after_collapse": combo_after_collapse
    }

func _process(delta: float) -> void:
    if Input.is_action_pressed("ui_left"):
        cam.position.x -= 380.0 * delta * cam.zoom.x
    if Input.is_action_pressed("ui_right"):
        cam.position.x += 380.0 * delta * cam.zoom.x
    if Input.is_action_pressed("ui_up"):
        cam.position.y -= 380.0 * delta * cam.zoom.y
    if Input.is_action_pressed("ui_down"):
        cam.position.y += 380.0 * delta * cam.zoom.y

    var delta_sim := 0.0
    if !simulation_paused:
        var step_seconds := _effective_step_seconds(delta)
        _simulate_step(step_seconds * time_scale_factor)
        delta_sim = step_seconds * time_scale_factor
        telemetry_time += delta_sim
    if replay_active:
        _advance_replay(delta_sim)
    _update_gameplay_state(delta_sim, delta)
    _update_hud()
    queue_redraw()

func _effective_step_seconds(delta: float) -> float:
    var bounded := clampf(delta, ADAPTIVE_STEP_MIN, ADAPTIVE_STEP_MAX)
    if !adaptive_timestep_enabled:
        return bounded

    var max_speed := 0.0
    for p in planets:
        max_speed = maxf(max_speed, p.vel.length())
    var speed_factor := maxf(1.0, max_speed / 260.0)
    var adaptive := bounded / speed_factor
    return clampf(adaptive, ADAPTIVE_STEP_MIN, ADAPTIVE_STEP_MAX)

func _current_positions() -> Array[Vector2]:
    var positions: Array[Vector2] = []
    positions.resize(planets.size())
    for i in range(planets.size()):
        positions[i] = planets[i].pos
    return positions

func _mass_list_from_planets() -> Array[float]:
    var masses: Array[float] = []
    masses.resize(planets.size())
    for i in range(planets.size()):
        masses[i] = planets[i].mass
    return masses

func _gravity_accel_from_mass(target: Vector2, source: Vector2, source_mass: float) -> Vector2:
    var offset := source - target
    var dist_sq := maxf(offset.length_squared(), softening * softening)
    var dist := sqrt(dist_sq)
    if dist <= 0.000001:
        return Vector2.ZERO
    return (offset / dist) * (gravity_constant * source_mass / dist_sq)

func _accelerations_direct(positions: Array[Vector2], masses: Array[float]) -> Array[Vector2]:
    var count := positions.size()
    var accelerations: Array[Vector2] = []
    accelerations.resize(count)
    for i in range(count):
        accelerations[i] = Vector2.ZERO

    for i in range(count):
        for j in range(i + 1, count):
            var offset: Vector2 = positions[j] - positions[i]
            var dist_sq: float = maxf(offset.length_squared(), softening * softening)
            var dist: float = sqrt(dist_sq)
            var direction: Vector2 = offset / dist
            var force: float = gravity_constant * masses[i] * masses[j] / dist_sq
            accelerations[i] += direction * (force / masses[i])
            accelerations[j] -= direction * (force / masses[j])
    return accelerations

func _bh_subdivide(node: BHNode) -> void:
    var child_half := node.half_size * 0.5
    if child_half <= 0.0001:
        return
    node.children.clear()
    node.children.append(BHNode.new(node.center + Vector2(-child_half, -child_half), child_half))
    node.children.append(BHNode.new(node.center + Vector2(child_half, -child_half), child_half))
    node.children.append(BHNode.new(node.center + Vector2(-child_half, child_half), child_half))
    node.children.append(BHNode.new(node.center + Vector2(child_half, child_half), child_half))

func _bh_child_index(node: BHNode, point: Vector2) -> int:
    var east := point.x >= node.center.x
    var south := point.y >= node.center.y
    if south:
        return 3 if east else 2
    return 1 if east else 0

func _bh_contains_point(node: BHNode, point: Vector2) -> bool:
    return point.x >= (node.center.x - node.half_size) && point.x <= (node.center.x + node.half_size) && point.y >= (node.center.y - node.half_size) && point.y <= (node.center.y + node.half_size)

func _bh_insert(node: BHNode, body_index: int, positions: Array[Vector2], masses: Array[float]) -> void:
    var point := positions[body_index]
    var body_mass := masses[body_index]
    var updated_mass := node.mass + body_mass
    if updated_mass > 0.0:
        node.com = (node.com * node.mass + point * body_mass) / updated_mass
    node.mass = updated_mass

    if node.body_index == -2 && node.children.is_empty():
        return

    if node.body_index == -1 && node.children.is_empty():
        node.body_index = body_index
        return

    if node.children.is_empty():
        if node.half_size <= 1.0:
            node.body_index = -2
            return
        var existing := node.body_index
        node.body_index = -1
        _bh_subdivide(node)
        if existing >= 0:
            var existing_child := _bh_child_index(node, positions[existing])
            _bh_insert(node.children[existing_child], existing, positions, masses)

    var child_idx := _bh_child_index(node, point)
    _bh_insert(node.children[child_idx], body_index, positions, masses)

func _bh_acceleration_for_body(node: BHNode, body_index: int, positions: Array[Vector2], theta_value: float) -> Vector2:
    if node.mass <= 0.0:
        return Vector2.ZERO
    if node.children.is_empty():
        if node.body_index == body_index:
            return Vector2.ZERO
        return _gravity_accel_from_mass(positions[body_index], node.com, node.mass)

    var target_pos := positions[body_index]
    var offset := node.com - target_pos
    var dist := maxf(offset.length(), 0.001)
    var size := node.half_size * 2.0
    var contains_target := _bh_contains_point(node, target_pos)
    if !contains_target && (size / dist) < theta_value:
        return _gravity_accel_from_mass(target_pos, node.com, node.mass)

    var total := Vector2.ZERO
    for child in node.children:
        total += _bh_acceleration_for_body(child, body_index, positions, theta_value)
    return total

func _accelerations_barnes_hut(positions: Array[Vector2], masses: Array[float], theta_override: float = -1.0) -> Array[Vector2]:
    var count := positions.size()
    var accelerations: Array[Vector2] = []
    accelerations.resize(count)
    for i in range(count):
        accelerations[i] = Vector2.ZERO
    if count == 0:
        return accelerations

    var min_x := positions[0].x
    var max_x := positions[0].x
    var min_y := positions[0].y
    var max_y := positions[0].y
    for pos in positions:
        min_x = minf(min_x, pos.x)
        max_x = maxf(max_x, pos.x)
        min_y = minf(min_y, pos.y)
        max_y = maxf(max_y, pos.y)
    var span := maxf(max_x - min_x, max_y - min_y)
    var half := maxf(64.0, span * 0.55 + softening * 2.0)
    var root := BHNode.new(Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5), half)

    for i in range(count):
        _bh_insert(root, i, positions, masses)

    var theta_value := barnes_hut_theta
    if theta_override > 0.0:
        theta_value = theta_override
    theta_value = clampf(theta_value, 0.25, 1.2)
    for i in range(count):
        accelerations[i] = _bh_acceleration_for_body(root, i, positions, theta_value)
    return accelerations

func _accelerations_for_state(positions: Array[Vector2]) -> Array[Vector2]:
    var masses := _mass_list_from_planets()
    if force_mode == ForceMode.BARNES_HUT && positions.size() >= 8:
        return _accelerations_barnes_hut(positions, masses, barnes_hut_theta)
    return _accelerations_direct(positions, masses)

func _compute_accelerations() -> Array[Vector2]:
    return _accelerations_for_state(_current_positions())

func _simulate_step(delta_scaled: float) -> void:
    if integrator_mode == IntegratorMode.LEAPFROG:
        var accel_start := _compute_accelerations()
        for i in range(planets.size()):
            planets[i].vel += accel_start[i] * (0.5 * delta_scaled)
            planets[i].pos += planets[i].vel * delta_scaled

        var accel_end := _compute_accelerations()
        for i in range(planets.size()):
            planets[i].vel += accel_end[i] * (0.5 * delta_scaled)
    elif integrator_mode == IntegratorMode.RK4:
        var count := planets.size()
        if count > 0:
            var p0: Array[Vector2] = []
            var v0: Array[Vector2] = []
            p0.resize(count)
            v0.resize(count)
            for i in range(count):
                p0[i] = planets[i].pos
                v0[i] = planets[i].vel

            var a1 := _accelerations_for_state(p0)

            var p2: Array[Vector2] = []
            var v2: Array[Vector2] = []
            p2.resize(count)
            v2.resize(count)
            for i in range(count):
                p2[i] = p0[i] + v0[i] * (0.5 * delta_scaled)
                v2[i] = v0[i] + a1[i] * (0.5 * delta_scaled)

            var a2 := _accelerations_for_state(p2)

            var p3: Array[Vector2] = []
            var v3: Array[Vector2] = []
            p3.resize(count)
            v3.resize(count)
            for i in range(count):
                p3[i] = p0[i] + v2[i] * (0.5 * delta_scaled)
                v3[i] = v0[i] + a2[i] * (0.5 * delta_scaled)

            var a3 := _accelerations_for_state(p3)

            var p4: Array[Vector2] = []
            var v4: Array[Vector2] = []
            p4.resize(count)
            v4.resize(count)
            for i in range(count):
                p4[i] = p0[i] + v3[i] * delta_scaled
                v4[i] = v0[i] + a3[i] * delta_scaled

            var a4 := _accelerations_for_state(p4)

            for i in range(count):
                var pos_delta := (v0[i] + 2.0 * v2[i] + 2.0 * v3[i] + v4[i]) * (delta_scaled / 6.0)
                var vel_delta := (a1[i] + 2.0 * a2[i] + 2.0 * a3[i] + a4[i]) * (delta_scaled / 6.0)
                planets[i].pos = p0[i] + pos_delta
                planets[i].vel = v0[i] + vel_delta
    else:
        var accelerations := _compute_accelerations()
        for i in range(planets.size()):
            planets[i].vel += accelerations[i] * delta_scaled
            planets[i].pos += planets[i].vel * delta_scaled

    for i in range(planets.size()):
        if trails_enabled:
            planets[i].trail.push_back(planets[i].pos)
            if planets[i].trail.size() > trail_limit:
                planets[i].trail.remove_at(0)
        elif planets[i].trail.size() > 0:
            planets[i].trail = PackedVector2Array([planets[i].pos])

    if merge_enabled:
        _merge_overlapping_planets()

func _merge_overlapping_planets() -> void:
    if planets.size() < 2:
        return

    var merged_planets: Array[Planet] = []
    var consumed: Dictionary = {}

    for i in range(planets.size()):
        if consumed.has(i):
            continue
        var merged := planets[i]
        for j in range(i + 1, planets.size()):
            if consumed.has(j):
                continue
            var candidate := planets[j]
            var touching := merged.pos.distance_to(candidate.pos) <= (merged.radius + candidate.radius)
            if !touching:
                continue

            var total_mass: float = merged.mass + candidate.mass
            var total_momentum: Vector2 = merged.vel * merged.mass + candidate.vel * candidate.mass
            var merged_pos: Vector2 = (merged.pos * merged.mass + candidate.pos * candidate.mass) / total_mass
            var merged_vel: Vector2 = total_momentum / total_mass
            var merged_radius: float = sqrt(merged.radius * merged.radius + candidate.radius * candidate.radius)
            var blend_weight: float = candidate.mass / total_mass
            var merged_color: Color = merged.color.lerp(candidate.color, blend_weight)

            merged = Planet.new(merged_pos, merged_vel, total_mass, merged_radius, merged_color)
            consumed[j] = true

        merged_planets.append(merged)

    planets = merged_planets

func _update_hud() -> void:
    var fps := Engine.get_frames_per_second()
    var energy := _total_system_energy()
    var angular_momentum := _total_system_angular_momentum()
    var momentum := _total_system_momentum()
    var energy_drift := energy - initial_total_energy
    var drift_pct := 0.0
    if absf(initial_total_energy) > 0.0001:
        drift_pct = (energy_drift / absf(initial_total_energy)) * 100.0

    var paused_text := "yes" if simulation_paused else "no"
    var trails_text := "on" if trails_enabled else "off"
    var adaptive_text := "on" if adaptive_timestep_enabled else "off"
    var merge_text := "on" if merge_enabled else "off"
    var vector_text := "on" if show_velocity_vectors else "off"
    var integrator_text := "Leapfrog"
    var force_text := "Direct"
    if integrator_mode == IntegratorMode.EULER:
        integrator_text = "Euler"
    elif integrator_mode == IntegratorMode.RK4:
        integrator_text = "RK4"
    if force_mode == ForceMode.BARNES_HUT:
        force_text = "Barnes-Hut"
    var mode_text := "challenge" if gameplay_mode == GameplayMode.CHALLENGE else "sandbox"
    var challenge_suffix := ""
    if gameplay_mode == GameplayMode.CHALLENGE:
        challenge_suffix = " score:%.1f/%.1f combo:x%.2f t:%.1f" % [challenge_score, challenge_goal_score, challenge_combo, challenge_time_left]
    hud_label.text = "Bodies:%d FPS:%d E:%.2f dE:%+.3f%% Lz:%.1f P:(%.1f,%.1f) G:%.1f dt:%.2f soft:%.1f int:%s force:%s theta:%.2f chk:%s tests:%s adapt:%s merge:%s vec:%s trails:%s(%d) seed:%d paused:%s mode:%s%s" % [
        planets.size(), fps, energy, drift_pct, angular_momentum, momentum.x, momentum.y, gravity_constant, time_scale_factor, softening, integrator_text, force_text, barnes_hut_theta, replay_checksum_state, last_self_test_summary, adaptive_text, merge_text, vector_text, trails_text, trail_limit, seed_value, paused_text, mode_text, challenge_suffix
    ]
    _refresh_gameplay_ui()
    _record_telemetry_sample(energy, angular_momentum, drift_pct)

func _total_system_energy() -> float:
    var kinetic := 0.0
    for p in planets:
        kinetic += 0.5 * p.mass * p.vel.length_squared()

    var potential := 0.0
    for i in range(planets.size()):
        for j in range(i + 1, planets.size()):
            var distance := maxf(planets[i].pos.distance_to(planets[j].pos), 1.0)
            potential -= gravity_constant * planets[i].mass * planets[j].mass / distance

    return kinetic + potential

func _total_system_momentum() -> Vector2:
    var total := Vector2.ZERO
    for p in planets:
        total += p.vel * p.mass
    return total

func _total_system_angular_momentum() -> float:
    var com := _center_of_mass()
    var total := 0.0
    for p in planets:
        var r := p.pos - com
        total += p.mass * (r.x * p.vel.y - r.y * p.vel.x)
    return total

func _center_of_mass() -> Vector2:
    var total_mass := 0.0
    var accum := Vector2.ZERO
    for p in planets:
        total_mass += p.mass
        accum += p.pos * p.mass
    if total_mass <= 0.0:
        return Vector2.ZERO
    return accum / total_mass

func _compute_orbital_spawn_velocity(world_pos: Vector2) -> Vector2:
    var center := _center_of_mass()
    var offset := world_pos - center
    var distance := maxf(offset.length(), 80.0)
    if offset.length() < 0.001:
        offset = Vector2.RIGHT * distance
    var tangent := Vector2(-offset.y, offset.x).normalized()
    var speed := sqrt((gravity_constant * 5500.0) / distance) * rng.randf_range(0.7, 1.0)
    return tangent * speed

func _spawn_planet_with_velocity(world_pos: Vector2, velocity: Vector2) -> Planet:
    var mass := rng.randf_range(25.0, 120.0)
    var radius := 4.0 + sqrt(mass) * 0.5
    var color := Color.from_hsv(rng.randf(), 0.7, 0.95)
    var planet := Planet.new(world_pos, velocity, mass, radius, color)
    planets.append(planet)
    return planet

func _spawn_planet_from_record(data: Dictionary) -> void:
    var world_pos := Vector2(float(data.get("px", 0.0)), float(data.get("py", 0.0)))
    var velocity := Vector2(float(data.get("vx", 0.0)), float(data.get("vy", 0.0)))
    var mass := float(data.get("mass", 32.0))
    var radius := float(data.get("radius", 6.0))
    var color := Color.from_string(str(data.get("color", "#ffffff")), Color.WHITE)
    planets.append(Planet.new(world_pos, velocity, mass, radius, color))

func _spawn_planet_at(world_pos: Vector2) -> void:
    var velocity := _compute_orbital_spawn_velocity(world_pos)
    var planet := _spawn_planet_with_velocity(world_pos, velocity)
    _append_replay_event("spawn", {
        "px": world_pos.x,
        "py": world_pos.y,
        "vx": velocity.x,
        "vy": velocity.y,
        "mass": planet.mass,
        "radius": planet.radius,
        "color": planet.color.to_html()
    })

func _delete_planet_near(world_pos: Vector2) -> bool:
    if planets.is_empty():
        return false

    var best_index := -1
    var best_dist := 1e20
    for i in range(planets.size()):
        var p := planets[i]
        var pick_radius := maxf(DELETE_PICK_RADIUS, p.radius + 8.0)
        var dist := p.pos.distance_to(world_pos)
        if dist <= pick_radius && dist < best_dist:
            best_dist = dist
            best_index = i

    if best_index >= 0:
        planets.remove_at(best_index)
        return true
    return false

func _screen_to_world(screen_pos: Vector2) -> Vector2:
    return get_viewport().get_canvas_transform().affine_inverse() * screen_pos

func _draw_drag_preview() -> void:
    if !drag_spawn_active:
        return
    var drag_vec := drag_current_world - drag_start_world
    draw_circle(drag_start_world, 4.0, Color(0.95, 0.95, 0.95, 0.9))
    draw_line(drag_start_world, drag_current_world, Color(0.85, 0.95, 1.0, 0.9), 2.0)
    var preview_velocity := drag_vec * DRAG_VELOCITY_SCALE
    var preview_tip := drag_start_world + preview_velocity * (VELOCITY_VECTOR_SCALE * 8.0)
    draw_line(drag_start_world, preview_tip, Color(0.2, 1.0, 0.8, 0.9), 2.0)

func _draw_background_stars() -> void:
    for star in background_stars:
        var pos: Vector2 = star.get("pos", Vector2.ZERO)
        var radius := float(star.get("r", 1.0))
        var alpha := float(star.get("a", 0.4))
        var phase := float(star.get("phase", 0.0))
        var speed := float(star.get("speed", 0.5))
        var pulse := 0.55 + 0.45 * (0.5 + 0.5 * sin(visual_time * speed + phase))
        draw_circle(pos, radius, Color(0.78, 0.84, 1.0, alpha * pulse))

func _draw_challenge_overlay() -> void:
    if gameplay_mode != GameplayMode.CHALLENGE:
        return
    var anchor := _largest_body()
    if anchor == null:
        return
    draw_arc(anchor.pos, 120.0, 0.0, TAU, 90, Color(0.38, 0.72, 1.0, 0.26), 1.2)
    draw_arc(anchor.pos, 420.0, 0.0, TAU, 120, Color(0.35, 0.78, 0.55, 0.18), 1.1)
    if challenge_active:
        draw_circle(anchor.pos, anchor.radius + 8.0, Color(0.25, 0.95, 0.75, 0.16))

func _draw_shockwave_fx() -> void:
    if !shockwave_visual_active:
        return
    var t := clampf(shockwave_visual_time / SHOCKWAVE_VISUAL_DURATION, 0.0, 1.0)
    var radius := lerpf(10.0, SHOCKWAVE_RADIUS, t)
    var alpha := 1.0 - t
    draw_arc(shockwave_visual_origin, radius, 0.0, TAU, 120, Color(0.5, 1.0, 0.95, 0.95 * alpha), 2.0)
    draw_circle(shockwave_visual_origin, 5.0 + 16.0 * (1.0 - t), Color(0.65, 1.0, 0.9, 0.28 * alpha))

func _draw() -> void:
    var view_size := get_viewport_rect().size
    var top_left := Vector2.ZERO
    if cam != null:
        view_size *= cam.zoom
        top_left = cam.position - view_size * 0.5
    draw_rect(Rect2(top_left, view_size), Color(0.02, 0.02, 0.05), true)
    _draw_background_stars()
    _draw_challenge_overlay()

    for p in planets:
        if p.trail.size() > 1:
            draw_polyline(p.trail, p.color.darkened(0.35), 1.5, true)

    for p in planets:
        draw_circle(p.pos, p.radius, p.color)

    if show_velocity_vectors:
        for p in planets:
            var tip := p.pos + p.vel * VELOCITY_VECTOR_SCALE
            draw_line(p.pos, tip, p.color.lightened(0.25), 1.2)

    if !planets.is_empty():
        var com := _center_of_mass()
        draw_circle(com, 4.0, Color(1.0, 1.0, 1.0, 0.9))
        draw_line(com + Vector2(-10, 0), com + Vector2(10, 0), Color(1.0, 1.0, 1.0, 0.8), 1.5)
        draw_line(com + Vector2(0, -10), com + Vector2(0, 10), Color(1.0, 1.0, 1.0, 0.8), 1.5)

    _draw_drag_preview()
    _draw_shockwave_fx()

func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var button_event := event as InputEventMouseButton
        if button_event.button_index == MOUSE_BUTTON_MIDDLE:
            panning_camera = button_event.pressed
            last_mouse_pos = button_event.position
        elif button_event.button_index == MOUSE_BUTTON_LEFT:
            var hovered_left := get_viewport().gui_get_hovered_control()
            if button_event.pressed:
                if hovered_left == null:
                    drag_spawn_active = true
                    drag_start_world = _screen_to_world(button_event.position)
                    drag_current_world = drag_start_world
            else:
                if drag_spawn_active:
                    drag_current_world = _screen_to_world(button_event.position)
                    var drag_vec := drag_current_world - drag_start_world
                    if drag_vec.length() < DRAG_SPAWN_MIN_DISTANCE:
                        _spawn_planet_at(drag_start_world)
                    else:
                        var drag_velocity := drag_vec * DRAG_VELOCITY_SCALE
                        var spawned := _spawn_planet_with_velocity(drag_start_world, drag_velocity)
                        _append_replay_event("spawn", {
                            "px": drag_start_world.x,
                            "py": drag_start_world.y,
                            "vx": drag_velocity.x,
                            "vy": drag_velocity.y,
                            "mass": spawned.mass,
                            "radius": spawned.radius,
                            "color": spawned.color.to_html()
                        })
                drag_spawn_active = false
        elif button_event.pressed && button_event.button_index == MOUSE_BUTTON_RIGHT:
            var hovered_right := get_viewport().gui_get_hovered_control()
            if hovered_right == null:
                var world_pos_right := _screen_to_world(button_event.position)
                if _delete_planet_near(world_pos_right):
                    _append_replay_event("delete", {
                        "px": world_pos_right.x,
                        "py": world_pos_right.y
                    })
        elif button_event.pressed && button_event.button_index == MOUSE_BUTTON_WHEEL_UP:
            cam.zoom *= 0.9
            cam.zoom.x = clampf(cam.zoom.x, 0.2, 5.0)
            cam.zoom.y = clampf(cam.zoom.y, 0.2, 5.0)
        elif button_event.pressed && button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            cam.zoom *= 1.1
            cam.zoom.x = clampf(cam.zoom.x, 0.2, 5.0)
            cam.zoom.y = clampf(cam.zoom.y, 0.2, 5.0)

    if event is InputEventMouseMotion:
        var motion_event := event as InputEventMouseMotion
        if panning_camera:
            cam.position -= motion_event.relative * cam.zoom
        elif drag_spawn_active:
            drag_current_world = _screen_to_world(motion_event.position)

    if event is InputEventKey:
        var key_event := event as InputEventKey
        if key_event.pressed && !key_event.echo:
            if key_event.keycode == KEY_SPACE:
                if get_viewport().gui_get_focus_owner() == null:
                    _on_shockwave_pressed()
            elif key_event.keycode == KEY_TAB:
                _toggle_gameplay_mode()
EOF

  sed -i.bak "s/__START_PLANETS__/$requested_planets/g" "$tmp_dir/Main.gd"
  rm -f "$tmp_dir/Main.gd.bak"

  for rel in project.godot Main.tscn Main.gd; do
    file_diff=$(diff -u /dev/null "$tmp_dir/$rel" || true)
    if [ -n "$(trim "$file_diff")" ]; then
      file_diff=$(printf '%s\n' "$file_diff" | sed "1s|^--- .*|--- /dev/null|;2s|^+++ .*|+++ b/$rel|")
      patch_text="${patch_text}
${file_diff}"
    fi
  done

  rm -rf "$tmp_dir"
  patch_text=$(trim_block_edges "$patch_text")
  printf '%s' "$patch_text"
}

framework_bootstrap_patch_for_prompt() {
  prompt_lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$prompt_lower" in
    *godot*)
      if printf '%s' "$prompt_lower" | grep -Eq 'gravity|gravitational|orbit|orbital|revolv|planet|celestial|n[- ]?body|bodies'; then
        requested_planets=$(godot_requested_planet_min_from_prompt "$prompt_lower")
        if [ -z "$requested_planets" ] || [ "$requested_planets" -lt 80 ]; then
          requested_planets=80
        fi
        godot_gravity_template_patch "$requested_planets"
        return 0
      fi
      ;;
  esac
  printf '%s' ""
}

godot_requested_planet_min_from_prompt() {
  prompt_lower=$1
  printf '%s\n' "$prompt_lower" | perl -CS -0777 -ne '
    my $s = lc $_;
    my $max = 0;

    while ($s =~ /(\d{1,4})\s*\+/g) {
      my $n = $1 + 0;
      $max = $n if $n > $max;
    }
    while ($s =~ /at\s+least\s+(\d{1,4})(?!\d)/g) {
      my $n = $1 + 0;
      $max = $n if $n > $max;
    }
    while ($s =~ /(\d{1,4})(?!\d)\s+(?:planets|bodies)\b/g) {
      my $n = $1 + 0;
      $max = $n if $n > $max;
    }
    print $max if $max > 0;
  '
}

godot_start_planets_value_from_text() {
  text=$1
  printf '%s\n' "$text" | perl -CS -0777 -ne '
    my $s = lc $_;
    my $max = 0;
    while ($s =~ /start_planets\s*:?=\s*(\d{1,4})/g) {
      my $n = $1 + 0;
      $max = $n if $n > $max;
    }
    print $max if $max > 0;
  '
}

framework_patch_is_low_confidence() {
  prompt_text=$1
  patch_text=$2
  workspace_path=${3:-}
  prompt_lower=$(printf '%s' "$prompt_text" | tr '[:upper:]' '[:lower:]')
  patch_trimmed=$(trim "$patch_text")

  [ -n "$patch_trimmed" ] || return 0

  case "$prompt_lower" in
    *godot*)
      workspace_has_project=0
      if [ -n "$workspace_path" ] && [ -d "$workspace_path" ]; then
        if find "$workspace_path" -maxdepth 3 -type f -name 'project.godot' 2>/dev/null | sed -n '1p' | grep -q '.'; then
          workspace_has_project=1
        fi
      fi
      if [ "$workspace_has_project" -eq 1 ]; then
        return 1
      fi

      paths_file=$(mktemp)
      patch_paths_from_text "$patch_text" > "$paths_file"
      has_project_path=0
      has_scene_path=0
      has_script_path=0
      while IFS= read -r rel_path; do
        rel_path=$(trim "$rel_path")
        [ -n "$rel_path" ] || continue
        case "$rel_path" in
          */project.godot|project.godot)
            has_project_path=1
            ;;
          *.tscn)
            has_scene_path=1
            ;;
          *.gd)
            has_script_path=1
            ;;
        esac
      done < "$paths_file"
      rm -f "$paths_file"

      has_application=0
      has_main_scene=0
      has_config_version=0
      if printf '%s\n' "$patch_text" | grep -Eiq '^[+ ][[:space:]]*\[application\][[:space:]]*$'; then
        has_application=1
      fi
      if printf '%s\n' "$patch_text" | grep -Eiq '^[+ ][[:space:]]*run/main_scene[[:space:]]*='; then
        has_main_scene=1
      fi
      if printf '%s\n' "$patch_text" | grep -Eiq '^[+ ][[:space:]]*config_version[[:space:]]*='; then
        has_config_version=1
      fi

      if [ "$has_project_path" -eq 1 ] && [ "$has_scene_path" -eq 1 ] && [ "$has_script_path" -eq 1 ] && \
         [ "$has_application" -eq 1 ] && [ "$has_main_scene" -eq 1 ] && [ "$has_config_version" -eq 1 ]; then
        patch_lower=$(printf '%s' "$patch_text" | tr '[:upper:]' '[:lower:]')

        if printf '%s' "$prompt_lower" | grep -Eq 'pause|resume|reset|slider|time scale|gravitational constant|sandbox'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'pause|resume|reset|slider|hslider|time_scale|gravity_constant'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'collision|merge'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'collision|merge'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'camera|pan|zoom'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'camera2d|camera|pan|zoom'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'hud|fps|energy'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'hud|fps|energy'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '5\\+|at least[[:space:]]+5([^0-9]|$)|(^|[^[:alpha:]])five([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*([5-9]|1[0-9])|start_planets[[:space:]]*=[[:space:]]*([5-9]|1[0-9])'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '8\\+|at least[[:space:]]+8([^0-9]|$)|(^|[^[:alpha:]])eight([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(8|9|1[0-9])|start_planets[[:space:]]*=[[:space:]]*(8|9|1[0-9])'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '10\\+|at least[[:space:]]+10([^0-9]|$)|(^|[^[:alpha:]])ten([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(10|1[1-9])|start_planets[[:space:]]*=[[:space:]]*(10|1[1-9])'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '14\\+|at least[[:space:]]+14([^0-9]|$)|14[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])fourteen([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(1[4-9]|[2-9][0-9])|start_planets[[:space:]]*=[[:space:]]*(1[4-9]|[2-9][0-9])'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '20\\+|at least[[:space:]]+20([^0-9]|$)|20[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])twenty([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(2[0-9]|[3-9][0-9])|start_planets[[:space:]]*=[[:space:]]*(2[0-9]|[3-9][0-9])'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '30\\+|at least[[:space:]]+30([^0-9]|$)|30[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])thirty([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(3[0-9]|[4-9][0-9])|start_planets[[:space:]]*=[[:space:]]*(3[0-9]|[4-9][0-9])'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '40\\+|at least[[:space:]]+40([^0-9]|$)|40[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])forty([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*(4[0-9]|[5-9][0-9])|start_planets[[:space:]]*=[[:space:]]*(4[0-9]|[5-9][0-9])'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '60\\+|at least[[:space:]]+60([^0-9]|$)|60[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])sixty([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*([6-9][0-9]|[1-9][0-9][0-9])|start_planets[[:space:]]*=[[:space:]]*([6-9][0-9]|[1-9][0-9][0-9])'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq '80\\+|at least[[:space:]]+80([^0-9]|$)|80[[:space:]]+(planets|bodies)|(^|[^[:alpha:]])eighty([^[:alpha:]]|$)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'start_planets[[:space:]]*:=[[:space:]]*([8-9][0-9]|[1-9][0-9][0-9])|start_planets[[:space:]]*=[[:space:]]*([8-9][0-9]|[1-9][0-9][0-9])'; then
            return 0
          fi
        fi

        requested_planet_min=$(godot_requested_planet_min_from_prompt "$prompt_lower")
        if [ -n "$requested_planet_min" ] && [ "$requested_planet_min" -ge 5 ]; then
          patch_start_planets=$(godot_start_planets_value_from_text "$patch_lower")
          if [ -z "$patch_start_planets" ] || [ "$patch_start_planets" -lt "$requested_planet_min" ]; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'click|spawn'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'spawn|mouse_button_left|inputeventmousebutton'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'gameplay|fun|interactiv|challenge|objective|score|combo|win|lose'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'gameplay_mode|challenge_active|challenge_score|challenge_label|_sample_challenge_score|set_gameplay_mode'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'ability|abilities|power[- ]?up|special move|shockwave|cooldown'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'shockwave|cooldown|_trigger_shockwave|on_shockwave_pressed'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'polish|juic|juice|feel|visual feedback|fx|effects|presentation'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'background_stars|draw_background|draw_arc|challenge_message|visual_time|autowrap'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'right[- ]click|delete|remove planet'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'mouse_button_right'; then
            return 0
          fi
          if ! printf '%s' "$patch_lower" | grep -Eq 'delete|remove_at|erase'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'adaptive|time[ -]?step|timestep'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'adaptive|effective_step|step_seconds'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'deterministic|seed'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'seed|randomnumbergenerator|rng|lineedit|apply_seed'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'step once|single step|advance one tick|one tick'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'step_once|step once|step_once_delta'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'merge toggle|collision/merge toggle|collision toggle|toggle merge'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'merge_enabled|toggle_merge|merge:'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'velocity[- ]vectors?|vectors toggle|velocity arrows?'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'show_velocity_vectors|toggle_vectors|velocity_vector|vectors:'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'center of mass|centre of mass|com marker'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'center_of_mass'; then
            return 0
          fi
          if ! printf '%s' "$patch_lower" | grep -Eq 'draw_circle|draw_line'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'total momentum|momentum.*(readout|display|hud|on-screen|onscreen)'; then
          if ! printf '%s' "$patch_lower" | grep -Eq '_total_system_momentum|momentum:'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'trail|toggle'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'trail'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'clear[- ]?trails?|clear trails button'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'clear_trails|clear trails'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'integrator|leapfrog|euler|symplectic'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'integrator|leapfrog|euler|optionbutton|item_selected'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'rk4|runge-kutta'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'rk4|runge|integratormode'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'softening'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'softening'; then
            return 0
          fi
          if ! printf '%s' "$patch_lower" | grep -Eq 'slider|hslider|on_softening'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'click[- ]drag|drag[- ]spawn|velocity preview|drag.*preview|click and drag'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'drag_spawn|inputeventmousemotion|mousemotion|draw_drag|preview_velocity|drag_current'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'angular momentum|\\blz\\b'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'angular_momentum|_total_system_angular_momentum|\\blz\\b'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'energy drift|drift from initial|delta energy|\\bde\\b'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'energy_drift|initial_total_energy|drift_pct|drift'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'telemetry|export csv|csv export|continuous telemetry|time, energy'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'telemetry|csv|export_telemetry|store_line|fileaccess'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'record|replay|input events|event log|deterministic replay'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'record|replay|replay_events|record_events|replay_path|_start_replay|_toggle_recording'; then
            return 0
          fi
          if ! printf '%s' "$patch_lower" | grep -Eq 'json|fileaccess'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'benchmark|benchmark integrators|benchmark_results|energy drift percent|simulated_seconds'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'benchmark|benchmark_results|run_benchmark|benchmark_path|_run_integrator_benchmark'; then
            return 0
          fi
          if ! printf '%s' "$patch_lower" | grep -Eq 'csv|store_line|fileaccess'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'barnes[- ]?hut|theta|approximation mode|n[[:space:]]*log[[:space:]]*n|quadtree'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'barnes|bhnode|quadtree|theta|force_mode|_accelerations_barnes_hut'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'checksum|hash|digest'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'checksum|sha256|mismatch|replay_checksum|validate'; then
            return 0
          fi
          if ! printf '%s' "$patch_lower" | grep -Eq 'json|fileaccess'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'final[ -]?state checksum|end[ -]?state checksum|state checksum'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'final_state_checksum|state_checksum_for_snapshot|final-mismatch|ok\\+final'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'self[- ]?tests?|regression|regression_report|validation suite'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'self_test|run_self_tests|regression_report|report_path'; then
            return 0
          fi
          if ! printf '%s' "$patch_lower" | grep -Eq 'json|fileaccess'; then
            return 0
          fi
        fi

        if printf '%s' "$prompt_lower" | grep -Eq 'save|load|json|preset'; then
          if ! printf '%s' "$patch_lower" | grep -Eq 'save|load|json|fileaccess|preset'; then
            return 0
          fi
        fi

        return 1
      fi
      return 0
      ;;
  esac

  return 1
}

