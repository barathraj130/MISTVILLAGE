extends SceneTree
## Renders the bus boards (Tamil and English, shaped by Godot's text engine) to PNGs for Blender and the game:
##   godot --path godot -s tools/render_boards.gd -- <out_dir>
## Each board: [file, text, font size, text colour, background colour, width, height]

const BOARDS := [
	["board_route_ta", "கோயம்புத்தூர் - உதகமண்டலம்", 76, Color(0.15, 1.0, 0.35), Color(0.01, 0.01, 0.012), 1400, 150],
	["board_dest_ta", "உதகை", 120, Color(0.15, 1.0, 0.35), Color(0.01, 0.01, 0.012), 700, 170],
	["board_exp_ta", "விரைவு", 96, Color(1.0, 0.12, 0.06), Color(0.01, 0.01, 0.012), 420, 170],
	["board_operator_ta", "கோவை சாலைப் போக்குவரத்து", 72, Color(1, 1, 1), Color(0, 0, 0, 0), 1500, 120],
	["board_via_ta", "மேட்டுப்பாளையம் வழி", 64, Color(1.0, 0.9, 0.2), Color(0.01, 0.01, 0.012), 1200, 110],
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://boards"
	DirAccess.make_dir_recursive_absolute(out)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Tamil Sangam MN", "Tamil MN"])
	font.font_weight = 700
	for b in BOARDS:
		var vp := SubViewport.new()
		vp.size = Vector2i(b[5], b[6])
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var bg := ColorRect.new()
		bg.color = b[4]
		bg.size = Vector2(b[5], b[6])
		vp.add_child(bg)
		var lb := Label.new()
		lb.text = b[1]
		lb.add_theme_font_override("font", font)
		lb.add_theme_font_size_override("font_size", b[2])
		lb.add_theme_color_override("font_color", b[3])
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lb.size = Vector2(b[5], b[6])
		vp.add_child(lb)
		root.add_child(vp)
		await process_frame
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png(out.path_join(b[0] + ".png"))
		print("BOARD ", b[0])
		vp.queue_free()
	quit()
