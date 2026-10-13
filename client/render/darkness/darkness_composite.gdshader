// VIS-05: the darkness composite, the last pass of the frame. Every pixel outside the drawn-tile
// mask, outside the analytic cone (straight edges from the miner, hard, never feathered) or outside
// the view is written as exactly (0, 0, 0). Inside, the picture is floored at vision.min_drawn_level,
// so exact black only ever means "no data". Everything before it (VIS-06's light pool with Brightness
// and Lamp Glow; bloom, a stand-in uniform here until a bloom pass exists) cannot reach the black:
// the mask is applied after them.
shader_type canvas_item;

uniform sampler2D mask : filter_nearest, repeat_disable;
uniform vec2 mask_origin;   // tile coordinate of texel (0, 0)
uniform vec2 mask_size;     // texels
uniform vec2 view_origin;   // tile coordinate of the screen's top-left
uniform vec2 view_size;     // tiles across and down the screen
uniform vec2 miner;         // the predicted own position, tiles
uniform vec2 facing_dir;    // the predicted facing, a unit vector
uniform float cos_half;     // cos(cone / 2)
uniform float floor_level;  // vision.min_drawn_level / 255
uniform float bloom = 0.0;
uniform bool black_mode = false;

void fragment() {
	vec2 world = view_origin + UV * view_size;
	vec3 col = texture(TEXTURE, UV).rgb;
	col = col + vec3(bloom * 0.2);
	vec2 cell = floor(world) - mask_origin;
	bool in_mask = cell.x >= 0.0 && cell.y >= 0.0 && cell.x < mask_size.x && cell.y < mask_size.y
		&& texture(mask, (cell + 0.5) / mask_size).r > 0.5;
	vec2 v = world - miner;
	float len_sq = dot(v, v);
	float d = dot(v, facing_dir);
	bool in_cone = len_sq < 1e-8 || (d >= 0.0 && d * d >= cos_half * cos_half * len_sq);
	bool in_view = world.x >= view_origin.x && world.y >= view_origin.y
		&& world.x <= view_origin.x + view_size.x && world.y <= view_origin.y + view_size.y;
	if (black_mode || !in_mask || !in_cone || !in_view) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		COLOR = vec4(max(col, vec3(floor_level)), 1.0);
	}
}
