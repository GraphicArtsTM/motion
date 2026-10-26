shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Обои Backrooms. Фактура — фото старых обоев (Poly Haven, CC0, см.
// textures/CREDITS.md): из неё берём только рельеф, шероховатость и
// относительную яркость, а цвет — фирменный жёлтый с выцветшим печатным
// узором. Поверх — порча в мировых координатах, поэтому не повторяется
// плиткой и сходится на стыках: подтёки воды от потолка, ржавые ореолы,
// чёрная плесень у пола, копоть под потолком. Насколько всё плохо, решает
// decay чанка (0 — у старта, 1 — далеко в глубине): его ставит room_builder.

uniform sampler2D paper_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paper_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paper_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.88, 0.77, 0.46);
uniform vec3 print_color : source_color = vec3(0.72, 0.6, 0.31);
uniform vec3 water_color : source_color = vec3(0.40, 0.30, 0.15);
uniform vec3 mold_color : source_color = vec3(0.10, 0.11, 0.07);
// Средняя яркость фото: цвет фото делим на неё, чтобы осталась лишь вариация
uniform vec3 paper_mean = vec3(0.466, 0.419, 0.368);
uniform float tex_scale = 0.5;
instance uniform float decay : hint_range(0.0, 1.0) = 0.0;

varying vec3 wpos;
varying vec3 wnorm;

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Координаты на плоскости стены: вдоль стены и вверх, в метрах
	float along = abs(wnorm.x) > 0.5 ? wpos.z : wpos.x;
	vec2 wall = vec2(along, wpos.y);
	vec2 tuv = wall * tex_scale;
	// Базис рельефа по мировым осям стены: у геометрии касательных нет,
	// а фактура и так снята в мировых координатах
	TANGENT = normalize((VIEW_MATRIX * vec4(abs(wnorm.x) > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0), 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec3 photo = texture(paper_diff, tuv).rgb / paper_mean;
	vec3 arm = texture(paper_arm, tuv).rgb;

	// Печатный узор: двойные полосы и ромбики, выцветшие пятнами
	float stripe = 1.0 - smoothstep(0.004, 0.012, abs(fract(along * 5.0) - 0.5) - 0.02);
	vec2 d = fract(vec2(along * 5.0, wpos.y * 3.33)) - 0.5;
	float diamond = 1.0 - smoothstep(0.06, 0.09, abs(d.x) + abs(d.y));
	float fade = smoothstep(0.25, 0.75, fbm(wall * 0.6));
	// Узор едва читается — как на выгоревших обоях, а не панели под дерево
	vec3 color = mix(base_color, print_color, max(stripe * 0.35, diamond * 0.4) * (0.4 + 0.6 * fade));
	// Фото — только старение бумаги: вариация тона, а не её коричневый цвет
	color *= mix(vec3(1.0), vec3(dot(photo, vec3(0.333))), 0.55);
	// Крупная неровность тона: лист к листу обои выгорели по-разному
	color *= 0.88 + 0.2 * fbm(wall * 0.15 + 7.3);

	float h = wpos.y;
	// Подтёки воды: от потолка вниз полосами, длина и сила растут с порчей
	float column = fbm(vec2(along * 2.2, 0.0) + 13.0);
	float reach = mix(0.4, 1.9, decay) * (0.5 + column);
	float drip_edge = (2.8 - h) / max(reach, 0.01);
	float drip = smoothstep(0.55, 0.75, column + 0.15 * vnoise(vec2(along * 9.0, h * 1.5)))
		* (1.0 - smoothstep(0.6, 1.0, drip_edge));
	// Ореол ржавой воды по кромке подтёка
	float halo = drip * smoothstep(0.35, 0.95, drip_edge);
	color = mix(color, water_color, clamp(drip * 0.45 + halo * 0.35, 0.0, 0.8));

	// Плесень и сырость у пола: пятнами, выше и гуще в глубине лабиринта
	float mold_h = mix(0.25, 1.1, decay);
	float mold = smoothstep(0.55 - decay * 0.2, 0.75, fbm(wall * 1.6 + 3.1))
		* (1.0 - smoothstep(0.0, mold_h, h - 0.08 * fbm(wall * 4.0)));
	color = mix(color, mold_color, mold * 0.85);
	// Грязь у пола и копоть под потолком — заземляют стену
	color *= mix(0.72, 1.0, smoothstep(0.0, 0.45, h));
	color *= mix(0.8, 1.0, smoothstep(2.8, 2.35, h));

	ALBEDO = color;
	NORMAL_MAP = texture(paper_nor, tuv).rgb;
	NORMAL_MAP_DEPTH = 1.2;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.2;
	// Мокрое блестит: подтёки и плесень темнее и глаже сухой бумаги
	ROUGHNESS = mix(clamp(arm.g * 0.95, 0.6, 1.0), 0.35, clamp(drip * 0.8 + mold * 0.5, 0.0, 1.0));
	METALLIC = 0.0;
}
