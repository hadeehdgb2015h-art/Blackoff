// Night sky for the dark-fantasy look: violet zenith, blood-rose horizon band,
// clouds, stars, a large pale moon and a glowing rift torn across the north.
// Static (no TIME) so the sky radiance is computed once, not every frame.
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.07, 0.05, 0.16);
uniform vec3 horizon_color : source_color = vec3(0.34, 0.15, 0.36);
uniform vec3 band_color : source_color = vec3(0.95, 0.36, 0.42);
uniform vec3 ground_color : source_color = vec3(0.05, 0.035, 0.07);
uniform vec3 cloud_color : source_color = vec3(0.16, 0.1, 0.22);
uniform vec3 moon_color : source_color = vec3(0.93, 0.9, 1.0);
uniform vec3 rift_color : source_color = vec3(1.0, 0.32, 0.86);
uniform vec3 moon_dir = vec3(-0.35, 0.5, -0.8);

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	float up = clamp(h, 0.0, 1.0);
	vec3 col = mix(horizon_color, zenith_color, pow(up, 0.55));
	col += band_color * exp(-abs(h) * 10.0) * 0.5;

	// stars (fade toward the horizon)
	vec3 g = d * 260.0;
	vec3 cell = floor(g);
	float r = hash3(cell);
	float star = step(0.9965, r) * smoothstep(0.5, 0.0, length(fract(g) - 0.5)) * (0.4 + 0.6 * hash3(cell + 3.1));
	col += vec3(0.85, 0.82, 1.0) * star * smoothstep(0.05, 0.35, h) * 1.4;

	// moon with halo and maria
	vec3 m = normalize(moon_dir);
	float md = dot(d, m);
	vec3 t = normalize(cross(m, vec3(0.0, 1.0, 0.0)));
	vec3 b = cross(t, m);
	vec2 muv = vec2(dot(d, t), dot(d, b)) / 0.055;
	float disc = smoothstep(1.0, 0.96, length(muv)) * step(0.0, md);
	float maria = 0.72 + 0.28 * smoothstep(0.35, 0.7, fbm(muv * 2.6 + 4.0));
	float limb = 0.75 + 0.25 * sqrt(max(1.0 - dot(muv, muv), 0.0));
	col += moon_color * disc * maria * limb * 0.95;
	col += moon_color * (pow(max(md, 0.0), 1500.0) * 0.35 + pow(max(md, 0.0), 60.0) * 0.12);

	// rift: a jagged tear of light across the northern sky
	float az = atan(d.x, -d.z);          // 0 = north (-Z)
	float el = asin(clamp(h, -1.0, 1.0));
	float span = smoothstep(-1.5, -1.05, az) * smoothstep(0.95, 0.4, az);
	float path = 0.52 + 0.1 * sin(az * 2.2 + 0.4) + 0.045 * sin(az * 6.1 + 1.3) + (fbm(vec2(az * 7.0, 2.0)) - 0.5) * 0.09;
	float dist = abs(el - path);
	float width = 0.0045 * span * (0.6 + 0.8 * fbm(vec2(az * 11.0, 7.0)));
	float core = smoothstep(width, width * 0.2, dist) * span;
	float glow = exp(-dist * 30.0) * span;
	col += rift_color * glow * 0.32 + vec3(1.0, 0.8, 1.0) * core * 0.7;

	// clouds, lit from below by the rift and the horizon
	vec2 cp = d.xz / (h + 0.22) * 1.2;
	float c = fbm(cp + vec2(3.1, 1.7));
	float cl = smoothstep(0.48, 0.8, c) * smoothstep(0.0, 0.2, h) * (1.0 - disc);
	vec3 ccol = cloud_color + rift_color * glow * 0.35 + band_color * exp(-h * 6.0) * 0.12;
	col = mix(col, ccol, cl * 0.85);

	col = mix(col, ground_color, smoothstep(0.0, -0.08, h));
	COLOR = col;
}
