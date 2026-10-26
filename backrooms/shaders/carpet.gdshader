shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Ковёр Backrooms. Фактура — фото грязного петлевого ковра (Poly Haven, CC0,
// textures/CREDITS.md): рельеф ворса, затенение, шероховатость и вариация
// яркости; цвет — горчичный. Повтор фото ломает крупная неровность тона.
// Поверх в мировых координатах: сырые пятна (темнее и блестят — ковёр
// промок), бурые потёки и вытоптанные дорожки. decay чанка (room_builder)
// делает пол мокрее и грязнее с глубиной.

uniform sampler2D carpet_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D carpet_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D carpet_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 carpet_color : source_color = vec3(0.66, 0.56, 0.33);
uniform vec3 wet_color : source_color = vec3(0.17, 0.14, 0.08);
uniform vec3 stain_color : source_color = vec3(0.22, 0.12, 0.07);
uniform vec3 carpet_mean = vec3(0.207, 0.184, 0.144);
uniform float tex_scale = 0.7;
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
}

void fragment() {
	// Базис рельефа по мировым осям: у плоскости касательных нет
	TANGENT = normalize((VIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	vec2 p = wpos.xz;
	// Фото чуть повёрнуто и сдвинуто от шума — стыки плиток не читаются
	vec2 tuv = p * tex_scale + vec2(fbm(p * 0.05), fbm(p * 0.05 + 9.0)) * 0.6;
	vec3 photo = texture(carpet_diff, tuv).rgb / carpet_mean;
	vec3 arm = texture(carpet_arm, tuv).rgb;
	vec3 color = carpet_color * mix(vec3(1.0), photo, 0.6);
	color *= 0.82 + 0.3 * fbm(p * 0.12 + 3.0);

	// Сырость: широкие пятна, у краёв — тёмный ободок высохшей воды
	float wet_n = fbm(p * 0.22 + 21.0);
	float wet_cut = mix(0.68, 0.5, decay);
	float wet = smoothstep(wet_cut, wet_cut + 0.06, wet_n);
	float rim = smoothstep(wet_cut - 0.04, wet_cut, wet_n) * (1.0 - wet);
	color = mix(color, wet_color, wet * 0.7);
	color *= 1.0 - rim * 0.35;

	// Бурые потёки: мелкие рваные пятна, гуще в глубине
	float stain = smoothstep(0.72 - decay * 0.12, 0.8, fbm(p * 0.9 + 40.0));
	color = mix(color, stain_color, stain * 0.75);

	ALBEDO = color;
	NORMAL_MAP = texture(carpet_nor, tuv).rgb;
	NORMAL_MAP_DEPTH = mix(1.0, 0.5, wet);
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.3;
	// Мокрый ворс прилипает и бликует под лампой
	ROUGHNESS = mix(arm.g, 0.32, wet * 0.85);
	SPECULAR = mix(0.35, 0.6, wet);
}
