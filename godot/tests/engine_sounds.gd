extends SceneTree
## Each kind of engine (jeep.gd ENGINE_SOUND) rendered to a WAV to listen to: 1 s at idle, 3 s revving up to near
## the redline under full load, 2 s falling back to idle off the throttle.
## Run: Godot --headless --path godot --script res://tests/engine_sounds.gd -- --out=DIR

const KINDS := {"karthik_scooter": "scooter", "bike": "bike", "auto": "auto", "hatchback": "petrol_car", "coupe": "sport",
	"luxury_suv": "diesel_suv", "bus": "heavy"}


func _init() -> void:
	var out := "user://engine_sounds"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out)
	var Jeep = load("res://scripts/drive/jeep.gd")
	for vehicle in KINDS:
		var car = Jeep.new()
		get_root().add_child(car)
		car.configure(vehicle)
		car.autopilot = true                          # (no keys: the sample is driven here)
		var rate := 22050
		var data := PackedByteArray()
		var n := rate * 6
		for i in n:
			var t := float(i) / rate
			var load := 0.0
			var r: float = car.idle_rpm
			if t >= 1.0 and t < 4.0:
				load = 1.0
				r = lerpf(car.idle_rpm, car.redline * 0.9, (t - 1.0) / 3.0)
			elif t >= 4.0:
				r = lerpf(car.redline * 0.9, car.idle_rpm, clampf((t - 4.0) / 1.5, 0.0, 1.0))
			car.rpm = r
			car.speed = (r - car.idle_rpm) / car.redline * 20.0
			var v := clampi(int(car._engine_sample(load) * 32767.0 * 2.5), -32768, 32767)
			data.append(v & 0xff)
			data.append((v >> 8) & 0xff)
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = rate
		wav.stereo = false
		wav.data = data
		var path := "%s/engine_%s_%s.wav" % [out, vehicle, KINDS[vehicle]]
		wav.save_to_wav(path)
		print("ENGINE %s → %s" % [vehicle, path])
		car.queue_free()
	quit()
