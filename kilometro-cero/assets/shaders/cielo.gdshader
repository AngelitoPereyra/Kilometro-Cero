shader_type sky;
// Cielo de degradado (tarea 62c.3e, D140): arriba, horizonte y suelo; el sol (o la luna) con un
// halo; estrellas de noche. LookDirector cambia los colores según la hora.

uniform vec3 top_color : source_color = vec3(0.44, 0.7, 0.88);
uniform vec3 horizon_color : source_color = vec3(0.81, 0.91, 0.96);
uniform vec3 ground_color : source_color = vec3(0.6, 0.62, 0.55);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.77);
// Medio ancho del disco, en radianes.
uniform float sun_size = 0.03;
uniform float sun_glow : hint_range(0.0, 2.0) = 0.35;
uniform float stars : hint_range(0.0, 1.0) = 0.0;

float hash(vec3 point) {
	return fract(sin(dot(point, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void sky() {
	float up = EYEDIR.y;
	vec3 color = mix(horizon_color, top_color, pow(clamp(up, 0.0, 1.0), 0.6));
	color = mix(color, ground_color, smoothstep(0.0, -0.1, up));
	if (LIGHT0_ENABLED) {
		float facing = dot(EYEDIR, LIGHT0_DIRECTION);
		float disc = smoothstep(cos(sun_size), cos(sun_size * 0.7), facing);
		float halo = pow(max(facing, 0.0), 12.0) * sun_glow;
		color += sun_color * (disc * 3.0 + halo) * step(-0.02, up);
	}
	if (stars > 0.0 && up > 0.0) {
		vec3 cell = floor(EYEDIR * 260.0);
		float star = step(0.9975, hash(cell));
		color += vec3(star * stars * smoothstep(0.0, 0.25, up));
	}
	COLOR = color;
}
