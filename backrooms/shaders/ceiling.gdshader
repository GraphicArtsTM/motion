shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Подвесной потолок Backrooms: акустическая плитка в металлической
// решётке. Сетка привязана к клетке лабиринта (4 м): 3 плитки поперёк и 5
// вдоль, поэтому центральная плитка всегда под светильником. Рельеф
// плитки — фото крапчатой штукатурки (Poly Haven, CC0, textures/CREDITS.md).
// С порчей (decay чанка) на плитках проступают ржавые кольца протечек,
// плитки желтеют и проседают, а некоторых нет вовсе: на их месте чёрная
// дыра в перекрытие. Светильник никогда не остаётся без плитки.

uniform sampler2D tile_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tile_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tile_color : source_color = vec3(0.86, 0.84, 0.76);
uniform vec3 grid_color : source_color = vec3(0.62, 0.6, 0.54);
uniform vec3 leak_color : source_color = vec3(0.52, 0.38, 0.2);
uniform vec3 void_color : source_color = vec3(0.012, 0.011, 0.01);
uniform float cell = 4.0;
instance uniform float decay : hint_range(0.0, 1.0) = 0.0;

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Базис рельефа по мировым осям: у плоскости касательных нет
	TANGENT = normalize((VIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	vec2 counts = vec2(3.0, 5.0);
	vec2 g = wpos.xz / cell * counts;
	vec2 tile_id = floor(g);
	vec2 in_tile = fract(g);
	vec2 tile_m = cell / counts;
	// Решётка: тонкие полосы по краям плитки, в метрах
	vec2 edge_m = min(in_tile, 1.0 - in_tile) * tile_m;
	float bar = 1.0 - smoothstep(0.012, 0.02, min(edge_m.x, edge_m.y));

	float r = hash(tile_id + 0.37);
	// Центральная плитка клетки — под светильником, её не трогаем
	vec2 in_cell = mod(tile_id, counts);
	bool lamp_tile = in_cell.x == 1.0 && in_cell.y == 2.0;
	bool missing = !lamp_tile && r < 0.015 + 0.09 * decay;

	vec2 tuv = wpos.xz * 0.6;
	vec3 color = tile_color * (0.92 + 0.12 * hash(tile_id + 3.1));
	// Пожелтение и протечки: кольцо ржавой воды вокруг случайной точки плитки
	color = mix(color, color * vec3(0.95, 0.88, 0.72), decay * 0.6 * hash(tile_id + 5.5));
	vec2 leak_c = vec2(hash(tile_id + 1.1), hash(tile_id + 2.2)) * 0.6 + 0.2;
	float leak_r = 0.18 + 0.25 * hash(tile_id + 4.4);
	float dist = length((in_tile - leak_c) * tile_m) + 0.05 * vnoise(wpos.xz * 9.0);
	float has_leak = step(1.0 - (0.04 + 0.4 * decay), hash(tile_id + 8.8));
	float leak_fill = 1.0 - smoothstep(leak_r * 0.8, leak_r, dist);
	float leak_ring = leak_fill * smoothstep(leak_r * 0.55, leak_r * 0.85, dist);
	color = mix(color, leak_color, has_leak * (leak_fill * 0.25 + leak_ring * 0.55));
	color = mix(color, grid_color, bar);

	vec3 arm = texture(tile_arm, tuv).rgb;
	if (missing && bar < 0.5) {
		// Нет плитки: в дыре темно, только кромка соседних чуть видна
		ALBEDO = void_color + vec3(0.02) * vnoise(wpos.xz * 3.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	} else {
		ALBEDO = color;
		NORMAL_MAP = texture(tile_nor, tuv).rgb;
		NORMAL_MAP_DEPTH = mix(0.9, 0.0, bar);
		AO = arm.r;
		ROUGHNESS = mix(arm.g, 0.45, bar);
		METALLIC = bar * 0.4;
	}
}
