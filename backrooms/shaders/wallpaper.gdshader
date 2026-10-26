shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Цвета обоев Backrooms
uniform vec3 base_color : source_color = vec3(0.851, 0.753, 0.447); // #D9C072
uniform vec3 pattern_color : source_color = vec3(0.780, 0.671, 0.373); // #C7AB5F
uniform vec3 stain_color : source_color = vec3(0.659, 0.565, 0.376); // #A89060

// Параметры узора
uniform float pattern_scale : hint_range(0.5, 5.0) = 2.5; // Повтор каждые 0.4м
uniform float stripe_width : hint_range(0.05, 0.2) = 0.1; // Ширина полосы 8-12см
uniform float stain_coverage : hint_range(0.0, 0.5) = 0.24;

// Простой hash для шума
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

// FBM для органичности
float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	
	for (int i = 0; i < 3; i++) {
		value += amplitude * noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

// Вертикальные полосы обоев
float vertical_stripes(vec2 uv) {
	float stripes = sin(uv.x * 20.0) * 0.5 + 0.5;
	return smoothstep(0.4, 0.6, stripes);
}

// Пятна сырости (Voronoi-based)
float moisture_stains(vec2 uv) {
	vec2 cell = floor(uv * 2.0);
	vec2 local = fract(uv * 2.0);
	
	float min_dist = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = hash(cell + neighbor) * vec2(1.0, 1.0) + neighbor;
			float dist = length(local - point);
			min_dist = min(min_dist, dist);
		}
	}
	
	return smoothstep(0.3, 0.8, min_dist);
}

void fragment() {
	vec2 uv = UV * pattern_scale;
	
	// Вертикальные полосы
	float stripes = vertical_stripes(uv);
	
	// Добавляем шум для размытия полос
	float detail = fbm(uv * 8.0) * 0.2;
	stripes = mix(stripes, detail, 0.3);
	
	// Базовый цвет с паттерном
	vec3 color = mix(base_color, pattern_color, stripes * 0.3);
	
	// Пятна сырости
	float stains = moisture_stains(uv);
	stains = 1.0 - smoothstep(0.7, 1.0, stains);
	color = mix(color, stain_color, stains * stain_coverage);
	
	// Лёгкие вариации яркости
	float variation = noise(uv * 20.0) * 0.05;
	color += variation;

	// Контактное затемнение у пола: заземляет стены, прячет стык
	float h = clamp(UV.y / 2.9, 0.0, 1.0);
	color *= mix(0.7, 1.0, smoothstep(0.0, 0.22, h));

	// Плинтус: тёмная полоса 12 см вдоль пола
	float baseboard = 1.0 - smoothstep(0.10, 0.13, h);
	color = mix(color, vec3(0.16, 0.14, 0.11), baseboard * 0.9);

	ALBEDO = color;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
}
