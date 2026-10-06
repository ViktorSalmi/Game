shader_type canvas_item;
// Marken: ett enda stort skikt. Biom-masker (linjärt filtrerade) + brus ger mjuka, organiska övergångar.

uniform sampler2D mask1 : filter_linear_mipmap, repeat_disable;   // R vatten, G skog, B bebyggelse, A å
uniform sampler2D mask2 : filter_linear_mipmap, repeat_disable;   // R berg, G myr, B utanför, A sand/torrt
uniform sampler2D elev : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(800.0, 800.0);
uniform vec2 elev_size = vec2(41.0, 41.0);
uniform float relief = 0.012;

varying vec2 cell;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	cell = UV * map_size;
}

void fragment() {
	vec4 m1 = texture(mask1, UV);
	vec4 m2 = texture(mask2, UV);
	if (m2.b > 0.5) {
		discard;
	}
	float n1 = fbm(cell * 0.30);
	float n2 = fbm(cell * 1.6);
	float n3 = vnoise(cell * 7.0);
	float n4 = vnoise(cell * 19.0);
	float detail = 1.0 - smoothstep(0.04, 0.22, length(fwidth(cell)));   // tona ut finbrus när man zoomar ut
	n3 = mix(0.5, n3, detail);
	n4 = mix(0.5, n4, detail);

	// --- mark ---
	vec3 grass_a = vec3(0.34, 0.54, 0.22);
	vec3 grass_b = vec3(0.47, 0.64, 0.27);
	vec3 col = mix(grass_a, grass_b, smoothstep(0.30, 0.70, n1));
	float pn = vnoise(cell * 0.20 + vec2(3.0, 7.0));
	float wheat = smoothstep(0.62, 0.66, pn);
	float meadow = smoothstep(0.42, 0.45, pn) * (1.0 - wheat);
	float rows = mix(0.5, 0.5 + 0.5 * sin(dot(cell, vec2(0.8, 0.6)) * 9.0), detail);
	col = mix(col, vec3(0.74, 0.67, 0.36) * (0.93 + 0.1 * rows), wheat * 0.85);
	col = mix(col, vec3(0.56, 0.67, 0.30), meadow * 0.7);

	float mire = smoothstep(0.42, 0.58, m2.g + (n2 - 0.5) * 0.35);
	vec3 mire_col = mix(vec3(0.40, 0.46, 0.27), vec3(0.30, 0.38, 0.30), n2);
	mire_col = mix(mire_col, vec3(0.16, 0.30, 0.36), smoothstep(0.64, 0.68, fbm(cell * 0.9)) * 0.8);
	col = mix(col, mire_col, mire);

	float rock = smoothstep(0.45, 0.55, m2.r + (n2 - 0.5) * 0.3);
	vec3 rock_col = mix(vec3(0.50, 0.49, 0.46), vec3(0.62, 0.61, 0.58), n3);
	col = mix(col, rock_col, rock);

	float sandm = smoothstep(0.45, 0.55, m2.a + (n2 - 0.5) * 0.3);
	col = mix(col, vec3(0.85, 0.77, 0.55), sandm);

	float fo = smoothstep(0.42, 0.58, m1.g + (n1 - 0.5) * 0.55 + (n2 - 0.5) * 0.25);
	vec3 forest = mix(vec3(0.09, 0.22, 0.11), vec3(0.19, 0.36, 0.17), clamp(n2 * 0.9 + n3 * 0.25, 0.0, 1.0));
	forest *= 0.82 + 0.34 * n4;
	col = mix(col, forest, fo);

	float ur = smoothstep(0.45, 0.55, m1.b + (n2 - 0.5) * 0.18);
	vec3 urban = mix(vec3(0.58, 0.56, 0.50), vec3(0.67, 0.64, 0.58), n3);
	vec3 garden = mix(vec3(0.40, 0.55, 0.28), vec3(0.50, 0.63, 0.32), n3);
	urban = mix(urban, garden, smoothstep(0.38, 0.62, fbm(cell * 0.9 + vec2(5.0, 2.0))) * 0.75);
	col = mix(col, urban, ur);

	// strand
	float wblur = textureLod(mask1, UV, 2.0).r;
	float shore = smoothstep(0.06, 0.34, wblur);
	col = mix(col, vec3(0.80, 0.73, 0.52), shore * 0.75);

	// småskalig variation + relief
	col *= 0.90 + 0.20 * n1;
	col *= 0.94 + 0.12 * n3;
	vec2 e_px = 1.0 / elev_size;
	float e0 = texture(elev, UV).r;
	float ex = texture(elev, UV + vec2(e_px.x, 0.0)).r;
	float ey = texture(elev, UV + vec2(0.0, e_px.y)).r;
	float shade = clamp(1.0 - ((ex - e0) + (ey - e0)) * relief, 0.78, 1.25);
	col *= shade;

	// --- vatten ---
	float w = m1.r + (n1 - 0.5) * 0.34 + (n2 - 0.5) * 0.10;
	float water = smoothstep(0.43, 0.57, w);
	float depth = textureLod(mask1, UV, 3.0).r;
	vec3 shallow = vec3(0.25, 0.58, 0.68);
	vec3 deep = vec3(0.07, 0.27, 0.47);
	vec3 wc = mix(shallow, deep, smoothstep(0.15, 0.85, depth));
	float rip = sin(cell.x * 13.0 + TIME * 1.1 + n2 * 6.0) * sin(cell.y * 10.0 - TIME * 0.8 + n1 * 5.0);
	wc += (rip * 0.025 + pow(max(rip, 0.0), 8.0) * 0.07) * detail;
	float foam = 1.0 - smoothstep(0.0, 0.07, abs(w - 0.5));
	foam *= 0.5 + 0.5 * sin(cell.x * 21.0 + cell.y * 17.0 + TIME * 1.6 + n3 * 8.0);
	wc = mix(wc, vec3(0.92, 0.96, 0.98), clamp(foam, 0.0, 1.0) * 0.55);

	float rv = smoothstep(0.30, 0.48, m1.a + (n2 - 0.5) * 0.25);
	vec3 rc = vec3(0.28, 0.58, 0.72) + rip * 0.03 + pow(max(rip, 0.0), 8.0) * 0.06;

	vec3 outc = mix(col, wc, water);
	outc = mix(outc, rc, rv * (1.0 - water));
	COLOR = vec4(outc, 1.0);
}
