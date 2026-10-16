extends SceneTree
## Lettered boards for the street props (tea stall boards, flex banners, shop shade cloths, small signs): Tamil
## first, English second, fictional names, drawn by Godot so Tamil is shaped correctly.
##   godot --path godot -s tools/street_boards.gd -- <out_dir>
## Each: [file, width, height, background, [ [text, font(0 ta / 1 en), size, colour, y 0..1], ... ]]

const BOARDS := [
	["stall_tea_1", 1024, 256, Color(0.95, 0.75, 0.05), [["முருகன் டீ ஸ்டால்", 0, 92, Color(0.6, 0.05, 0.03), 0.42],
		["MURUGAN TEA STALL", 1, 50, Color(0.1, 0.1, 0.4), 0.82]]],
	["stall_tea_2", 1024, 256, Color(0.1, 0.35, 0.65), [["அன்னை டீ கடை", 0, 96, Color(1, 1, 1), 0.42],
		["ANNAI TEA & SNACKS", 1, 48, Color(1, 0.9, 0.2), 0.82]]],
	["flex_sale", 1024, 512, Color(0.95, 0.85, 0.15), [["ஆடி தள்ளுபடி", 0, 120, Color(0.75, 0.05, 0.05), 0.3],
		["50% OFF", 1, 140, Color(0.1, 0.15, 0.5), 0.66], ["கோவை சில்க்ஸ் · KOVAI SILKS", 0, 44, Color(0.2, 0.2, 0.2), 0.9]]],
	["flex_tuition", 1024, 512, Color(0.15, 0.45, 0.25), [["டியூஷன் சென்டர்", 0, 110, Color(1, 1, 1), 0.3],
		["ADMISSION OPEN", 1, 96, Color(1, 0.9, 0.2), 0.62], ["X · XII · NEET", 1, 52, Color(1, 1, 1), 0.88]]],
	["flex_wedding", 1024, 512, Color(0.75, 0.1, 0.25), [["திருமண வாழ்த்துக்கள்", 0, 96, Color(1, 0.9, 0.3), 0.32],
		["செல்வம் ♥ பிரியா", 0, 88, Color(1, 1, 1), 0.66], ["HAPPY WEDDING", 1, 44, Color(1, 0.9, 0.3), 0.9]]],
	["shade_textiles", 1024, 160, Color(0.8, 0.1, 0.08), [["ராஜா டெக்ஸ்டைல்ஸ் · RAJA TEXTILES", 0, 70, Color(1, 1, 1), 0.52]]],
	["shade_jewel", 1024, 160, Color(0.08, 0.2, 0.55), [["லட்சுமி ஜுவல்லரி · LAKSHMI JEWELLERY", 0, 62, Color(1, 0.85, 0.2), 0.52]]],
	["shade_fancy", 1024, 160, Color(0.1, 0.5, 0.2), [["மீனா பேன்சி ஸ்டோர் · MEENA FANCY", 0, 64, Color(1, 1, 1), 0.52]]],
	["sign_school", 512, 512, Color(1, 1, 1), [["பள்ளி", 0, 110, Color(0.1, 0.1, 0.1), 0.6], ["SCHOOL", 1, 70, Color(0.1, 0.1, 0.1), 0.85]]],
	["sign_noparking", 512, 512, Color(0.1, 0.25, 0.65), [["P", 1, 280, Color(1, 1, 1), 0.52]]],
	["shrine_board", 512, 160, Color(0.85, 0.15, 0.05), [["ஸ்ரீ விநாயகர் ஆலயம்", 0, 52, Color(1, 0.9, 0.3), 0.55]]],
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://boards"
	DirAccess.make_dir_recursive_absolute(out)
	var ta := SystemFont.new()
	ta.font_names = PackedStringArray(["Tamil Sangam MN", "Tamil MN"])
	ta.font_weight = 700
	var en := SystemFont.new()
	en.font_names = PackedStringArray(["Arial Black", "Arial"])
	for b in BOARDS:
		var vp := SubViewport.new()
		vp.size = Vector2i(b[1], b[2])
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var c := Control.new()
		c.size = Vector2(b[1], b[2])
		var bd: Array = b
		c.draw.connect(func():
			c.draw_rect(Rect2(0, 0, bd[1], bd[2]), bd[3])
			c.draw_rect(Rect2(6, 6, bd[1] - 12, bd[2] - 12), Color(1, 1, 1, 0.5), false, 4.0)
			for line in bd[4]:
				var f: Font = ta if line[1] == 0 else en
				var w := f.get_string_size(line[0], HORIZONTAL_ALIGNMENT_LEFT, -1, line[2]).x
				var scale := minf(1.0, (bd[1] - 40) / maxf(w, 1.0))
				var size := int(line[2] * scale)
				w = f.get_string_size(line[0], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
				c.draw_string(f, Vector2((bd[1] - w) * 0.5, bd[2] * line[4] + size * 0.35), line[0],
					HORIZONTAL_ALIGNMENT_LEFT, -1, size, line[3]))
		vp.add_child(c)
		root.add_child(vp)
		for _i in 3:
			await process_frame
			await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(out.path_join(b[0] + ".png"))
		print("BOARD ", b[0])
		vp.queue_free()
	quit()
