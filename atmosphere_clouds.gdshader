shader_type spatial;
render_mode unshaded, cull_front, depth_test_disabled, skip_vertex_transform;

// --- 🎮 移动端参数 ---
uniform int ray_steps = 32;      // 采样次数
uniform float step_size = 250.0; // 步长
uniform float density_scale = 0.03;

// --- ☁️ 云层高度 ---
uniform float cloud_bottom = 1500.0;
uniform float cloud_top = 4000.0;
uniform float coverage = 0.45;

// --- ☀️ 颜色配置 ---
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.8);
uniform vec3 sky_top_color : source_color = vec3(0.1, 0.4, 0.9);
uniform vec3 sky_horizon_color : source_color = vec3(0.6, 0.75, 0.9);
uniform vec3 cloud_light : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shadow : source_color = vec3(0.25, 0.3, 0.4);

// --- 🎲 纯数学噪声 (不依赖纹理) ---
float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
				   mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
				   mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float f = 0.0;
	float a = 0.5;
	for(int i = 0; i < 4; i++) {
		f += a * noise(p);
		p *= 2.02;
		a *= 0.5;
	}
	return f;
}

// --- 🌫️ 采样逻辑 ---
float map_clouds(vec3 p) {
	vec3 move = vec3(TIME * 20.0, 0.0, TIME * 10.0);
	vec3 pos = (p + move) * 0.0004;
	float n = fbm(pos);

	float h = p.y;
	float thickness = cloud_top - cloud_bottom;
	float h_norm = (h - cloud_bottom) / thickness;
	float gradient = 1.0 - pow(2.0 * h_norm - 1.0, 2.0);

	float d = n * gradient - (1.0 - coverage);
	return max(d, 0.0);
}

void vertex() {
	// ⚡ 修复点：MODEL_VIEW_MATRIX -> MODELVIEW_MATRIX (去掉了中间的下划线)
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, 1.0, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 world_pos = (INV_VIEW_MATRIX * view).xyz;
	vec3 rd = normalize(world_pos - cam_pos);
	vec3 ro = cam_pos;

	// 绘制大气背景
	float horizon = smoothstep(-0.1, 0.4, rd.y);
	vec3 final_color = mix(sky_horizon_color, sky_top_color, horizon);

	float sun_dot = max(0.0, dot(rd, normalize(sun_dir)));
	final_color += vec3(1.0, 0.9, 0.7) * pow(sun_dot, 128.0);
	final_color += vec3(1.0, 0.8, 0.6) * pow(sun_dot, 32.0) * 0.5;

	// 体积云渲染
	if (rd.y > 0.05) {
		float dist_to_start = (cloud_bottom - ro.y) / rd.y;

		if (dist_to_start > 0.0) {
			vec3 p = ro + rd * dist_to_start;
			float dist_limit = (cloud_top - ro.y) / rd.y;
			float ray_len = dist_limit - dist_to_start;

			if (ray_len > 0.0) {
				// 抖动
				float dither = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
				p += rd * step_size * dither;

				float density_acc = 0.0;
				vec3 cloud_acc = vec3(0.0);

				for(int i=0; i<ray_steps; i++) {
					if (density_acc >= 1.0) break;

					float dens = map_clouds(p);

					if (dens > 0.001) {
						float step_d = dens * density_scale * step_size;
						float light = dens + (p.y - cloud_bottom) / (cloud_top - cloud_bottom);
						vec3 col = mix(cloud_shadow, cloud_light, clamp(light + sun_dot * 0.5, 0.0, 1.0));
						cloud_acc += col * step_d * (1.0 - density_acc);
						density_acc += step_d;
					}
					p += rd * step_size;
				}

				float mist = 1.0 - exp(-dist_to_start * 0.00005);
				vec3 cloud_final = mix(cloud_acc, sky_horizon_color, mist);
				final_color = mix(final_color, cloud_final, min(density_acc, 1.0));
			}
		}
	}
	ALBEDO = final_color;
}