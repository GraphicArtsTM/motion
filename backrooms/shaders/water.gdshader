shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Вода затопленного сектора (flood.gd): мутная, по щиколотку, дна не видно.
// Непрозрачная намеренно: отражения экрана (SSR) ложатся только на
// непрозрачное — в ней отражаются лампы и стены, рябь от капели их ломает.
// Рябь — две бегущие волны шума и кольца от капель в мировых координатах,
// поэтому гладь сходится на стыках чанков и не повторяется плиткой.

uniform vec3 water_color : source_color = vec3(0.09, 0.085, 0.05);

varying vec3 wpos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float height(vec2 p) {
	float h = vnoise(p * 1.7 + vec2(TIME * 0.11, TIME * 0.07)) * 0.6;
	h += vnoise(p * 4.3 - vec2(TIME * 0.19, -TIME * 0.13)) * 0.3;
	// Кольца от капель: в каждой ячейке 3×3 м своя капля со своим ритмом
	vec2 cell = floor(p / 3.0);
	vec2 drop = (cell + vec2(hash(cell), hash(cell + 7.1))) * 3.0;
	float period = 2.0 + 3.0 * hash(cell + 3.3);
	float age = mod(TIME + hash(cell + 1.9) * period, period);
	float r = length(p - drop);
	h += sin((r - age * 0.9) * 18.0) * exp(-age * 1.4) * smoothstep(age * 0.9 + 0.05, age * 0.9 - 0.3, r) * 0.25;
	return h;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float e = 0.03;
	float h = height(p);
	vec3 n = normalize(vec3(height(p - vec2(e, 0.0)) - height(p + vec2(e, 0.0)), 0.6,
		height(p - vec2(0.0, e)) - height(p + vec2(0.0, e))));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// Плёнка и муть: местами темнее
	ALBEDO = water_color * (0.8 + 0.4 * vnoise(p * 0.4));
	ROUGHNESS = 0.02 + 0.05 * h;
	SPECULAR = 0.8;
	METALLIC = 0.0;
}
