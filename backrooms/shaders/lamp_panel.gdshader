shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Люминесцентная панель Backrooms: рамка + светящийся рассеиватель,
// мерцание и случайно мёртвые панели. Всё процедурно, фаза от позиции ячейки.
uniform vec3 frame_color : source_color = vec3(0.30, 0.29, 0.27);
uniform vec3 lamp_on : source_color = vec3(1.0, 0.96, 0.86);
uniform vec3 lamp_dead : source_color = vec3(0.10, 0.10, 0.09);
uniform float dead_ratio : hint_range(0.0, 1.0) = 0.06;
uniform float emission_energy : hint_range(0.0, 4.0) = 2.2;
// Яркость всего пролёта: часть чанков темнее — там темно и страшно.
// Значение статично (никакой осцилляции: она давала бегущие полосы).
uniform float brightness : hint_range(0.0, 2.0) = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	// Одна фаза и флаг «мёртвая» на ячейку 4×4 м
	vec2 cell = floor(world_pos.xz / 4.0);
	float h = hash12(cell);
	float dead = step(1.0 - dead_ratio, h);

	// Мерцание ВРЕМЕННО заморожено: любая осцилляция яркости давала
	// бегущие полосы. Вернём позже одной «больной» лампой локально.
	float level = brightness;

	vec3 glow = mix(lamp_on * level, lamp_dead, dead);

	// Рамка панели по краям UV
	float inner = step(0.06, UV.x) * step(UV.x, 0.94)
		* step(0.12, UV.y) * step(UV.y, 0.88);
	vec3 color = mix(frame_color, glow, inner);

	ALBEDO = color;
	EMISSION = glow * inner * emission_energy * (1.0 - dead);
	ROUGHNESS = 0.6;
	METALLIC = 0.0;
}
