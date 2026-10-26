shader_type canvas_item;

// Пост-обработка нагрудной камеры: так выглядит запись цифрового бодикама.
// Широкоугольник «рыбий глаз», цифровая матрица (шум в тенях, лесенка и
// квадраты сжатия в тёмном, перешарп с ореолами, пересвет ламп), шторка
// строк на повороте и страх (dread) с сердцебиением и сбоями кодека.
// Читает экран, поэтому лежит нижним слоем HUD — интерфейс поверх чистый.

// Рыбий глаз: 0 — обычная перспектива, 1 — равнопромежуточная проекция.
// Камера рендерит прямолинейно с углом src_fov (по вертикали, его кормит
// camera_lens.gd), а шейдер перекладывает кадр так, что углы экрана остаются
// углами: края сжимаются, центр крупнее, прямые гнутся — главная примета
uniform float fisheye : hint_range(0.0, 1.0) = 0.75;
uniform float src_fov : hint_range(30.0, 150.0) = 100.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.4;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.035;
uniform float aberration : hint_range(0.0, 0.01) = 0.0016;
uniform float lens_dirt : hint_range(0.0, 1.0) = 0.35;
// Перешарп матрицы: светлые ореолы на кромках, как у любой бодикамеры
uniform float sharpen : hint_range(0.0, 2.0) = 0.7;
// Квадраты сжатия 8×8 в тёмных ровных местах — кодек экономит на тенях
uniform float blockiness : hint_range(0.0, 1.0) = 0.55;
uniform float saturation : hint_range(0.0, 1.5) = 0.8;
uniform float contrast : hint_range(0.5, 2.0) = 1.08;
// 0 — спокойно, 1 — сущность вплотную: кадр ведёт, кодек сыпется, тьма дышит
uniform float dread : hint_range(0.0, 1.0) = 0.0;
// Оптика нагрудной камеры, кормит camera_lens.gd: motion — насколько кадр
// уехал за кадр (доли экрана), shutter — перекос строк от поворота
uniform vec2 motion = vec2(0.0);
uniform float shutter = 0.0;
// Усиление матрицы: camera_lens поднимает его на включении камеры, потом
// даёт едва дышать — так ведёт себя автоусиление
uniform float gain : hint_range(0.5, 4.0) = 1.0;
// Часы записи: их ведёт camera_lens только пока игра идёт, поэтому на паузе
// шум и сбои стоят вместе с застывшим кадром
uniform float tape_time = 0.0;
// Корпус камеры по краям кадра: тёмная рамка со скруглёнными углами, как
// в Bodycam. Сдвигается от тряски (border_shift кормит camera_lens) и
// чуть подсвечивается, когда в кадре светло
uniform float border_strength : hint_range(0.0, 1.0) = 0.85;
uniform vec2 border_shift = vec2(0.0);
// Лицо сущности, как на «отредактированной» записи: центр в координатах
// прямолинейного рендера и радиус в долях высоты кадра (0 — нет лица).
// Кормит face_redact.gd
uniform vec2 face_uv = vec2(0.5);
uniform float face_r = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
// Тот же экран с мипами: последний уровень — средняя яркость кадра
uniform sampler2D screen_mip : hint_screen_texture, filter_linear_mipmap, repeat_disable;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Экранная точка -> откуда брать её из прямолинейного рендера.
// p — координаты от центра в долях высоты кадра (верх кадра на 0.5)
vec2 lens_uv(vec2 uv, float aspect, float k) {
	vec2 p = (uv - vec2(0.5)) * vec2(aspect, 1.0);
	float r = length(p);
	if (r < 0.00001 || k <= 0.0) {
		return uv;
	}
	// Фокус прямолинейного рендера и рыбьего глаза, у которого угол
	// кадра попадает ровно в угол экрана — поля не обрезаются и не чернеют
	float f_rect = 0.5 / tan(radians(src_fov) * 0.5);
	float r_corner = 0.5 * sqrt(aspect * aspect + 1.0);
	float f_fish = r_corner / atan(r_corner / f_rect);
	float r_src = f_rect * tan(min(r / f_fish, 1.55));
	p *= mix(r, r_src, k) / r;
	return p / vec2(aspect, 1.0) + vec2(0.5);
}

vec3 sample_rgb(vec2 u) {
	return texture(screen_tex, clamp(u, vec2(0.0), vec2(1.0))).rgb;
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 dir = SCREEN_UV - vec2(0.5);
	float r2 = dot(dir, dir);

	// Сердцебиение: удар, потом тишина — и снова
	float beat = pow(0.5 + 0.5 * sin(tape_time * 4.6), 4.0);
	float tremble = dread * (0.0012 + 0.0018 * beat);

	// Объектив: под страхом стекло ещё и чуть «дышит» сильнее
	vec2 uv = lens_uv(SCREEN_UV, aspect, clamp(fisheye + dread * 0.08, 0.0, 1.0));
	uv += vec2(sin(uv.y * 40.0 + tape_time * 2.3),
		cos(uv.x * 37.0 + tape_time * 1.7)) * tremble;

	// Лицо сущности — крупными квадратами: все отсчёты ниже берут один
	// цвет на квадрат. Считаем в пространстве рендера, поэтому квадраты
	// гнутся вместе с объективом, как на настоящей записи
	vec2 face_d = (uv - face_uv) * vec2(aspect, 1.0);
	if (face_r > 0.0 && length(face_d) < face_r) {
		float cell = max(face_r / 3.5, px.y * 4.0);
		vec2 q = uv * vec2(aspect, 1.0);
		uv = (floor(q / cell) + vec2(0.5)) * cell / vec2(aspect, 1.0);
	}

	// Сбои кодека под страхом: полосы по 16 строк съезжают целиком —
	// так рассыпается поток, когда кодек не успевает
	float band_row = floor(FRAGCOORD.y / 16.0);
	float glitch = step(1.0 - dread * dread * 0.12,
		hash(vec2(band_row, floor(tape_time * 12.0))));
	uv.x += glitch * (hash(vec2(band_row, floor(tape_time * 12.0) + 3.0)) - 0.5) * 0.08;

	// Шторка: строки матрицы сняты в разное время — на повороте кадр кренит
	uv.x += shutter * (uv.y - 0.5) * 2.0;

	// Смаз движения: пять отсчётов вдоль вектора скорости кадра
	vec3 col = vec3(0.0);
	for (int i = 0; i < 5; i++) {
		float t = float(i) * 0.25;
		col += sample_rgb(uv - motion * t) * (1.0 - 0.6 * t);
	}
	col /= 3.5;

	// Хроматика к краям широкоугольника: красный и синий одним отсчётом
	// вне цикла смаза — расхождение каналов видно на кромках, не в смазе
	vec2 off = dir * r2 * (aberration + dread * 0.0026) * 24.0;
	vec3 center = sample_rgb(uv);
	col.r += sample_rgb(uv + off).r - center.r;
	col.b += sample_rgb(uv - off).b - center.b;
	if (glitch > 0.5) {
		col.r = sample_rgb(uv + vec2(0.012, 0.0)).r;
	}

	// Перешарп: исходник минус размытый — светлые ореолы на кромках
	vec3 blur = (sample_rgb(uv + vec2(px.x, 0.0) * 1.5) + sample_rgb(uv - vec2(px.x, 0.0) * 1.5)
		+ sample_rgb(uv + vec2(0.0, px.y) * 1.5) + sample_rgb(uv - vec2(0.0, px.y) * 1.5)) * 0.25;
	col += (center - blur) * sharpen;

	float lum = dot(col, vec3(0.299, 0.587, 0.114));

	// Квадраты сжатия: в тёмном и ровном кодек сводит блок 8×8 к одному цвету
	vec2 block_screen = (floor(FRAGCOORD.xy / 8.0) * 8.0 + vec2(4.0)) * px;
	vec3 block_col = sample_rgb(lens_uv(block_screen, aspect, fisheye));
	float block_lum = dot(block_col, vec3(0.299, 0.587, 0.114));
	float flat_dark = (1.0 - smoothstep(0.0, 0.3, lum))
		* (1.0 - smoothstep(0.0, 0.05, abs(lum - block_lum)));
	col = mix(col, block_col, flat_dark * blockiness);

	// Цвет цифровой записи под люминесцентными лампами: чуть выцвел, ушёл
	// в жёлто-зелёный, чёрное молочное — сжатое видео не держит глубоких теней
	lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, saturation * mix(1.0, 0.55, dread));
	col *= vec3(1.04, 1.02, 0.86);
	col = (col - 0.5) * contrast + 0.5;
	col = max(col, vec3(0.0)) * 0.97 + vec3(0.028, 0.03, 0.026);

	// Пересвет: матрица клипует лампы в белое и отдаёт ореолом
	float halo = pow(smoothstep(0.65, 1.0, lum), 2.0);
	col += vec3(0.06, 0.06, 0.05) * halo;

	// Разводы на стекле: бодикам носят на груди, объектив вечно захватан
	vec2 dirt_cell = floor(SCREEN_UV * 7.0);
	if (hash(dirt_cell) > 0.955) {
		vec2 inside = fract(SCREEN_UV * 7.0) - vec2(0.5);
		col *= 1.0 - lens_dirt * 0.25 * smoothstep(0.45, 0.05,
			length(inside * vec2(1.0, 1.6)));
	}

	// Лесенка уровней в тенях: восьмибитному потоку их не хватает
	float shadow = 1.0 - smoothstep(0.0, 0.25, lum);
	vec3 banded = floor(col * 48.0 + 0.5) / 48.0;
	col = mix(col, banded, shadow * 0.35);

	// Средняя яркость кадра — последний мип экрана: ей подсвечена рамка,
	// и от неё же зависит, насколько матрица тянет шум
	float avg = dot(textureLod(screen_mip, vec2(0.5), 10.0).rgb, vec3(0.299, 0.587, 0.114));

	// Корпус камеры: скруглённый прямоугольник чуть шире кадра. В покое
	// видны только тёмные углы, на тряске рамка заходит в кадр краем
	vec2 bp = (SCREEN_UV - vec2(0.5) - border_shift) * vec2(aspect, 1.0);
	vec2 half_size = vec2(aspect * 0.5, 0.5) + vec2(0.012);
	float corner = 0.16;
	vec2 bq = abs(bp) - half_size + vec2(corner);
	float sdf = length(max(bq, vec2(0.0))) + min(max(bq.x, bq.y), 0.0) - corner;
	float housing = smoothstep(-0.03, 0.006, sdf) * border_strength;
	col = mix(col, vec3(0.012, 0.011, 0.01) + vec3(0.06, 0.055, 0.045) * avg, housing);

	// Виньетка широкоугольника; от страха сжимается и дышит
	float vig = 1.0 - smoothstep(0.35, 1.0, length(dir * vec2(aspect, 1.0)) / (0.5 * aspect + 0.2));
	col *= mix(1.0, vig, clamp(vignette_strength + dread * (0.25 + 0.1 * beat), 0.0, 1.0));
	col *= 1.0 - dread * (0.07 + 0.07 * beat);

	// Цифровой шум матрицы: яркостный и цветной, каждый кадр новый. В тенях
	// и в тёмном кадре (автоусиление тянет сигнал) его заметно больше
	float iso = mix(1.0, 2.4, 1.0 - smoothstep(0.04, 0.2, avg));
	vec2 seed = FRAGCOORD.xy + vec2(fract(tape_time * 13.0) * 271.0, fract(tape_time * 7.0) * 173.0);
	float n_luma = hash(seed) - 0.5;
	vec3 n_chroma = vec3(hash(seed + 17.1), hash(seed + 41.7), hash(seed + 73.3)) - 0.5;
	float shadow_noise = 0.5 + 1.5 * (1.0 - smoothstep(0.0, 0.5, lum));
	col += (vec3(n_luma) + n_chroma * 0.7) * grain_amount * shadow_noise * iso
		+ vec3(n_luma) * dread * 0.06;

	// Автоусиление последним: на включении камеры кадр пересвечен,
	// потом матрица съезжает в норму
	col *= gain;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
