shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Цвета потолочных плиток Backrooms
uniform vec3 tile_color : source_color = vec3(0.922, 0.910, 0.878); // #EBE8E0
uniform vec3 grid_color : source_color = vec3(0.784, 0.769, 0.729); // #C8C4BA
uniform vec3 stain_color : source_color = vec3(0.831, 0.812, 0.745); // #D4CFBE

// Параметры плиток
uniform float tile_size : hint_range(0.3, 1.0) = 0.6; // 60см × 60см
uniform float grid_width : hint_range(0.005, 0.02) = 0.01; // 1см швы
uniform float stain_coverage : hint_range(0.0, 0.5) = 0.3; // 30% пятен

// Hash
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Noise
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

// FBM
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

// Сетка плиток
float tile_grid(vec2 uv, out vec2 tile_id) {
	vec2 scaled = uv / tile_size;
	tile_id = floor(scaled);
	vec2 tile_uv = fract(scaled);
	
	// Швы между плитками
	float grid_half = grid_width * 0.5 / tile_size;
	float grid_x = smoothstep(0.0, grid_half, tile_uv.x) * smoothstep(0.0, grid_half, 1.0 - tile_uv.x);
	float grid_y = smoothstep(0.0, grid_half, tile_uv.y) * smoothstep(0.0, grid_half, 1.0 - tile_uv.y);
	
	return grid_x * grid_y;
}

// Пятна от влаги на плитке
float moisture_stains(vec2 tile_id, vec2 tile_uv) {
	// Случайное пятно на плитке
	float has_stain = step(0.7, hash(tile_id));
	
	if (has_stain < 0.5) return 0.0;
	
	// Форма пятна (неровная)
	vec2 stain_center = vec2(hash(tile_id * 1.1), hash(tile_id * 2.3)) * 0.6 + 0.2;
	float dist = length(tile_uv - stain_center);
	
	float stain_shape = fbm(tile_uv * 8.0 + tile_id, 2);
	float stain = smoothstep(0.4, 0.1, dist + stain_shape * 0.1);
	
	return stain;
}

// Текстура поверхности плитки
float tile_surface(vec2 uv) {
	// Мелкие отверстия (минеральная плита)
	float holes = fbm(uv * 100.0, 4);
	holes = smoothstep(0.55, 0.65, holes) * 0.08;
	
	return holes;
}

void fragment() {
	vec2 uv = UV * 1.67; // Масштаб для плиток 0.6м
	
	vec2 tile_id;
	float grid = tile_grid(uv, tile_id);
	
	// UV внутри плитки
	vec2 tile_uv = fract(uv / tile_size);
	
	// Вариации яркости между плитками
	float tile_variation = hash(tile_id) * 0.05;
	
	// Базовый цвет плитки
	vec3 color = tile_color + tile_variation;
	
	// Пятна от влаги
	float stains = moisture_stains(tile_id, tile_uv);
	color = mix(color, stain_color, stains * stain_coverage);
	
	// Текстура поверхности
	float surface = tile_surface(uv);
	color -= surface;
	
	// Сетка (швы)
	color = mix(grid_color, color, grid);
	
	ALBEDO = color;
	ROUGHNESS = 0.8;
	METALLIC = 0.0;
}
