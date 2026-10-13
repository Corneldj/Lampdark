// VIS-06: the light pools from received per-tile light, drawn into WorldView's world viewport
// before VIS-05's darkness composite. Coal-black surfaces under each tile's light, in its colour
// class; a custom bilinear between tile centres over sent neighbours only, so no light bleeds into
// an unsent tile (a bite stays a hard notch). Brightness and Lamp Glow (UI-06) touch lit tiles only.
// Normal maps arrive with final art (GDD §14.1).
shader_type canvas_item;

uniform sampler2D light_tex : filter_nearest, repeat_disable;
uniform vec2 tex_origin;
uniform vec2 tex_size;
uniform vec2 view_origin;
uniform vec2 view_size;
uniform vec3 class_colours[8];
uniform vec3 floor_albedo = vec3(1.0);
uniform vec3 wall_albedo = vec3(1.0);
uniform float brightness = 1.0;
uniform float lamp_glow = 0.0;
uniform float max_channel = 1.0;

vec4 texel(vec2 tile) {
	vec2 p = tile - tex_origin;
	if (p.x < 0.0 || p.y < 0.0 || p.x >= tex_size.x || p.y >= tex_size.y) {
		return vec4(0.0);
	}
	return texture(light_tex, (p + 0.5) / tex_size);
}

void fragment() {
	vec2 world = view_origin + UV * view_size;
	vec2 own = floor(world);
	vec4 o = texel(own);
	if (o.b < 0.5) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec2 f = world - vec2(0.5);
		vec2 base = floor(f);
		vec2 fr = f - base;
		float total = 0.0;
		float weight = 0.0;
		for (int dy = 0; dy < 2; dy++) {
			for (int dx = 0; dx < 2; dx++) {
				vec4 t = texel(base + vec2(float(dx), float(dy)));
				if (t.b < 0.5) {
					continue;
				}
				float w = (dx == 1 ? fr.x : 1.0 - fr.x) * (dy == 1 ? fr.y : 1.0 - fr.y);
				total += w * t.r;
				weight += w;
			}
		}
		float light = weight > 1e-6 ? total / weight : o.r;
		int cls = int(o.g * 255.0 + 0.5);
		vec3 albedo = o.a > 0.5 ? wall_albedo : floor_albedo;
		float e = light;
		if (e > 0.0) {
			e = e * brightness;
			e = e + lamp_glow * e * (1.0 - min(e, 1.0));
		}
		vec3 c = albedo * class_colours[clamp(cls, 0, 7)] * e;
		COLOR = vec4(min(c, vec3(max_channel)), 1.0);
	}
}
