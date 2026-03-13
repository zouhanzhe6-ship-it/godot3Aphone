extends Node3D

# --- 🌍 世界参数 ---
const CHUNK_SIZE = 32
const VIEW_DISTANCE = 3
const RES = 32
const SEA_LEVEL = 0.0

# --- 🌿 植被参数 ---
const TREE_DENSITY = 0.04
const BASE_GRASS_CHANCE = 0.12 
const GRASS_CLUMP_THRESHOLD = 0.15 
const BLOCK_SIZE_MIN = 3
const BLOCK_SIZE_MAX = 25
const BLOCK_SPREAD_RADIUS = 4.0
const MAX_PEAK_HEIGHT = 120.0 
const MOUNTAIN_LEVEL = 45.0
const TREE_LINE = 25.0
const BEACH_LINE = 2.2 

# --- ⚙️ 噪声系统 ---
var continental_noise = FastNoiseLite.new()
var mountain_noise = FastNoiseLite.new()
var moisture_noise = FastNoiseLite.new()
var grass_clump_noise = FastNoiseLite.new() 
var grass_height_noise = FastNoiseLite.new()
var tex_noise = FastNoiseLite.new()
var chunks = {}

# 材质
var terrain_material = StandardMaterial3D.new()
var veg_shader = ShaderMaterial.new()
var water_material = StandardMaterial3D.new()
var cloud_shader = ShaderMaterial.new()

# --- 🌊 海洋系统 ---
var water_shader_mat = ShaderMaterial.new() 
var water_normal_noise = FastNoiseLite.new() 
var water_plane = MeshInstance3D.new()
var cloud_plane = MeshInstance3D.new() 
var player_node = null
var tree_mesh = ArrayMesh.new()
var grass_cluster_mesh = ArrayMesh.new() 

# --- ☀️ 光影系统 ---
var sun = DirectionalLight3D.new()
var env_node = WorldEnvironment.new()
var sky_mat = ProceduralSkyMaterial.new()
var day_time = 0.3
const DAY_SPEED = 0.002
var sun_color_ramp = Gradient.new()
var sky_horizon_ramp = Gradient.new()

const COL_SNOW = Color(0.95, 0.95, 0.98)
const COL_ROCK_DARK = Color(0.2, 0.15, 0.1)
const COL_ROCK_LIGHT = Color(0.4, 0.35, 0.3)
const COL_GRASS_LUSH = Color(0.15, 0.4, 0.1)
const COL_GRASS_DRY = Color(0.5, 0.45, 0.25)
const COL_SAND = Color(0.75, 0.7, 0.55)
const COL_SEA_BED = Color(0.1, 0.1, 0.2)
const COLOR_TRUNK = Color(0.2, 0.1, 0.05) 
const COLOR_LEAF = Color(0.1, 0.35, 0.05)

# --- 🌊 [核心升级] 现实级海洋 Shader ---
const OCEAN_SHADER_CODE = """
shader_type spatial;
render_mode specular_schlick_ggx, cull_disabled, depth_draw_always;
uniform vec3 deep_color : source_color = vec3(0.0, 0.02, 0.05);
uniform vec3 shallow_color : source_color = vec3(0.0, 0.3, 0.4);
uniform vec3 foam_color : source_color = vec3(0.95, 0.95, 0.95);
uniform vec3 sss_color : source_color = vec3(0.0, 0.6, 0.5);
uniform float wave_speed = 0.3;
uniform float wave_height = 0.4;
uniform float roughness = 0.04;
uniform sampler2D normal_texture_1; 
uniform sampler2D normal_texture_2;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform vec2 wave_direction_1 = vec2(1.0, 0.2);
uniform vec2 wave_direction_2 = vec2(0.2, 1.0);

vec3 gerstner_wave(vec2 uv, float time, vec2 dir, float steepness, float wavelength, inout vec3 tangent, inout vec3 binormal) {
	float k = 2.0 * 3.14159 / wavelength;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(dir);
	float f = k * (dot(d, uv) - c * time);
	float a = steepness / k;
	float sin_f = sin(f);
	float cos_f = cos(f);
	float wa = k * a;
	vec3 p = vec3(d.x * (a * cos_f), a * sin_f, d.y * (a * cos_f));
	float wa_cos = wa * cos_f;
	float wa_sin = wa * sin_f;
	tangent += vec3(-d.x * d.x * wa_sin, d.x * wa_cos, -d.x * d.y * wa_sin);
	binormal += vec3(-d.x * d.y * wa_sin, d.y * wa_cos, -d.y * d.y * wa_sin);
	return p;
}

void vertex() {
	float time = TIME * wave_speed;
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 p = VERTEX;
	vec2 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	p += gerstner_wave(world_pos, time, vec2(1.0, 0.1), 0.15, 50.0, tangent, binormal) * wave_height;
	p += gerstner_wave(world_pos, time, vec2(0.5, 0.6), 0.1, 25.0, tangent, binormal) * wave_height * 0.5;
	p += gerstner_wave(world_pos, time, vec2(-0.3, 0.8), 0.1, 12.0, tangent, binormal) * wave_height * 0.2;
	VERTEX = p;
	NORMAL = normalize(cross(binormal, tangent));
}

void fragment() {
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	float depth_fade = clamp((linear_depth - VERTEX.z) * 0.2, 0.0, 1.0);
	vec2 uv_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz * 0.03;
	float time = TIME * 0.03;
	vec3 n1 = texture(normal_texture_1, uv_world + wave_direction_1 * time).rgb;
	vec3 n2 = texture(normal_texture_2, uv_world - wave_direction_2 * time).rgb;
	vec3 final_normal = normalize(vec3(n1.xy + n2.xy - 1.0, n1.z * n2.z)); 
	NORMAL_MAP = final_normal;
	NORMAL_MAP_DEPTH = 0.3;
	float fresnel = sqrt(1.0 - dot(NORMAL, VIEW));
	fresnel = pow(fresnel, 4.0); 
	vec3 water_col = mix(shallow_color, deep_color, depth_fade);
	float sss_mask = smoothstep(0.4, 1.0, fresnel) * (0.5 + 0.5 * dot(NORMAL, vec3(0.0, 1.0, 0.0)));
	water_col = mix(water_col, sss_color, sss_mask * 0.5);
	float shore_foam = smoothstep(0.1, 0.0, depth_fade);
	float crest_foam = smoothstep(0.9, 0.75, dot(NORMAL, vec3(0.0, 1.0, 0.0))) * depth_fade;
	float foam_mix = clamp(shore_foam + crest_foam, 0.0, 1.0);
	ALBEDO = mix(water_col, foam_color, foam_mix);
	ROUGHNESS = mix(roughness, 0.5, foam_mix); 
	METALLIC = 0.0;
	SPECULAR = 1.0; 
	ALPHA = smoothstep(0.0, 0.5, depth_fade); 
}
"""

# --- 🌿 植被 Shader ---
const VEG_SHADER_CODE = """
shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley, specular_disabled; 
uniform vec3 color_trunk : source_color;
uniform vec3 color_leaf : source_color;
uniform float wind_speed = 1.0;
uniform float wind_strength = 0.1;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float random_offset = hash(world_pos.xz); 
	float wind_wave = sin(TIME * wind_speed + world_pos.x * 0.5 + world_pos.z * 0.5 + random_offset * 6.28);
	float complex_wind = wind_wave + sin(TIME * 2.1 + world_pos.x) * 0.5;
	float sway_mask = COLOR.r; 
	VERTEX.x += complex_wind * wind_strength * sway_mask;
	VERTEX.z += complex_wind * wind_strength * sway_mask * 0.7;
	VERTEX.y -= abs(complex_wind) * wind_strength * sway_mask * 0.15;
}

void fragment() {
	float leaf_mask = COLOR.g; 
	float random_val = COLOR.b; 
	if (leaf_mask > 0.5) {
		vec3 col_lush = color_leaf;
		vec3 col_dry = vec3(0.55, 0.5, 0.3);
		vec3 final_col = mix(col_lush, col_dry, random_val * 0.7 + hash(UV)*0.2);
		final_col *= clamp(UV.y + 0.3, 0.0, 1.0);
		ALBEDO = final_col;
		ROUGHNESS = 1.0; 
		SSS_STRENGTH = 0.6;
		BACKLIGHT = vec3(0.25, 0.35, 0.1);
		NORMAL = normalize(NORMAL + vec3(random_val*0.4, 0, -random_val*0.4));
	} else {
		ALBEDO = color_trunk * (0.7 + random_val * 0.3);
		ROUGHNESS = 1.0;
	}
}
"""

const CLOUD_SHADER_CODE = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never;
uniform sampler2D noise_tex;
uniform float cloud_speed = 0.02;

void fragment() {
	vec2 uv1 = UV + vec2(TIME * cloud_speed, TIME * cloud_speed * 0.5);
	vec2 uv2 = UV * 1.5 - vec2(TIME * cloud_speed * 0.8, 0.0);
	float noise = (texture(noise_tex, uv1).r + texture(noise_tex, uv2).r) * 0.5;
	float alpha = smoothstep(0.4, 0.8, noise);
	float edge = 1.0 - distance(UV, vec2(0.5)) * 2.0;
	ALBEDO = vec3(0.95, 0.95, 0.98);
	ALPHA = alpha * clamp(edge, 0.0, 1.0) * 0.8;
}
"""

func _ready():
	_init_noise()
	_init_materials()
	_init_ocean_material()
	_init_complex_vegetation()
	_init_environment() 
	_init_water()
	_init_clouds()
	
	if has_node("Player"):
		player_node = get_node("Player")
		player_node.position.y = 100.0 
	
	sun_color_ramp.add_point(0.0, Color(1.0, 0.3, 0.1))
	sun_color_ramp.add_point(0.2, Color(1.0, 0.8, 0.6))
	sun_color_ramp.add_point(0.5, Color(1.0, 0.98, 0.9))
	
	sky_horizon_ramp.add_point(0.0, Color(0.6, 0.2, 0.1))
	sky_horizon_ramp.add_point(0.4, Color(0.5, 0.6, 0.8))

func _init_noise():
	randomize()
	var seed_val = randi()
	continental_noise.seed = seed_val
	continental_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	continental_noise.frequency = 0.003
	continental_noise.fractal_octaves = 2
	
	mountain_noise.seed = seed_val + 100
	mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mountain_noise.frequency = 0.01
	mountain_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	mountain_noise.fractal_octaves = 4
	
	moisture_noise.seed = seed_val + 300
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moisture_noise.frequency = 0.002
	
	tex_noise.seed = randi()
	tex_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	tex_noise.frequency = 0.05
	tex_noise.fractal_octaves = 2
	
	grass_clump_noise.seed = randi()
	grass_clump_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	grass_clump_noise.frequency = 0.02
	grass_clump_noise.fractal_octaves = 2
	
	grass_height_noise.seed = randi()
	grass_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	grass_height_noise.frequency = 0.01
	
	water_normal_noise.seed = randi()
	water_normal_noise.noise_type = FastNoiseLite.TYPE_PERLIN 
	water_normal_noise.frequency = 0.008 
	water_normal_noise.fractal_octaves = 3

func _init_materials():
	var noise_img = tex_noise.get_image(512, 512)
	noise_img.generate_mipmaps()
	var noise_tex = ImageTexture.create_from_image(noise_img)
	
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.roughness = 1.0 
	terrain_material.specular = 0.0
	terrain_material.albedo_texture = noise_tex 
	terrain_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	terrain_material.uv1_triplanar = true
	terrain_material.uv1_world_triplanar = true
	terrain_material.uv1_scale = Vector3(0.5, 0.5, 0.5) 
	
	var v_shader = Shader.new()
	v_shader.code = VEG_SHADER_CODE
	veg_shader.shader = v_shader
	veg_shader.set_shader_parameter("color_trunk", COLOR_TRUNK)
	veg_shader.set_shader_parameter("color_leaf", COLOR_LEAF)

func _init_ocean_material():
	var shader = Shader.new()
	shader.code = OCEAN_SHADER_CODE
	water_shader_mat.shader = shader
	
	var img = water_normal_noise.get_image(512, 512)
	img.bump_map_to_normal_map(3.0) 
	img.generate_mipmaps() 
	var normal_tex = ImageTexture.create_from_image(img)
	
	water_shader_mat.set_shader_parameter("deep_color", Color(0.01, 0.03, 0.08))
	water_shader_mat.set_shader_parameter("shallow_color", Color(0.0, 0.4, 0.45))
	water_shader_mat.set_shader_parameter("foam_color", Color(0.95, 0.95, 0.95))
	water_shader_mat.set_shader_parameter("sss_color", Color(0.0, 0.8, 0.6))
	water_shader_mat.set_shader_parameter("wave_speed", 0.3)
	water_shader_mat.set_shader_parameter("wave_height", 0.4)
	water_shader_mat.set_shader_parameter("roughness", 0.04)
	
	water_shader_mat.set_shader_parameter("normal_texture_1", normal_tex)
	water_shader_mat.set_shader_parameter("normal_texture_2", normal_tex)

func _init_complex_vegetation():
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(35): 
		var center_offset = Vector3(randf_range(-0.35, 0.35), 0, randf_range(-0.35, 0.35))
		var angle = randf() * TAU
		var w = randf_range(0.03, 0.06)
		var h = 1.0
		var lean = randf_range(0.1, 0.45)
		var v1 = center_offset + Vector3(-w, 0, 0).rotated(Vector3.UP, angle)
		var v2 = center_offset + Vector3(w, 0, 0).rotated(Vector3.UP, angle)
		var v3 = center_offset + Vector3(0, h, lean).rotated(Vector3.UP, angle)
		var rand_color = randf()
		var col_bottom = Color(0.1, 0.8, rand_color, 1.0)
		var col_top = Color(1.0, 1.0, rand_color, 1.0)
		st.set_color(col_bottom)
		st.set_uv(Vector2(0,0))
		st.add_vertex(v1)
		st.set_color(col_bottom)
		st.set_uv(Vector2(1,0))
		st.add_vertex(v2)
		st.set_color(col_top)
		st.set_uv(Vector2(0.5,1))
		st.add_vertex(v3)
		st.add_index(i*3)
		st.add_index(i*3+1)
		st.add_index(i*3+2)
		st.add_index(i*3+2)
		st.add_index(i*3+1)
		st.add_index(i*3)
	st.generate_normals()
	grass_cluster_mesh = st.commit()
	
	var st_tree = SurfaceTool.new()
	st_tree.begin(Mesh.PRIMITIVE_TRIANGLES)
	_build_fractal_tree(st_tree, Vector3.ZERO, Vector3.UP, 4.5, 0.5, 3)
	st_tree.generate_normals()
	tree_mesh = st_tree.commit()

func _build_fractal_tree(st, pos, dir, length, rad, depth):
	var segments = 6
	var end_pos = pos + dir * length
	var axis = Vector3.UP.cross(dir).normalized()
	if axis.length_squared() < 0.01: 
		axis = Vector3.RIGHT
	var axis_y = dir.cross(axis).normalized()
	var col = Color(0.0, 0.0, randf())
	if depth <= 1: 
		col.r = 0.15 
	for i in range(segments):
		var a1 = (float(i)/segments)*TAU
		var a2 = (float(i+1)/segments)*TAU
		var p1 = pos+(axis*cos(a1)+axis_y*sin(a1))*rad
		var p2 = pos+(axis*cos(a2)+axis_y*sin(a2))*rad
		var p3 = end_pos+(axis*cos(a1)+axis_y*sin(a1))*(rad*0.6)
		var p4 = end_pos+(axis*cos(a2)+axis_y*sin(a2))*(rad*0.6)
		st.set_color(col); st.add_vertex(p1); st.set_color(col); st.add_vertex(p2); st.set_color(col); st.add_vertex(p3)
		st.set_color(col); st.add_vertex(p2); st.set_color(col); st.add_vertex(p4); st.set_color(col); st.add_vertex(p3)
	if depth > 0:
		var split = 2
		for k in range(split):
			var new_dir = dir.rotated(axis, 0.6+randf()*0.2).rotated(dir, randf()*TAU).normalized().lerp(Vector3.UP, 0.5).normalized()
			_build_fractal_tree(st, end_pos, new_dir, length*0.7, rad*0.6, depth - 1)
	else:
		var leaves = 20
		var col_leaf = Color(1.0, 1.0, randf())
		for k in range(leaves):
			var center = end_pos + Vector3(randf()-0.5, randf()-0.5, randf()-0.5).normalized() * 1.8
			var sz = 0.9
			var lv1 = center+Vector3(-sz,0,0)
			var lv2 = center+Vector3(sz,0,0)
			var lv3 = center+Vector3(0,sz,0)
			st.set_color(col_leaf); st.add_vertex(lv1); st.set_color(col_leaf); st.add_vertex(lv2); st.set_color(col_leaf); st.add_vertex(lv3)
			st.set_color(col_leaf); st.add_vertex(lv3); st.set_color(col_leaf); st.add_vertex(lv2); st.set_color(col_leaf); st.add_vertex(lv1)

func _init_environment():
	var env = Environment.new()
	sky_mat.sun_angle_max = 20.0
	var sky = Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	
	env.fog_enabled = true
	env.fog_density = 0.001
	env.fog_aerial_perspective = 0.6
	env_node.environment = env
	add_child(env_node)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	sun.light_energy = 1.5
	add_child(sun)

func _init_water():
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(5000, 5000)
	plane_mesh.subdivide_width = 256 
	plane_mesh.subdivide_depth = 256 
	
	water_plane.mesh = plane_mesh
	water_plane.material_override = water_shader_mat
	water_plane.position.y = -0.3
	add_child(water_plane)

func _init_clouds():
	var cloud_noise = FastNoiseLite.new()
	cloud_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	cloud_noise.fractal_octaves = 3
	var noise_tex = NoiseTexture2D.new()
	noise_tex.noise = cloud_noise
	var c_shader = Shader.new()
	c_shader.code = CLOUD_SHADER_CODE
	cloud_shader.shader = c_shader
	cloud_shader.set_shader_parameter("noise_tex", noise_tex)
	var mesh = PlaneMesh.new()
	mesh.size = Vector2(4000, 4000)
	cloud_plane.mesh = mesh
	cloud_plane.material_override = cloud_shader
	cloud_plane.position.y = 180.0
	add_child(cloud_plane)

func _process(delta):
	day_time = wrapf(day_time + delta * DAY_SPEED * 0.2, 0.0, 1.0)
	var sun_h = sin(day_time * PI)
	var grad_pos = clamp(sun_h, 0.0, 1.0)
	sun.rotation_degrees.x = -day_time * 180.0 + 90.0
	sun.light_color = sun_color_ramp.sample(grad_pos)
	sun.light_energy = clamp(sun_h * 1.5, 0.0, 1.5)
	sky_mat.sky_horizon_color = sky_horizon_ramp.sample(grad_pos)
	veg_shader.set_shader_parameter("wind_speed", 2.0 + sin(day_time * 5.0))
	veg_shader.set_shader_parameter("wind_strength", 0.15)
	
	if player_node:
		var pos = player_node.global_position
		water_plane.position.x = pos.x
		water_plane.position.z = pos.z
		cloud_plane.position.x = pos.x
		cloud_plane.position.z = pos.z
		if env_node.environment:
			if pos.y + 1.5 < SEA_LEVEL:
				env_node.environment.fog_light_color = Color(0.0, 0.05, 0.2)
				env_node.environment.fog_density = 0.1
			else:
				var fog_col = Color(0.6, 0.7, 0.8).lerp(Color(0.9, 0.5, 0.4), 1.0 - grad_pos)
				env_node.environment.fog_light_color = fog_col
				env_node.environment.fog_density = 0.001
		var cx = floor(pos.x / CHUNK_SIZE)
		var cz = floor(pos.z / CHUNK_SIZE)
		_update_chunks(Vector2i(cx, cz))

func _update_chunks(center: Vector2i):
	for x in range(center.x - VIEW_DISTANCE, center.x + VIEW_DISTANCE):
		for z in range(center.y - VIEW_DISTANCE, center.y + VIEW_DISTANCE):
			var coord = Vector2i(x, z)
			if not chunks.has(coord): 
				_create_chunk(coord)
	var to_remove = []
	for coord in chunks:
		if abs(coord.x - center.x) > VIEW_DISTANCE or abs(coord.y - center.y) > VIEW_DISTANCE: 
			to_remove.append(coord)
	for coord in to_remove: 
		chunks[coord].queue_free()
		chunks.erase(coord)

func _get_extreme_height(wx, wz):
	var continental = (continental_noise.get_noise_2d(wx, wz) + 1.0) * 0.5
	var final_h = 0.0
	
	if continental < 0.5:
		var t = smoothstep(0.0, 0.5, continental)
		final_h = lerp(-20.0, 1.0, t)
	else:
		var land_factor = (continental - 0.5) * 2.0 
		var mountains = pow(max(0.0, land_factor), 2.5) * MAX_PEAK_HEIGHT
		var ridge = mountain_noise.get_noise_2d(wx*0.5, wz*0.5) * 30.0
		final_h = mountains + ridge + 2.5
	
	return final_h

func _create_chunk(coord):
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(terrain_material)
	st.set_smooth_group(0)
	
	var tree_transforms = []
	var grass_transforms = []
	
	for z in range(RES + 1):
		for x in range(RES + 1):
			var px = float(x) / RES
			var pz = float(z) / RES
			var wx = (coord.x * CHUNK_SIZE) + (px * CHUNK_SIZE)
			var wz = (coord.y * CHUNK_SIZE) + (pz * CHUNK_SIZE)
			
			var h = _get_extreme_height(wx, wz)
			var moisture = moisture_noise.get_noise_2d(wx * 2.0, wz * 2.0)
			
			var color = COL_GRASS_LUSH
			if moisture < -0.2: 
				color = COL_GRASS_DRY 
			if h < SEA_LEVEL: 
				color = COL_SEA_BED
			elif h < BEACH_LINE: 
				color = COL_SAND 
			elif h < MOUNTAIN_LEVEL: 
				color = color 
			elif h < MAX_PEAK_HEIGHT * 0.8: 
				color = COL_ROCK_LIGHT
			else: 
				color = COL_SNOW
			
			var h_offset = _get_extreme_height(wx + 1.0, wz)
			if abs(h - h_offset) > 1.5 and h > BEACH_LINE: 
				color = COL_ROCK_DARK
			st.set_color(color)
			st.set_uv(Vector2(wx, wz))
			st.add_vertex(Vector3(wx, h, wz))
			
			if h > BEACH_LINE and h < MOUNTAIN_LEVEL and color != COL_ROCK_DARK:
				var tree_prob = TREE_DENSITY
				if moisture < 0.0: 
					tree_prob = 0.005
				if randf() < tree_prob:
					var t = Transform3D()
					var s = randf_range(1.2, 2.2)
					t = t.scaled(Vector3(s, s, s))
					t = t.rotated(Vector3.UP, randf() * TAU)
					t.origin = Vector3(wx, h - 0.3, wz)
					tree_transforms.append(t)
				
				var clump_val = grass_clump_noise.get_noise_2d(wx * 4.0, wz * 4.0)
				if clump_val < GRASS_CLUMP_THRESHOLD: 
					continue 
				
				if randf() < BASE_GRASS_CHANCE:
					var current_block_size = randi_range(BLOCK_SIZE_MIN, BLOCK_SIZE_MAX)
					if moisture > 0.2: 
						current_block_size = randi_range(15, BLOCK_SIZE_MAX + 5)
					elif moisture < -0.2: 
						current_block_size = randi_range(BLOCK_SIZE_MIN, 10)
					var height_val = grass_height_noise.get_noise_2d(wx * 2.5, wz * 2.5) 
					var final_scale_y = 1.0
					if moisture < -0.3: 
						final_scale_y = map_range(height_val, -1, 1, 0.9, 1.6)
					elif moisture > 0.2: 
						final_scale_y = map_range(height_val, -1, 1, 0.3, 0.7)
					else: 
						final_scale_y = map_range(height_val, -1, 1, 0.4, 1.0)
					
					for k in range(current_block_size):
						var t = Transform3D()
						var scale_xz = randf_range(0.85, 1.15)
						t = t.scaled(Vector3(scale_xz, final_scale_y, scale_xz))
						t = t.rotated(Vector3.UP, randf() * TAU)
						
						var spread_angle = randf() * TAU
						var spread_dist = sqrt(randf()) * BLOCK_SPREAD_RADIUS
						var offset = Vector3(cos(spread_angle) * spread_dist, 0, sin(spread_angle) * spread_dist)
						
						var world_pos_x = wx + offset.x
						var world_pos_z = wz + offset.z
						var new_h = _get_extreme_height(world_pos_x, world_pos_z)
						
						var slope_check = abs(new_h - _get_extreme_height(world_pos_x + 0.5, world_pos_z))
						if slope_check > 1.0: 
							continue
						
						t.origin = Vector3(world_pos_x, new_h, world_pos_z)
						grass_transforms.append(t)

	for z in range(RES):
		for x in range(RES):
			var r = RES + 1
			var i = z * r + x
			st.add_index(i); st.add_index(i + 1); st.add_index(i + r)
			st.add_index(i + r); st.add_index(i + 1); st.add_index(i + r + 1)
			
	st.generate_normals()
	st.generate_tangents()
	var chunk_root = Node3D.new()
	var mi = MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.create_trimesh_collision()
	chunk_root.add_child(mi)
	
	if tree_transforms.size() > 0:
		var mm = MultiMeshInstance3D.new()
		mm.multimesh = MultiMesh.new()
		mm.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		mm.multimesh.mesh = tree_mesh
		mm.material_override = veg_shader
		mm.multimesh.instance_count = tree_transforms.size()
		for i in range(tree_transforms.size()): 
			mm.multimesh.set_instance_transform(i, tree_transforms[i])
		chunk_root.add_child(mm)
	
	if grass_transforms.size() > 0:
		var mm_grass = MultiMeshInstance3D.new()
		mm_grass.multimesh = MultiMesh.new()
		mm_grass.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		mm_grass.multimesh.mesh = grass_cluster_mesh
		mm_grass.material_override = veg_shader
		mm_grass.multimesh.instance_count = grass_transforms.size()
		for i in range(grass_transforms.size()): 
			mm_grass.multimesh.set_instance_transform(i, grass_transforms[i])
		chunk_root.add_child(mm_grass)
	
	add_child(chunk_root)
	chunks[coord] = chunk_root

func map_range(val, min1, max1, min2, max2):
	return min2 + (val - min1) * (max2 - min2) / (max1 - min1)
