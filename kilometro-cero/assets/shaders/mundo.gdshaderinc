// Material compartido del mundo (tarea 62c.3e, D140 y D141). Lo usan mundo.gdshader (cara de
// adelante) y mundo_doble.gdshader (las dos caras). La luz es la de siempre de Godot, la misma del
// StandardMaterial3D: sombreado suave, sin rampa de tonos. Lo arma Palette; no se usa a mano.
//
// Color: sale de la paleta compartida (una celda por color) según `swatch`; con `color_mode` 1
// sale del color de cada vértice (terreno) y con 2 mezcla `tint_a` y `tint_b` según el rojo del
// vértice (horizonte, que cambia con la hora).
// Vitalidad (D141): lo abandonado se ve desaturado y con polvo; lee un mapa global por zona.
// Viento: mueve la punta de pasto y árboles, más cuanto más alto (`wind`, en metros).

uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform int swatch = 0;
uniform int swatch_alt = -1;
// Cuánto va hacia `swatch_alt`: fijo (`alt_mix`) o según la altura del vértice (`alt_height`, la
// altura local a la que ya es todo `swatch_alt`; 0 no mira la altura).
uniform float alt_mix : hint_range(0.0, 1.0) = 0.0;
uniform float alt_height = 0.0;
uniform int color_mode = 0;
uniform vec3 tint_a : source_color = vec3(1.0);
uniform vec3 tint_b : source_color = vec3(1.0);
uniform float wind = 0.0;
uniform float wind_height = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
// Vitalidad fija (de 0 a 1) para lo que no depende de la zona; -1 lee el mapa.
uniform float vitality_override = -1.0;

global uniform sampler2D vitality_map;
global uniform sampler2D vitality_map_prev;
global uniform float vitality_mix;
global uniform vec4 vitality_rect;
global uniform float vitality_enabled;

const int PALETTE_COLUMNS = 8;
// El pampero: de dónde sopla el viento, en el mundo.
const vec3 WIND_DIRECTION = vec3(0.8, 0.0, 0.6);
// El polvo de lo abandonado (tosca, ya en lineal).
const vec3 DUST = vec3(0.69, 0.57, 0.37);

varying vec3 world_position;
varying float height_t;

vec3 palette_color(int index) {
	ivec2 size = textureSize(palette, 0);
	int cell = max(size.x / PALETTE_COLUMNS, 1);
	ivec2 texel = ivec2((index % PALETTE_COLUMNS) * cell + cell / 2, (index / PALETTE_COLUMNS) * cell + cell / 2);
	return texelFetch(palette, texel, 0).rgb;
}

vec3 srgb_to_linear(vec3 color) {
	return mix(color / 12.92, pow((color + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), color));
}

float vitality_at(vec2 point) {
	if (vitality_override >= 0.0) {
		return vitality_override;
	}
	if (vitality_enabled < 0.5) {
		return 1.0;
	}
	vec2 uv = (point - vitality_rect.xy) / vitality_rect.zw;
	uv = clamp(uv, vec2(0.0), vec2(1.0));
	return mix(texture(vitality_map_prev, uv).r, texture(vitality_map, uv).r, vitality_mix);
}

vec3 with_vitality(vec3 color, float vitality) {
	float gray = dot(color, vec3(0.2126, 0.7152, 0.0722));
	vec3 dusty = mix(vec3(gray), DUST * (0.6 + gray), 0.3);
	return mix(dusty, color, mix(0.15, 1.0, clamp(vitality, 0.0, 1.0)));
}

void vertex() {
	height_t = alt_height > 0.0 ? clamp(VERTEX.y / alt_height, 0.0, 1.0) : 0.0;
	if (wind > 0.0) {
		vec3 origin = MODEL_MATRIX[3].xyz;
		float phase = TIME * 1.6 + origin.x * 0.13 + origin.z * 0.09;
		float gust = 0.55 + 0.35 * sin(phase) + 0.1 * sin(phase * 2.7 + 1.3);
		float reach = clamp(VERTEX.y / max(wind_height, 0.001), 0.0, 1.0);
		vec3 push = normalize(WIND_DIRECTION) * wind * gust * reach * reach;
		// Del mundo al espacio del modelo (sirve con giro y escala pareja, como en BiomeScatter).
		mat3 basis = mat3(MODEL_MATRIX);
		VERTEX += transpose(basis) * push / max(dot(basis[0], basis[0]), 0.0001);
	}
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 albedo;
	if (color_mode == 1) {
		albedo = srgb_to_linear(COLOR.rgb);
	} else if (color_mode == 2) {
		albedo = mix(tint_a, tint_b, COLOR.r);
	} else {
		albedo = palette_color(swatch);
		if (swatch_alt >= 0) {
			albedo = mix(albedo, palette_color(swatch_alt), clamp(alt_mix + height_t, 0.0, 1.0));
		}
	}
	ALBEDO = with_vitality(albedo, vitality_at(world_position.xz));
	ROUGHNESS = roughness_value;
	SPECULAR = 0.3;
}
