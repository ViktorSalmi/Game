shader_type canvas_item;
// Stadsområden: färgade ytor med tydliga gränslinjer. R-kanalen i `ids` = stadsnummer (0 = ingen).

uniform sampler2D ids : filter_nearest, repeat_disable;
uniform vec2 map_size = vec2(384.0, 384.0);
uniform float fill_alpha = 0.09;
uniform float border_alpha = 0.95;

vec3 town_color(float id) {
	float h = fract(id * 0.61803);
	vec3 k = vec3(5.0, 3.0, 1.0);
	vec3 p = abs(fract(vec3(h) + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), 0.7);
}

void fragment() {
	vec2 c = UV * map_size;
	vec2 f = fract(c);
	float id = texture(ids, UV).r * 255.0;
	vec2 px = 1.0 / map_size;
	float nl = texture(ids, UV - vec2(px.x, 0.0)).r * 255.0;
	float nr = texture(ids, UV + vec2(px.x, 0.0)).r * 255.0;
	float nu = texture(ids, UV - vec2(0.0, px.y)).r * 255.0;
	float nd = texture(ids, UV + vec2(0.0, px.y)).r * 255.0;
	float w = clamp(length(fwidth(c)) * 1.6, 0.05, 0.45);
	float edge = 0.0;
	if (abs(id - nl) > 0.5 && f.x < w) edge = 1.0;
	if (abs(id - nr) > 0.5 && f.x > 1.0 - w) edge = 1.0;
	if (abs(id - nu) > 0.5 && f.y < w) edge = 1.0;
	if (abs(id - nd) > 0.5 && f.y > 1.0 - w) edge = 1.0;
	if (id < 0.5) {
		discard;
	}
	vec3 col = town_color(id);
	vec4 o = vec4(col, fill_alpha);
	if (edge > 0.5) {
		o = vec4(col * 0.55, border_alpha);
	}
	COLOR = o;
}
