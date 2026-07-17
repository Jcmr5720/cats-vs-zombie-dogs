extends Node
## Audio provisional (Fase 09). Combina assets reales cuando existen con fallbacks
## procedurales, y centraliza buses, volumen, musica y limites anti-spam.

const MIX_RATE: int = 22050
const SFX_POOL_SIZE: int = 18
const UI_HOVER_COOLDOWN_MS: int = 90
const DEFAULT_SFX_COOLDOWN_MS: int = 45
const DEFAULT_SIMULTANEOUS_LIMIT: int = 3
const UI_AUDIO_DIR := "res://assets/audio/ui/"

const UI_REAL_STREAMS: Dictionary = {
	&"ui_hover": ["UI Hover.wav", "UI_Hover.wav", "Button Select.wav", "Button_Select.wav"],
	&"ui_click": ["UI Click.wav", "UI_Click.wav", "Button Click.wav", "Button_Click.wav"],
	&"ui_buy": ["Purchase.wav"],
	&"ui_error": ["Error.mp3"],
	&"ui_open": ["Menu Open.mp3", "Menu_Open.mp3"],
	&"ui_close": ["Menu Close.mp3", "Menu_Close.mp3"],
	&"ui_select": ["Button Select.wav", "Button_Select.wav"],
	&"ui_button_click": ["Button Click.wav", "Button_Click.wav"],
	&"ui_notification": ["Notification.wav"],
}

var _sfx: Dictionary = {}
var _music: Dictionary = {}
var _music_gain_db: Dictionary = {}
var _cooldowns_ms: Dictionary = {}
var _limits: Dictionary = {}
var _last_played: Dictionary = {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _current_music: StringName = &""
var _muted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_build_streams()
	_build_players()


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	# Liberar los reproductores de forma explicita (no solo stop()): al salir del
	# proceso, dejar un playback activo hace que el AudioServer no alcance a soltar
	# el stream/playback antes del chequeo de fugas del motor. free() destruye el
	# nodo en el acto y libera su playback interno de forma sincrona.
	for player in _sfx_pool:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
			player.free()
	_sfx_pool.clear()
	if is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null
		_music_player.free()
	_music_player = null
	_sfx.clear()
	_music.clear()
	_music_gain_db.clear()
	_cooldowns_ms.clear()
	_limits.clear()
	_last_played.clear()


func play_sfx(sound_name: StringName) -> void:
	_play(sound_name, "SFX")


func play_ui(sound_name: StringName) -> void:
	_play(sound_name, "UI")


func play_music(sound_name: StringName) -> void:
	if _muted or not _music.has(sound_name):
		return
	if not is_instance_valid(_music_player):
		return
	if _current_music == sound_name and _music_player.playing:
		return
	_current_music = sound_name
	_music_player.stop()
	_music_player.stream = _music[sound_name]
	_music_player.volume_db = float(_music_gain_db.get(sound_name, 0.0))
	_music_player.play()


func stop_music() -> void:
	_current_music = &""
	if is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null
		_music_player.volume_db = 0.0


func reset_for_scene_change() -> void:
	for player in _sfx_pool:
		if is_instance_valid(player):
			player.stop()
	if is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null
		_music_player.volume_db = 0.0
	_current_music = &""
	_last_played.clear()


func set_master_volume(value: float) -> void:
	_set_bus_volume("Master", value)


func set_music_volume(value: float) -> void:
	_set_bus_volume("Music", value)


func set_sfx_volume(value: float) -> void:
	_set_bus_volume("SFX", value)


func set_ui_volume(value: float) -> void:
	_set_bus_volume("UI", value)


func mute_all(enabled: bool) -> void:
	_muted = enabled
	var master_index: int = AudioServer.get_bus_index("Master")
	if master_index != -1:
		AudioServer.set_bus_mute(master_index, enabled)


func is_muted() -> bool:
	return _muted


func _play(sound_name: StringName, bus: String) -> void:
	if _muted or not _sfx.has(sound_name):
		return
	var now: int = Time.get_ticks_msec()
	var cooldown: int = int(_cooldowns_ms.get(sound_name, DEFAULT_SFX_COOLDOWN_MS))
	if now - int(_last_played.get(sound_name, -999999)) < cooldown:
		return
	var limit: int = int(_limits.get(sound_name, DEFAULT_SIMULTANEOUS_LIMIT))
	if _active_count(sound_name) >= limit:
		return
	var player := _free_sfx_player()
	if player == null:
		return
	_last_played[sound_name] = now
	player.stop()
	player.bus = bus
	player.stream = _sfx[sound_name]
	player.pitch_scale = randf_range(0.96, 1.04)
	player.set_meta("audio_name", sound_name)
	player.play()


func _free_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_pool:
		if not player.playing:
			return player
	return null


func _active_count(sound_name: StringName) -> int:
	var count: int = 0
	for player in _sfx_pool:
		if player.playing and player.has_meta("audio_name") and player.get_meta("audio_name") == sound_name:
			count += 1
	return count


func _build_players() -> void:
	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_sfx_pool.append(player)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)


func _ensure_buses() -> void:
	for bus_name in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index: int = AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")


func _set_bus_volume(bus_name: String, value: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	var clamped: float = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(clamped) if clamped > 0.0 else -80.0)


func _build_streams() -> void:
	_add_tone(&"ui_hover", 880.0, 0.035, 0.20, "sine", UI_HOVER_COOLDOWN_MS, 1)
	_add_tone(&"ui_click", 520.0, 0.055, 0.28, "triangle", 55, 2)
	_add_tone(&"ui_buy", 720.0, 0.11, 0.34, "chime", 120, 1)
	_add_tone(&"ui_error", 190.0, 0.13, 0.30, "square", 180, 1)
	_add_tone(&"ui_open", 460.0, 0.09, 0.26, "rise", 120, 1)
	_add_tone(&"ui_close", 410.0, 0.08, 0.24, "fall", 120, 1)
	_add_tone(&"ui_select", 680.0, 0.08, 0.24, "triangle", 90, 1)
	_add_tone(&"ui_button_click", 480.0, 0.055, 0.25, "triangle", 55, 2)
	_add_tone(&"ui_notification", 760.0, 0.22, 0.24, "chime", 250, 1)
	_apply_real_ui_streams()

	_add_tone(&"shoot_basic", 740.0, 0.045, 0.18, "square", 90, 2)
	_add_tone(&"shoot_strong", 420.0, 0.075, 0.22, "square", 120, 2)
	_add_tone(&"explosion", 95.0, 0.22, 0.36, "noise_fall", 150, 2)
	_add_tone(&"laser", 1200.0, 0.12, 0.20, "laser", 130, 1)
	_add_tone(&"enemy_hit", 260.0, 0.035, 0.13, "noise", 70, 2)
	_add_tone(&"enemy_die", 310.0, 0.11, 0.22, "fall", 95, 3)
	_add_tone(&"xp_collect", 980.0, 0.045, 0.16, "chime", 85, 1)
	_add_tone(&"level_up", 620.0, 0.32, 0.36, "level", 250, 1)
	_add_tone(&"player_damage", 150.0, 0.15, 0.32, "fall", 250, 1)
	_add_tone(&"rescue_cat", 660.0, 0.32, 0.34, "rescue", 300, 1)
	_add_tone(&"medic_heal", 720.0, 0.16, 0.20, "chime", 450, 1)
	_add_tone(&"companion_downed", 180.0, 0.22, 0.30, "fall", 350, 1)
	_add_tone(&"companion_revived", 560.0, 0.24, 0.31, "chime", 300, 1)
	_add_tone(&"orbital_hit", 520.0, 0.055, 0.14, "triangle", 160, 1)
	_add_tone(&"boss_appear", 92.0, 0.55, 0.42, "boss", 700, 1)
	_add_tone(&"boss_hit", 180.0, 0.09, 0.24, "noise", 180, 2)
	_add_tone(&"boss_die", 130.0, 0.75, 0.45, "boss_die", 800, 1)
	_add_tone(&"victory", 520.0, 0.85, 0.40, "victory", 1000, 1)
	_add_tone(&"defeat", 210.0, 0.75, 0.38, "defeat", 1000, 1)
	_add_tone(&"event_alert", 360.0, 0.22, 0.28, "alert", 500, 1)
	_add_tone(&"low_health", 270.0, 0.18, 0.22, "pulse", 1200, 1)

	_music[&"menu"] = _make_music_loop([440.0, 523.25, 659.25, 587.33], 0.10, 0.055)
	_music[&"gameplay"] = _make_music_loop([392.0, 440.0, 493.88, 329.63], 0.08, 0.060)
	_music[&"boss"] = _make_music_loop([196.0, 220.0, 246.94, 174.61], 0.12, 0.075)
	_music[&"shelter"] = _make_shelter_loop()
	_music_gain_db[&"shelter"] = 5.0


func _add_tone(sound_name: StringName, freq: float, duration: float, volume: float, shape: String, cooldown_ms: int, limit: int) -> void:
	_sfx[sound_name] = _make_tone(freq, duration, volume, shape)
	_cooldowns_ms[sound_name] = cooldown_ms
	_limits[sound_name] = limit


func _apply_real_ui_streams() -> void:
	for key in UI_REAL_STREAMS.keys():
		var stream := _load_first_audio_stream(UI_REAL_STREAMS[key])
		if stream != null:
			_sfx[key] = stream


func _load_first_audio_stream(file_names: Array) -> AudioStream:
	for file_name in file_names:
		var path: String = UI_AUDIO_DIR + str(file_name)
		if not ResourceLoader.exists(path):
			continue
		var stream := load(path) as AudioStream
		if stream != null:
			return stream
	return null


func _make_tone(freq: float, duration: float, volume: float, shape: String) -> AudioStreamWAV:
	var frames: int = max(1, int(duration * MIX_RATE))
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq * 1000.0) + frames
	for i in frames:
		var t: float = float(i) / float(MIX_RATE)
		var p: float = float(i) / float(frames)
		var env: float = min(1.0, p / 0.08) * pow(1.0 - p, 1.8)
		var f: float = freq
		match shape:
			"rise":
				f = lerpf(freq * 0.72, freq * 1.55, p)
			"fall":
				f = lerpf(freq * 1.45, freq * 0.42, p)
			"laser":
				f = lerpf(freq * 1.25, freq * 0.55, p)
			"boss", "boss_die", "noise_fall":
				f = lerpf(freq * 1.8, freq * 0.45, p)
		var sample: float = _wave_sample(shape, f, t, rng)
		if shape == "level":
			sample = sin(TAU * [freq, freq * 1.25, freq * 1.5][min(2, int(p * 3.0))] * t)
		elif shape == "rescue":
			sample = (sin(TAU * freq * t) + sin(TAU * freq * 1.5 * t) * 0.55) * 0.65
		elif shape == "victory":
			sample = sin(TAU * [freq, freq * 1.25, freq * 1.5, freq * 2.0][min(3, int(p * 4.0))] * t)
		elif shape == "defeat":
			sample = sin(TAU * lerpf(freq, freq * 0.45, p) * t)
		elif shape == "alert" or shape == "pulse":
			sample = sin(TAU * freq * t) * (0.35 + 0.65 * abs(sin(TAU * 7.5 * t)))
		var value: int = int(clampf(sample * env * volume, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, value)
	return _wav(bytes, false)


func _wave_sample(shape: String, freq: float, t: float, rng: RandomNumberGenerator) -> float:
	var sine: float = sin(TAU * freq * t)
	match shape:
		"square", "boss":
			return 1.0 if sine >= 0.0 else -1.0
		"triangle":
			return asin(sine) * (2.0 / PI)
		"noise", "noise_fall", "boss_die":
			return rng.randf_range(-1.0, 1.0) * 0.72 + sine * 0.28
		"chime":
			return sine * 0.7 + sin(TAU * freq * 2.0 * t) * 0.3
	return sine


func _make_music_loop(notes: Array, volume: float, bass_volume: float) -> AudioStreamWAV:
	var seconds: float = 8.0
	var frames: int = int(seconds * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var beat: float = 0.5
	for i in frames:
		var t: float = float(i) / float(MIX_RATE)
		var note_index: int = int(floor(t / beat)) % notes.size()
		var freq: float = float(notes[note_index])
		var gate: float = 0.55 + 0.45 * max(0.0, sin(TAU * 2.0 * t))
		var lead: float = sin(TAU * freq * t) * volume * gate
		var bass: float = sin(TAU * (freq * 0.5) * t) * bass_volume
		var tick: float = 0.0
		if fmod(t, beat) < 0.035:
			tick = sin(TAU * 1200.0 * t) * 0.018
		var fade: float = min(1.0, min(t / 0.12, (seconds - t) / 0.12))
		var value: int = int(clampf((lead + bass + tick) * fade, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, value)
	var stream := _wav(bytes, true)
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream


func _make_shelter_loop() -> AudioStreamWAV:
	var seconds: float = 16.0
	var frames: int = int(seconds * MIX_RATE)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	for i in frames:
		var t: float = float(i) / float(MIX_RATE)
		var phrase_pos: float = fmod(t, 8.0)
		var bar_pos: float = fmod(t, 2.0)
		var chord_index: int = int(floor(t / 4.0)) % 4
		var root: float = [146.875, 164.875, 196.0, 174.125][chord_index]
		var pad_lfo: float = 0.76 + 0.24 * sin(TAU * 0.125 * t)
		var pad: float = (
			sin(TAU * root * t) * 0.046 +
			sin(TAU * root * 1.5 * t) * 0.028 +
			sin(TAU * root * 2.0 * t) * 0.018
		) * pad_lfo
		var purr_gate: float = 0.55 + 0.45 * sin(TAU * 24.0 * t)
		var purr: float = sin(TAU * 48.0 * t + sin(TAU * 4.0 * t) * 0.25) * 0.055 * purr_gate
		var tick: float = 0.0
		if bar_pos < 0.07:
			tick = sin(TAU * 784.0 * t) * 0.032 * (1.0 - bar_pos / 0.07)
		elif fmod(bar_pos, 0.5) < 0.035:
			var local: float = fmod(bar_pos, 0.5)
			tick = sin(TAU * (392.0 + 98.0 * float(chord_index)) * t) * 0.018 * (1.0 - local / 0.035)
		var warmth: float = sin(TAU * 73.5 * t) * 0.018 * (0.5 + 0.5 * sin(TAU * 0.25 * phrase_pos))
		var soft_bell: float = 0.0
		if fmod(phrase_pos + 0.25, 2.0) < 0.09:
			var bell_pos: float = fmod(phrase_pos + 0.25, 2.0)
			soft_bell = sin(TAU * root * 3.0 * t) * 0.020 * (1.0 - bell_pos / 0.09)
		var value: int = int(clampf((pad + purr + tick + warmth + soft_bell) * 1.12, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, value)
	var stream := _wav(bytes, true)
	stream.loop_begin = 0
	stream.loop_end = frames
	return stream


func _wav(bytes: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	return stream
