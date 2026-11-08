extends SceneTree
## Text for the trailer's cards and captions, rendered by Godot (HarfBuzz shapes Tamil properly: the vowel signs
## join their letters) onto transparent PNGs the editor lays over the footage. ffmpeg's own text filter may be
## missing or unable to shape Tamil.
##   Godot --path godot --resolution 64x64 -s <this file> -- JOBS.json
## JOBS.json: [{"text", "out", "w", "h", "size", "color": "#rrggbb", "fonts": ["Tamil Sangam MN", ...],
##              "bold": false, "align": "center", "valign": "center"}]
## Each PNG is w × h, the text wrapped inside it with a soft shadow.

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(args[0])) if not args.is_empty() else null
	if not parsed is Array:                         # (a missing or broken job file: say so and stop, don't hang)
		printerr("text_png: no job list in %s" % (args[0] if not args.is_empty() else "(no file given)"))
		quit(1)
		return
	_run(parsed)


func _run(jobs: Array) -> void:
	for j in jobs:
		var vp := SubViewport.new()
		vp.size = Vector2i(int(j["w"]), int(j["h"]))
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var font := SystemFont.new()
		font.font_names = PackedStringArray(j.get("fonts", ["Georgia"]))
		font.font_weight = 700 if j.get("bold", false) else 400
		font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		var ls := LabelSettings.new()
		ls.font = font
		ls.font_size = int(j["size"])
		ls.font_color = Color(str(j.get("color", "#ffffff")))
		ls.shadow_color = Color(0, 0, 0, 0.75)
		ls.shadow_size = maxi(2, int(j["size"]) / 14)
		ls.shadow_offset = Vector2(2, 3)
		ls.line_spacing = int(j["size"]) * 0.2
		var l := Label.new()
		l.label_settings = ls
		l.text = str(j["text"])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = {"left": HORIZONTAL_ALIGNMENT_LEFT, "right": HORIZONTAL_ALIGNMENT_RIGHT}.get(str(j.get("align", "center")), HORIZONTAL_ALIGNMENT_CENTER)
		l.vertical_alignment = {"top": VERTICAL_ALIGNMENT_TOP, "bottom": VERTICAL_ALIGNMENT_BOTTOM}.get(str(j.get("valign", "center")), VERTICAL_ALIGNMENT_CENTER)
		l.position = Vector2(int(j["w"]) * 0.05, 0)
		l.size = Vector2(int(j["w"]) * 0.9, int(j["h"]))
		vp.add_child(l)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(str(j["out"]))
		print("TEXT %s" % j["out"])
		vp.queue_free()
	quit()
