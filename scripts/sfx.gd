extends Node
## Autoload "Sfx": every sound in the game is synthesised here at startup, so
## the project needs no audio files. Swap any entry in `sounds` for a real
## AudioStream later (e.g. sounds["thud"] = load("res://assets/sfx/door.ogg")).

const RATE := 22050

var sounds: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _rumble: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1337
	_build_sounds()
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_rumble = AudioStreamPlayer.new()
	_rumble.stream = sounds["rumble"]
	add_child(_rumble)


func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not sounds.has(sound):
		return
	var player: AudioStreamPlayer = _players[0]
	for p in _players:
		if not p.playing:
			player = p
			break
	player.stream = sounds[sound]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


## Low looping rumble that warns of The Wanderer. amount: 0 (off) .. 1 (loud).
func set_rumble(amount: float) -> void:
	if amount <= 0.01:
		if _rumble.playing:
			_rumble.stop()
		return
	if not _rumble.playing:
		_rumble.play()
	_rumble.volume_db = linear_to_db(clampf(amount, 0.0, 1.0)) + 4.0


# --- Synthesis -------------------------------------------------------------

func _build_sounds() -> void:
	sounds["thud"] = _wav(_thud())
	sounds["door_open"] = _wav(_scrape())
	sounds["click"] = _wav(_click())
	sounds["lever"] = _wav(_lever())
	sounds["buzz"] = _wav(_buzz())
	sounds["unlock"] = _wav(_chime([660.0, 990.0], 0.16))
	sounds["pickup"] = _wav(_sweep(520.0, 1250.0, 0.22))
	sounds["ore"] = _wav(_chime([1180.0, 1580.0], 0.07))
	sounds["jump"] = _wav(_noise_burst(0.12, 0.25, 0.18))
	sounds["slide"] = _wav(_noise_burst(0.32, 0.12, 0.22))
	sounds["hide"] = _wav(_noise_burst(0.25, 0.08, 0.3))
	sounds["screech"] = _wav(_screech())
	sounds["death"] = _wav(_death())
	sounds["tick"] = _wav(_tick())
	sounds["blip"] = _wav(_sweep(880.0, 900.0, 0.05))
	sounds["select"] = _wav(_sweep(520.0, 820.0, 0.12))
	sounds["level"] = _wav(_chime([220.0, 277.0, 330.0], 0.35))
	var r := _rumble_loop()
	sounds["rumble"] = _wav(r, true)


func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


func _thud() -> PackedFloat32Array:
	var b := _buf(0.7)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1, 1) - lp) * 0.08
		b[i] = sin(TAU * 52.0 * t) * exp(-t * 6.0) * 0.9 + lp * exp(-t * 14.0) * 1.6 \
			+ sin(TAU * 410.0 * t) * exp(-t * 30.0) * 0.12
	return b


func _scrape() -> PackedFloat32Array:
	var b := _buf(0.8)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var env := minf(t / 0.05, 1.0) * clampf((0.8 - t) / 0.3, 0.0, 1.0)
		var k := 0.04 + 0.05 * sin(t * 9.0)
		lp += (_rng.randf_range(-1, 1) - lp) * k
		b[i] = (lp * 1.8 + sin(TAU * (140.0 - t * 60.0) * t) * 0.15) * env * 0.7
	return b


func _click() -> PackedFloat32Array:
	var b := _buf(0.06)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = _rng.randf_range(-1, 1) * exp(-t * 140.0) * 0.5 + sin(TAU * 1900.0 * t) * exp(-t * 90.0) * 0.3
	return b


func _lever() -> PackedFloat32Array:
	var b := _buf(0.3)
	for i in b.size():
		var t := float(i) / RATE
		var hit2 := 0.0
		if t > 0.09:
			hit2 = sin(TAU * 95.0 * (t - 0.09)) * exp(-(t - 0.09) * 22.0) * 0.8
		b[i] = _rng.randf_range(-1, 1) * exp(-t * 90.0) * 0.4 + hit2
	return b


func _buzz() -> PackedFloat32Array:
	var b := _buf(0.35)
	for i in b.size():
		var t := float(i) / RATE
		var sq := 1.0 if fmod(t * 110.0, 1.0) < 0.5 else -1.0
		b[i] = sq * 0.22 * clampf((0.35 - t) / 0.05, 0.0, 1.0)
	return b


func _chime(freqs: Array, step: float) -> PackedFloat32Array:
	var b := _buf(step * freqs.size() + 0.35)
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for n in freqs.size():
			var start := step * n
			if t >= start:
				var lt := t - start
				v += sin(TAU * float(freqs[n]) * lt) * exp(-lt * 7.0) * 0.35
		b[i] = v
	return b


func _sweep(f0: float, f1: float, dur: float) -> PackedFloat32Array:
	var b := _buf(dur)
	var phase := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / dur)
		phase += TAU * f / RATE
		b[i] = sin(phase) * 0.35 * clampf((dur - t) / (dur * 0.5), 0.0, 1.0)
	return b


func _noise_burst(dur: float, cutoff: float, vol: float) -> PackedFloat32Array:
	var b := _buf(dur)
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1, 1) - lp) * cutoff
		b[i] = lp * vol * 3.0 * minf(t / 0.01, 1.0) * clampf((dur - t) / (dur * 0.7), 0.0, 1.0)
	return b


func _screech() -> PackedFloat32Array:
	var b := _buf(1.6)
	var phase := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var env := minf(t / 0.35, 1.0) * clampf((1.6 - t) / 0.6, 0.0, 1.0)
		var f := 700.0 - t * 330.0 + sin(t * 70.0) * 40.0
		phase += TAU * f / RATE
		var saw := fmod(phase / TAU, 1.0) * 2.0 - 1.0
		lp += (_rng.randf_range(-1, 1) - lp) * 0.3
		b[i] = (saw * 0.25 + lp * 0.9 + sin(TAU * 45.0 * t) * 0.4) * env * 0.8
	return b


func _death() -> PackedFloat32Array:
	var b := _buf(1.3)
	var phase := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / RATE
		phase += TAU * (90.0 - t * 50.0) / RATE
		lp += (_rng.randf_range(-1, 1) - lp) * 0.15
		b[i] = sin(phase) * exp(-t * 2.0) * 0.8 + lp * exp(-t * 4.0) * 1.2
	return b


func _tick() -> PackedFloat32Array:
	var b := _buf(0.03)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = _rng.randf_range(-1, 1) * exp(-t * 260.0) * 0.35
	return b


## 2 second seamless loop: low sines with whole cycles + crossfaded noise.
func _rumble_loop() -> PackedFloat32Array:
	var n := RATE * 2
	var fade := int(RATE * 0.25)
	var noise := PackedFloat32Array()
	noise.resize(n + fade)
	var lp := 0.0
	var lp2 := 0.0
	for i in noise.size():
		lp += (_rng.randf_range(-1, 1) - lp) * 0.02
		lp2 += (lp - lp2) * 0.05
		noise[i] = lp2 * 14.0
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		var t := float(i) / RATE
		var nz := noise[i]
		if i < fade:
			var a := float(i) / fade
			nz = noise[i] * a + noise[n + i] * (1.0 - a)
		var tone := sin(TAU * 36.0 * t) * 0.35 + sin(TAU * 49.5 * t) * 0.2 * (0.6 + 0.4 * sin(TAU * 1.5 * t))
		b[i] = clampf(nz * 0.7 + tone, -1.0, 1.0) * 0.8
	return b
