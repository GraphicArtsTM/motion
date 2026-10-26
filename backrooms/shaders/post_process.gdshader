shader_type canvas_item;

// Пост-обработка хоррора: цветокоррекция «больного» кадра, телевизор —
// развёртка, полоса записи, шум головки, бочка объектива, пыль на стекле,
// виньетка и страх (dread) с сердцебиением. Читает экран, поэтому лежит
// нижним слоем HUD — интерфейс поверх чистый.

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.7;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.05;
uniform float aberration : hint_range(0.0, 0.01) = 0.0016;
uniform float scanline_amount : hint_range(0.0, 0.5) = 0.025;
uniform float lens_dirt : hint_range(0.0, 1.0) = 0.5;
uniform float barrel : hint_range(0.0, 0.2) = 0.03;
uniform float saturation : hint_range(0.0, 1.5) = 0.78;
uniform float contrast : hint_range(0.5, 2.0) = 1.14;
// 0 — спокойно, 1 — сущность вплотную: кадр ведёт, рвёт и дышит темнотой
uniform float dread : hint_range(0.0, 1.0) = 0.0;
// Оптика нагрудной камеры, кормит camera_lens.gd: motion — насколько кадр
// уехал за кадр (доли экрана), shutter — перекос строк от поворота
uniform vec2 motion = vec2(0.0);
uniform float shutter = 0.0;
// Усиление матрицы: camera_lens поднимает его на включении камеры, потом
// даёт едва дышать — так ведёт себя автоусиление дешёвой камеры
uniform float gain : hint_range(0.5, 4.0) = 1.0;
// Часы ленты: их ведёт camera_lens только пока игра идёт, поэтому на паузе
// зерно, полоса и выпадения строк стоят вместе с застывшим кадром
uniform float tape_time = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - vec2(0.5);
	float r2 = dot(dir, dir);

	// Сердцебиение: удар, потом тишина — и снова
	float beat = pow(0.5 + 0.5 * sin(tape_time * 4.6), 4.0);
	float tremble = dread * (0.0012 + 0.0018 * beat);

	// Бочка объектива: стекло чуть ведёт и сильнее от страха
	uv = vec2(0.5) + dir * (1.0 + barrel * (1.0 + dread * 1.5) * r2 * 2.0);
	uv += vec2(sin(uv.y * 40.0 + tape_time * 2.3),
		cos(uv.x * 37.0 + tape_time * 1.7)) * tremble;

	// Телевизор: полоса записи медленно ползёт по кадру и всегда чуть ведёт
	// строки. Спокойная — на треть силы; под страхом лента рвётся сильнее.
	// Период по uv.y — целый, поэтому полоса есть в кадре всегда, без провала
	float tv = 0.3 + dread;
	float band = fract(uv.y - tape_time * 0.09);
	float band_line = 1.0 - smoothstep(0.0, 0.035, band);
	float dropout = step(1.0 - (0.0006 + dread * 0.02),
		hash(vec2(floor(uv.y * 260.0), floor(tape_time * 18.0))));
	uv.x += (band_line * tv * 0.004 + dropout * 0.02) * (0.5 + dread);

	// Шум головки внизу кадра: у VHS там всегда рябит, а строки дёргаются.
	// SCREEN_UV.y = 0 — верх экрана, поэтому «низ» — это y около единицы
	float head = smoothstep(0.975, 1.0, uv.y);
	uv.x += head * (hash(vec2(floor(uv.y * 320.0), floor(tape_time * 30.0)))
		- 0.5) * 0.012;

	// Дрожь строк: каждая строка ленты плывёт на доли пикселя
	uv.x += (hash(vec2(floor(uv.y * 220.0), floor(tape_time * 24.0))) - 0.5) * 0.0012;

	// Шторка: строки кадра сняты в разное время — на повороте кадр кренит
	uv += vec2(shutter * (uv.y - 0.5) * 2.0, 0.0);

	// Смаз движения и хроматика одним проходом: пять отсчётов вдоль вектора
	// скорости кадра, а к краям — с расхождением каналов (стекло объектива).
	// По горизонтали каналы сдвинуты сильнее: у ленты цвет отстаёт от яркости
	vec2 off = dir * r2 * (aberration + dread * 0.0026) * 40.0
		+ vec2(0.0012, 0.0) * (0.35 + r2);
	vec3 col = vec3(0.0);
	for (int i = 0; i < 5; i++) {
		float t = float(i) * 0.25;
		float w = 1.0 - 0.6 * t;
		vec2 u = clamp(uv - motion * t, vec2(0.0), vec2(1.0));
		col.r += texture(screen_tex, clamp(u + off, vec2(0.0), vec2(1.0))).r * w;
		col.g += texture(screen_tex, u).g * w;
		col.b += texture(screen_tex, clamp(u - off, vec2(0.0), vec2(1.0))).b * w;
	}
	col /= 3.5;

	// Больной свет: выцветание, жёлто-зелёный сдвиг, давленые тени и грязь в них
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, saturation * mix(1.0, 0.55, dread));
	col *= vec3(1.06, 1.0, 0.84);
	col = clamp((col - 0.055) * contrast + 0.02, 0.0, 1.0);
	float dark = 1.0 - smoothstep(0.0, 0.5, lum);
	col += vec3(0.005, 0.007, 0.014) * dark;
	col += vec3(0.02, 0.032, 0.0) * dark * dark;

	// Пересвет от ламп: дешёвый объектив отдаёт яркое узким ореолом.
	// Порог высокий — туман и светлые стены не должны светиться все разом
	float halo = pow(smoothstep(0.7, 1.0, lum), 2.0);
	col += vec3(0.045, 0.04, 0.026) * halo;

	// Пыль и разводы на стекле объектива: редкие мягкие пятна
	vec2 dirt_cell = floor(uv * 9.0);
	if (hash(dirt_cell) > 0.965) {
		vec2 inside = fract(uv * 9.0) - vec2(0.5);
		col *= 1.0 - lens_dirt * 0.3 * smoothstep(0.45, 0.05,
			length(inside * vec2(1.0, 1.6)));
	}

	// Матрица не тянет тёмное: в тенях появляется лесенка уровней, как на
	// дешёвой записи. Порог узкий — на тумане и стенах её быть не должно
	float shadow = 1.0 - smoothstep(0.0, 0.25, lum);
	vec3 banded = floor(col * 40.0 + 0.5) / 40.0;
	col = mix(col, banded, shadow * 0.22);

	// Полоса и низ кадра светятся и шумят поверх картинки — как на ленте
	col += band_line * tv * 0.035;
	col += head * (hash(vec2(floor(uv.y * 320.0), floor(tape_time * 30.0)))
		- 0.5) * 0.12;

	// Развёртка: каждая вторая строка чуть темнее
	col *= 1.0 - scanline_amount * (0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159));

	// Виньетка сжимается от страха и дышит вместе с ним
	float vig = smoothstep(1.28, 0.28, length(dir) * 1.35);
	col *= mix(1.0, vig, clamp(vignette_strength + dread * (0.2 + 0.1 * beat), 0.0, 1.0));
	col *= 1.0 - dread * (0.07 + 0.07 * beat);

	// Зерно плёнки оживает каждый кадр и сильнее шумит в тенях
	float n = hash(FRAGCOORD.xy + vec2(fract(tape_time * 13.0) * 271.0,
		fract(tape_time * 7.0) * 173.0));
	float shadow_grain = 1.0 - smoothstep(0.0, 0.6, lum);
	col += (n - 0.5) * (grain_amount * (0.7 + 1.1 * shadow_grain) + dread * 0.07);

	// Автоусиление последним: на включении камеры кадр пересвечен,
	// потом матрица съезжает в норму
	col *= gain;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
