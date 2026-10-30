extends Node
## The sound of a room while you're in it, made here (no recordings, as the jeep's and the story's sounds): a loop of
## its air (people talking, louder the more there are; ceiling fans turning; the AC's hiss; a stadium's crowd)
## and, now and then, what such a place does (the station's and the airport's announcement chime, the temple bell,
## a bus horn at the stand, a cheer in the stand, steel tumblers at the tea stall). Loops are made once and kept.

const RATE := 16000.0
const LOOP_SECS := 8.0

## room → [murmur (0..1), fans, ac, events: [kind, every min s, every max s, volume dB]]
const PLACES := {
	"station": [1.0, true, false, [["chime", 18.0, 40.0, -6.0]]],
	"bus": [0.9, true, false, [["horn", 7.0, 18.0, -10.0]]],
	"airport": [0.7, false, true, [["chime", 25.0, 50.0, -8.0]]],
	"mall_avinashi": [0.8, false, true, [["chime", 40.0, 80.0, -12.0]]],
	"mall_sathy": [0.8, false, true, [["chime", 40.0, 80.0, -12.0]]],
	"church": [0.12, true, false, []],
	"stadium": [0.0, false, false, [["cheer", 12.0, 30.0, -4.0]]],
	"temple_hall": [0.3, false, false, [["bell", 6.0, 14.0, -8.0]]],
	"temple": [0.2, false, false, [["bell", 6.0, 14.0, -8.0]]],
	"collectorate": [0.6, true, false, []],
	"hospital_gov": [0.7, true, false, []],
	"hospital_pvt": [0.4, false, true, []],
	"college": [0.6, true, false, []],
	"trade_fair": [0.8, false, true, []],
	"restaurant": [0.5, true, false, [["clink", 3.0, 9.0, -14.0]]],
	"mess": [0.5, true, false, [["clink", 3.0, 9.0, -14.0]]],
	"tea": [0.4, true, false, [["clink", 2.0, 7.0, -12.0]]],
	"fine_dining": [0.25, false, true, [["clink", 5.0, 14.0, -18.0]]],
	"kirana": [0.25, true, false, []],
	"bank": [0.35, true, false, []],
	"coopbank": [0.35, true, false, []],
	"hotel": [0.2, false, true, []],
	"office": [0.25, true, false, []],
	"dev_office": [0.2, false, true, []],
	"police": [0.2, true, false, []],
}

static var _cache := {}               # loops and one-shots, made once
var _events: Array = []
var _rng := RandomNumberGenerator.new()


## Start the room's sound: `people` in it (the murmur grows with them, a big room's crowd louder).
func setup(room_name: String, people: int) -> void:
	_rng.randomize()
	var p: Array = PLACES.get(room_name, [0.0, true, false, []])
	var talk: float = p[0] * clampf(0.4 + people / 30.0, 0.4, 1.2)
	if room_name == "stadium":
		_loop("crowd", _crowd(), -6.0)
	elif talk > 0.01:
		_loop("murmur", _murmur(), linear_to_db(talk) - 8.0)
	if p[1]:
		_loop("fans", _fans(), -18.0)
	if p[2]:
		_loop("ac", _ac(), -20.0)
	for e in p[3]:
		var pl := AudioStreamPlayer.new()
		pl.volume_db = e[3]
		add_child(pl)
		_events.append({"kind": e[0], "min": e[1], "max": e[2], "player": pl, "t": _rng.randf_range(1.0, e[1])})


## (testing) Every sound written as a WAV into dir.
static func save_all(dir: String) -> void:
	for k in ["murmur", "crowd", "fans", "ac"]:
		var w: AudioStreamWAV = {"murmur": _murmur, "crowd": _crowd, "fans": _fans, "ac": _ac}[k].call()
		w.save_to_wav("%s/%s.wav" % [dir, k])
	for k in ["chime", "bell", "horn", "cheer", "clink"]:
		_oneshot(k).save_to_wav("%s/%s.wav" % [dir, k])


func _process(dt: float) -> void:
	for e in _events:
		e["t"] -= dt
		if e["t"] <= 0.0:
			e["t"] = _rng.randf_range(e["min"], e["max"])
			var pl: AudioStreamPlayer = e["player"]
			pl.stream = _oneshot(e["kind"])
			pl.pitch_scale = _rng.randf_range(0.94, 1.06) if e["kind"] in ["clink", "horn"] else 1.0
			pl.play()


func _loop(key: String, wav: AudioStreamWAV, db: float) -> void:
	var pl := AudioStreamPlayer.new()
	pl.stream = wav
	pl.volume_db = db
	add_child(pl)
	pl.play(_rng.randf() * LOOP_SECS * 0.9)


# ----------------------------------------------------------------------------- the sounds
static func _murmur() -> AudioStreamWAV:
	if _cache.has("murmur"):
		return _cache["murmur"]
	var n := int(RATE * LOOP_SECS)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for v in 10:                                            # ten voices, each its own pitch band and rhythm
		var f0 := rng.randf_range(350.0, 1400.0)
		var bp := _Biquad.bandpass(f0, 1.2)
		var syl := rng.randf_range(3.0, 5.5)                # syllables a second
		var ph := rng.randf() * TAU
		var pause_ph := rng.randf() * TAU
		for i in n:
			var t := i / RATE
			var env := maxf(sin(t * syl * TAU + ph + 0.6 * sin(t * 1.3 + ph)), 0.0)
			env *= 0.4 + 0.6 * maxf(sin(t * 0.35 * TAU + pause_ph), 0.0)        # a phrase, a pause
			out[i] += bp.step(rng.randf_range(-1.0, 1.0)) * env
	return _store("murmur", out)


static func _crowd() -> AudioStreamWAV:
	if _cache.has("crowd"):
		return _cache["crowd"]
	var n := int(RATE * LOOP_SECS)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var lp := _Biquad.lowpass(1800.0)
	var bp := _Biquad.bandpass(700.0, 0.6)
	for i in n:
		var t := i / RATE
		var w := rng.randf_range(-1.0, 1.0)
		out[i] = bp.step(w) * (0.7 + 0.3 * sin(t * 0.5 * TAU)) + lp.step(w) * 0.25
	return _store("crowd", out)


static func _fans() -> AudioStreamWAV:
	if _cache.has("fans"):
		return _cache["fans"]
	var n := int(RATE * LOOP_SECS)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var lp := _Biquad.lowpass(500.0)
	for i in n:
		var t := i / RATE
		var hum := 0.25 * sin(t * 100.0 * TAU) + 0.12 * sin(t * 150.0 * TAU)        # the motor (50 Hz mains)
		var whoosh := lp.step(rng.randf_range(-1.0, 1.0)) * (0.7 + 0.3 * sin(t * 4.5 * TAU))   # three blades turning
		out[i] = hum * 0.4 + whoosh
	return _store("fans", out)


static func _ac() -> AudioStreamWAV:
	if _cache.has("ac"):
		return _cache["ac"]
	var n := int(RATE * LOOP_SECS)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 14
	var bp := _Biquad.bandpass(2500.0, 0.5)
	var lp := _Biquad.lowpass(200.0)
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		out[i] = bp.step(w) * 0.6 + lp.step(w) * 0.6
	return _store("ac", out)


static func _oneshot(kind: String) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var out := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 15
	match kind:
		"chime":                                            # the three-note announcement chime
			var notes := [659.3, 523.3, 392.0]
			out.resize(int(RATE * 2.6))
			for k in 3:
				var start := int(RATE * 0.55 * k)
				for i in range(start, out.size()):
					var t := (i - start) / RATE
					out[i] += (sin(t * notes[k] * TAU) + 0.3 * sin(t * notes[k] * 2.0 * TAU)) * exp(-t * 2.2) * 0.35
		"bell":                                             # a temple bell: inharmonic partials, a long ring
			out.resize(int(RATE * 4.0))
			var f := 520.0
			var parts := [[1.0, 1.0], [2.0, 0.6], [2.76, 0.45], [5.4, 0.25], [8.93, 0.12]]
			for i in out.size():
				var t := i / RATE
				var s := 0.0
				for pr in parts:
					s += pr[1] * sin(t * f * pr[0] * TAU) * exp(-t * (0.7 + pr[0] * 0.35))
				out[i] = s * 0.3 * (1.0 - exp(-t * 400.0))
		"horn":                                             # a bus horn across the bays: two tones, buzzy
			out.resize(int(RATE * 0.9))
			var lp := _Biquad.lowpass(1600.0)
			for i in out.size():
				var t := i / RATE
				var env := minf(t * 30.0, 1.0) * minf((0.9 - t) * 12.0, 1.0)
				var s := signf(sin(t * 415.0 * TAU)) * 0.5 + signf(sin(t * 520.0 * TAU)) * 0.5
				out[i] = lp.step(s) * env * 0.5
		"cheer":                                            # the crowd on its feet: a swell and back
			out.resize(int(RATE * 3.5))
			var bp := _Biquad.bandpass(900.0, 0.5)
			for i in out.size():
				var t := i / RATE
				var env := sin(clampf(t / 3.5, 0.0, 1.0) * PI) ** 1.5
				out[i] = bp.step(rng.randf_range(-1.0, 1.0)) * env * 1.4
		"clink":                                            # a steel tumbler set down
			out.resize(int(RATE * 0.5))
			for i in out.size():
				var t := i / RATE
				out[i] = (sin(t * 2350.0 * TAU) + 0.6 * sin(t * 3710.0 * TAU) + 0.3 * sin(t * 5200.0 * TAU)) * exp(-t * 14.0) * 0.3
	return _store(kind, out, false)


## Normalise to a peak, make a loop's ends meet (a short crossfade), keep it.
static func _store(key: String, s: PackedFloat32Array, loop := true) -> AudioStreamWAV:
	var peak := 0.0001
	for v in s:
		peak = maxf(peak, absf(v))
	var fade := int(RATE * 0.25) if loop else 0
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		var v := s[i] / peak * 0.8
		if fade > 0 and i < fade:                            # the start mixed with what follows the end
			var k := float(i) / fade
			v = v * k + (s[s.size() - fade + i] / peak * 0.8) * (1.0 - k) if s.size() > 2 * fade else v
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(RATE)
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size() - fade
	_cache[key] = w
	return w


## A second-order filter (RBJ cookbook), for shaping noise.
class _Biquad:
	var b0 := 1.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0

	static func bandpass(f: float, q: float) -> _Biquad:
		var bq := _Biquad.new()
		var w0 := TAU * f / RATE
		var al := sin(w0) / (2.0 * q)
		var a0 := 1.0 + al
		bq.b0 = al / a0
		bq.b1 = 0.0
		bq.b2 = -al / a0
		bq.a1 = -2.0 * cos(w0) / a0
		bq.a2 = (1.0 - al) / a0
		return bq

	static func lowpass(f: float) -> _Biquad:
		var bq := _Biquad.new()
		var w0 := TAU * f / RATE
		var al := sin(w0) / (2.0 * 0.707)
		var a0 := 1.0 + al
		var c := cos(w0)
		bq.b0 = (1.0 - c) / 2.0 / a0
		bq.b1 = (1.0 - c) / a0
		bq.b2 = (1.0 - c) / 2.0 / a0
		bq.a1 = -2.0 * c / a0
		bq.a2 = (1.0 - al) / a0
		return bq

	func step(x: float) -> float:
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		return y
