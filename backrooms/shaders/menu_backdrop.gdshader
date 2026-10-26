shader_type canvas_item;

// Фон меню: та же комната, что и в игре, только пустая. Жёлтая стена,
// свет лампы сверху, пыль в воздухе и виньетка — без единой текстуры,
// только математика. Медленное мерцание лампы держит кадр живым.

uniform vec4 deep_color : source_color = vec4(0.032, 0.028, 0.021, 1.0);
uniform vec4 wall_color : source_color = vec4(0.32, 0.27, 0.155, 1.0);
uniform vec4 lamp_color : source_color = vec4(1.0, 0.94, 0.74, 1.0);
uniform float grain_amount : hint_range(0.0, 0.2) = 0.05;
uniform float seam_count : hint_range(4.0, 80.0) = 34.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;

	// Стена: у потолка светлее, к полу уходит в темноту
	float ceiling = smoothstep(0.62, 0.0, uv.y);
	float to_floor = smoothstep(0.42, 1.05, uv.y);
	vec3 col = mix(wall_color.rgb * 0.42, deep_color.rgb, to_floor);
	col += wall_color.rgb * ceiling * 0.5;

	// Пятно лампы: одна панель над кадром, чуть левее центра
	vec2 lamp_uv = (uv - vec2(0.46, -0.02)) * vec2(1.7, 2.4);
	float lamp = exp(-dot(lamp_uv, lamp_uv) * 1.7);
	float flicker = 0.9 + 0.1 * sin(TIME * 16.0) * sin(TIME * 5.3 + 1.7);
	col += lamp_color.rgb * lamp * 0.32 * flicker;

	// Обои: тонкие вертикальные швы и стык полотна поперёк стены
	float seam = abs(fract(uv.x * seam_count + sin(uv.y * 3.0) * 0.15) - 0.5);
	col *= 1.0 - smoothstep(0.47, 0.5, seam) * 0.14;
	col *= 1.0 - smoothstep(0.004, 0.0, abs(uv.y - 0.6)) * 0.2;

	// Пыль и телевизионная строка развёртки
	float dust = hash(floor(uv * vec2(340.0, 190.0)) + floor(TIME * 6.0));
	col += vec3(dust) * grain_amount * (0.3 + ceiling);
	col *= 1.0 + sin(uv.y * 900.0) * 0.012;

	// Виньетка и тёмная кромка сверху под шапку меню
	float vignette = smoothstep(1.05, 0.25, length((uv - 0.5) * vec2(1.2, 1.0)));
	col *= mix(0.3, 1.0, vignette);
	col *= mix(0.55, 1.0, smoothstep(0.0, 0.14, uv.y));

	COLOR = vec4(col, 1.0);
}
