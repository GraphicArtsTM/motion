shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Цвета ковра Backrooms
uniform vec3 base_color : source_color = vec3(0.631, 0.561, 0.420); // #A18F6B
uniform vec3 dark_color : source_color = vec3(0.541, 0.471, 0.345); // #8A7858
uniform vec3 fiber_color : source_color = vec3(0.710, 0.643, 0.502); // #B5A480

// Параметры текстуры
uniform float texture_scale : hint_range(1.0, 5.0) = 3.0;
uniform float wear_amount : hint_range(0.0, 0.5) = 0.25;
uniform float detail_fade_distance : hint_range(5.0, 40.0) = 10.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Hash для шума
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Value noise
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// FBM для ворса
float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amplitude = 0.5;
	
	for (int i = 0; i < octaves; i++) {
		value += amplitude * noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

// Текстура ворса ковра
float carpet_fibers(vec2 uv) {
	// Ворсинки (частота умеренная, чтобы не алиасило вдали)
	float fibers = fbm(uv * 6.0, 4);
	
	// Диагональные следы от пылесоса
	float diagonal = sin((uv.x + uv.y * 0.5) * 12.0) * 0.5 + 0.5;
	diagonal = smoothstep(0.3, 0.7, diagonal) * 0.15;
	
	return mix(fibers, diagonal, 0.4);
}

// Потёртости и грязь
float wear_pattern(vec2 uv) {
	float wear = fbm(uv * 2.0, 3);
	wear = smoothstep(0.4, 0.7, wear);
	
	// Усиливаем грязь по краям (имитация стен)
	float edge_dirt = min(
		smoothstep(0.0, 0.2, uv.x) * smoothstep(1.0, 0.8, uv.x),
		smoothstep(0.0, 0.2, uv.y) * smoothstep(1.0, 0.8, uv.y)
	);
	edge_dirt = 1.0 - edge_dirt * 0.5;
	
	return wear * edge_dirt;
}

void fragment() {
	vec2 uv = UV * texture_scale;
	
	// Мелкий detail гаснет с расстоянием — иначе алиасинг в кашу
	float dist = distance(CAMERA_POSITION_WORLD, world_pos);
	float fade = exp(-dist / detail_fade_distance);
	
	// Текстура ворса
	float fibers = carpet_fibers(uv);
	
	// Базовый цвет с ворсом
	vec3 color = mix(base_color, fiber_color, fibers * 0.3 * fade);
	
	// Потёртости (низкочастотные, видны всегда)
	float wear = wear_pattern(uv);
	color = mix(color, dark_color, wear * wear_amount);

	// Затемнение-бухта вдоль стен: глубина + маскировка стыков
	vec2 cell_uv = fract(world_pos.xz / 4.0) * 4.0;
	float edge = min(min(cell_uv.x, 4.0 - cell_uv.x), min(cell_uv.y, 4.0 - cell_uv.y));
	color *= mix(0.78, 1.0, smoothstep(0.0, 0.6, edge));
	
	// Мелкий шум для реалистичности вблизи
	float micro_detail = noise(uv * 30.0) * 0.04 * fade;
	color += micro_detail;
	
	ALBEDO = color;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
	
	// Лёгкая normal map для ворса вблизи, вдали — ровная
	vec3 normal_detail = vec3(
		(noise(uv * 20.0 + vec2(0.1, 0.0)) - 0.5) * fade,
		(noise(uv * 20.0 + vec2(0.0, 0.1)) - 0.5) * fade,
		1.0
	) * 0.3;
	NORMAL_MAP = normalize(normal_detail);
}
