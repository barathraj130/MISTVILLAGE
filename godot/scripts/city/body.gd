extends CanvasLayer
## Karthik's meters shown on his body, not as numbers (GAME_DESIGN.md §8 rule 8):
##   tired      the edges of the view darken and close in; over 70 his eyes close now and then, slowly, and longer
##              the nearer he is to the end of him; on foot he walks heavier (slower)
##   stressed   his heartbeat, heard over the street once stress is over 60, faster and louder as it climbs; the
##              view's edges tighten with each beat
##   hungry     his stomach, now and then, under 25
## The bars come back with F1 (life.gd show_meters). Eyes closing are also used by sleep (lids), and by
## life.gd when he's dozing at the wheel.
const Prof := preload("res://scripts/drive/prof.gd")

const SHADER := """
shader_type canvas_item;
uniform float edge = 0.0;      // 0..1 how far the dark edges close in
uniform float lids = 0.0;      // 0 open .. 1 shut
void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv * vec2(1.0, 0.75)) * 1.6;
	float a = smoothstep(1.05 - edge * 0.55, 1.35 - edge * 0.35, r) * clamp(edge * 1.4, 0.0, 0.92);
	float half = lids * 0.5;
	float lid = max(smoothstep(half + 0.06, half - 0.02, UV.y), smoothstep(1.0 - half - 0.06, 1.0 - half + 0.02, UV.y));
	COLOR = vec4(0.0, 0.0, 0.0, max(a, lid * step(0.001, lids)));
}
"""

var life                                   # life.gd
var lids_hold := 0.0                       # (sleep, dozing: life.gd holds the eyes shut or half shut)
var _mat: ShaderMaterial
var _t := 0.0
var _blink := 0.0                          # a blink under way: seconds into it
var _next_blink := 12.0
var _beat_t := 0.0
var _pulse := 0.0
var _growl_t := 30.0
var _heart: AudioStreamPlayer
var _stomach: AudioStreamPlayer


func _ready() -> void:
	layer = 7
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	r.material = _mat
	add_child(r)
	_heart = AudioStreamPlayer.new()
	_heart.stream = _thump()
	add_child(_heart)
	_stomach = AudioStreamPlayer.new()
	_stomach.stream = _growl()
	_stomach.volume_db = -6.0
	add_child(_stomach)


func _process(dt: float) -> void:
	var _p0 := Time.get_ticks_usec()
	_process_timed(dt)
	Prof.add("bodies", _p0)


func _process_timed(dt: float) -> void:
	if life == null:
		return
	_t += dt
	var tired := clampf((float(life.tiredness) - 45.0) / 55.0, 0.0, 1.0)
	var stress := clampf((float(life.stress) - 60.0) / 40.0, 0.0, 1.0)
	# the heart: 70 bpm at 60 stress .. 125 at 100, heard over 60
	if stress > 0.0 and not life.busy:
		_beat_t += dt * (70.0 + 55.0 * stress) / 60.0
		if _beat_t >= 1.0:
			_beat_t -= 1.0
			_heart.volume_db = lerpf(-26.0, -6.0, stress)
			_heart.play()
			_pulse = 1.0
	_pulse = maxf(_pulse - dt * 4.0, 0.0)
	# blinks of a tired man: every 6–14 s over 70, each longer as he nears 100
	var lids := 0.0
	if float(life.tiredness) > 70.0 and not life.busy:
		_next_blink -= dt
		if _next_blink <= 0.0 and _blink <= 0.0:
			_blink = 0.001
			_next_blink = randf_range(6.0, 14.0) * lerpf(1.0, 0.45, tired)
	if _blink > 0.0:
		var dur := lerpf(0.5, 1.6, tired)
		_blink += dt
		lids = sin(clampf(_blink / dur, 0.0, 1.0) * PI) * lerpf(0.7, 1.0, tired)
		if _blink >= dur:
			_blink = 0.0
	lids = maxf(lids, lids_hold)
	_mat.set_shader_parameter("edge", clampf(tired * 0.75 + stress * 0.25 + _pulse * stress * 0.15, 0.0, 1.0))
	_mat.set_shader_parameter("lids", lids)
	# the stomach
	if float(life.energy) < 25.0 and not life.busy:
		_growl_t -= dt
		if _growl_t <= 0.0:
			_growl_t = randf_range(35.0, 70.0)
			_stomach.play()
	var w = life.city.walker if life.city else null
	if w:                                          # tired legs
		w.walk_speed = 1.4 * lerpf(1.0, 0.78, clampf((float(life.tiredness) - 75.0) / 25.0, 0.0, 1.0))


## Shut his eyes slowly (sleep) or open them: awaitable.
func eyes(shut: bool, secs: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "lids_hold", 1.0 if shut else 0.0, secs)
	await tw.finished


static func _thump() -> AudioStreamWAV:
	var rate := 16000
	var s := PackedFloat32Array()
	for k in 2:                                    # lub … dub
		var n := int(0.13 * rate)
		for i in n:
			var t := float(i) / rate
			s.append(sin(TAU * (52.0 if k == 0 else 64.0) * t) * exp(-t * 28.0) * (1.0 if k == 0 else 0.7))
		for i in int(0.09 * rate):
			s.append(0.0)
	return _wav(s, rate)


static func _growl() -> AudioStreamWAV:
	var rate := 16000
	var s := PackedFloat32Array()
	var n := int(1.6 * rate)
	var lp := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		ph += (70.0 + 30.0 * sin(t * 5.0) + 20.0 * sin(t * 13.0)) / rate
		lp += (randf_range(-1.0, 1.0) - lp) * 0.04
		var env := sin(clampf(t / 1.6, 0.0, 1.0) * PI) * (0.6 + 0.4 * sin(t * 9.0))
		s.append((sin(TAU * ph) * 0.5 + lp * 2.5) * env * 0.6)
	return _wav(s, rate)


static func _wav(s: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, clampi(int(s[i] * 32767.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w
