shader_type spatial;
render_mode depth_test_disabled, unshaded;

// https://www.youtube.com/watch?v=i12pFwXlOGw Advanced Procuderal 3D Graphics - Raymarching tutorial

#include "res://shaders/hg_sdf.gdshaderinc"

void vertex() {
	POSITION = vec4(VERTEX, 1.0);
}

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D u_texture1;
uniform sampler2D u_texture2;
uniform sampler2D u_texture3;
uniform sampler2D u_texture4;
uniform sampler2D u_texture5;
uniform sampler2D u_texture6;
uniform sampler2D u_texture7;

uniform int max_steps : hint_range(128, 512, 128) = 256;

const float CUBE_SIZE = 6.0;

const float CUBE_SCALE = 1.0 / CUBE_SIZE;
const float ROOF_SCALE = 0.15;
const float PEDESTAL_SCALE = 0.3;
const float FLOOR_SCALE = 0.15;
const float SPHERE_SCALE = 0.2;
const float WALL_SCALE = 0.12;

const float ROOF_BUMP_FACTOR = 0.31;
const float SPHERE_BUMP_FACTOR = 0.21;
const float WALL_BUMP_FACTOR = 0.06;

const float MAX_DIST = 4000.0;
const float EPSILON = 1e-3;

const int AA = 0; // 0/1 off/on - its 4x samples so its very demanding

void translate_sphere(inout vec3 p) {
    p.y -= 4.4;
}

void rotate_sphere(inout vec3 p) {
    pR(p.xz, 1.0 * TIME);
}

float displace(vec3 p) {
    pR(p.yz, sin(2.0 * TIME));
    return (sin(p.x + 4.0 * TIME) * sin(p.y + sin(2.0 * TIME)) * sin(p.z + 6.0 * TIME));
}

vec2 op_union_id(vec2 res1, vec2 res2) {
    return (res1.x < res2.x) ? res1 : res2;
}

vec2 op_difference_id(vec2 res1, vec2 res2) {
    return (res1.x > -res2.x) ? res1 : vec2(-res2.x, res2.y);
}

vec2 op_difference_columns_id(vec2 res1, vec2 res2, float r, float n) {
    float dist = fOpDifferenceColumns(res1.x, res2.x, r, n);
    return (res1.x > -res2.x) ? vec2(dist, res1.y) : vec2(dist, res2.y);
}

vec2 op_union_stairs_id(vec2 res1, vec2 res2, float r, float n) {
    float dist = fOpUnionStairs(res1.x, res2.x, r, n);
    return (res1.x < res2.x) ? vec2(dist, res1.y) : vec2(dist, res2.y);
}

vec2 op_union_chamfer_id(vec2 res1, vec2 res2, float r) {
    float dist = fOpUnionChamfer(res1.x, res2.x, r);
    return (res1.x < res2.x) ? vec2(dist, res1.y) : vec2(dist, res2.y);
}

vec3 tri_planar(sampler2D tex, vec3 p, vec3 normal) {
    normal = abs(normal);
    normal = pow(normal, vec3(5.0));
    normal /= normal.x + normal.y + normal.z;
    return (texture(tex, p.xy * 0.5 + 0.5) * normal.z +
            texture(tex, p.xz * 0.5 + 0.5) * normal.y +
            texture(tex, p.yz * 0.5 + 0.5) * normal.x).rgb;
}

float bump_mapping(sampler2D tex, vec3 p, vec3 n, float dist, float factor, float scale) {
    float bump = 0.0;
    if (dist < 0.1) {
        vec3 normal = normalize(n);
        bump += factor * tri_planar(tex, (p * scale), normal).r;
    }
    return bump;
}

vec2 get_pedestal(vec3 p) {
    float id = 9.0;
    float res;
    // box 1
    p.y += 13.8;
    float box1 = fBoxCheap(p, vec3(8, 0.4, 8));
    // box 2
    p.y -= 6.4;
    float box2 = fBoxCheap(p, vec3(7, 6, 7));
    // box 3
    pMirrorOctant(p.zx, vec2(7.5, 7.5));
    float box3 = fBoxCheap(p, vec3(5, 4, 1));
    // res
    res = box1;
    res = min(res, box2);
    res = fOpDifferenceColumns(res, box3, 1.9, 10.0);
    return vec2(res, id);
}

vec2 map(vec3 p) {
    vec3 tmp, op = p;
    // plane
    float plane_dist = fPlane(p, vec3(0, 1, 0), 14.0);
    float plane_id = 6.0;
    vec2 plane = vec2(plane_dist, plane_id);

    // pedestal
    vec2 pedestal = get_pedestal(p);

    vec3 pt = p + 0.2;
    pt.y -= 10.0;
    pR(pt.yx, 4.0 * TIME);
    pR(pt.yz, 0.3 * TIME);
    float torus_dist = fTorus(pt, 0.7, 10.0 + displace(pt) * 0.2);
    float torus_id = 12.0;
    vec2 torus = vec2(torus_dist, torus_id);
    // sphere
    vec3 ps = p + 0.2;
    ps.y -= 9.0;
    float sphere_dist = fSphere(ps, 7.0 + displace(p));
    float sphere_id = 1.0;
    vec2 sphere = vec2(sphere_dist, sphere_id);

    // manipulation operators
    pMirrorOctant(p.xz, vec2(50, 50));
    p.x = -abs(p.x) + 20.0;
    pMod1(p.z, 15.0);

    // roof
    vec3 pr = p;
    pr.y -= 15.7;
    pR(pr.xy, 0.6);
    pr.x -= 18.0;
    float roof_dist = fBox2Cheap(pr.xy, vec2(20, 0.5));
    roof_dist -= bump_mapping(u_texture7, p, p - ROOF_BUMP_FACTOR, roof_dist, ROOF_BUMP_FACTOR, ROOF_SCALE);
    roof_dist += ROOF_BUMP_FACTOR;
    float roof_id = 8.0;
    vec2 roof = vec2(roof_dist, roof_id);

    // box
    float box_dist = fBoxCheap(p, vec3(3,9,4));
    float box_id = 7.0;
    vec2 box = vec2(box_dist, box_id);

    // cylinder
    vec3 pc = p;
    pc.y -= 9.0;
    float cylinder_dist = fCylinder(pc.yxz, 4, 3);
    float cylinder_id = 7.0;
    vec2 cylinder = vec2(cylinder_dist, cylinder_id);

    // wall
    float wall_dist = fBox2Cheap(p.xy, vec2(1, 15));
    wall_dist -= bump_mapping(u_texture3, op, op + WALL_BUMP_FACTOR, wall_dist, WALL_BUMP_FACTOR, WALL_SCALE);
    wall_dist += WALL_BUMP_FACTOR;
    float wall_id = 7.0;
    vec2 wall = vec2(wall_dist, wall_id);

    // result
    vec2 res;
    res = op_union_id(box, cylinder);
    res = op_difference_columns_id(wall, res, 0.6, 3.0);
    res = op_union_chamfer_id(res, roof, 0.6);
    res = op_union_stairs_id(res, plane, 4.0, 5.0);
    res = op_union_id(res, sphere);
    res = op_union_id(res, torus);
    res = op_union_id(res, pedestal);
//    res = op_union_id(res, cube);
    res = res;
    return res;
}

vec3 get_material(vec3 p, float id, vec3 normal) {
    vec3 m;
	
    switch (int(id)) {
        case 1:
        	m = vec3(0.9, 0.0, 0.0);
			break;
        case 2:
        	m = vec3(0.2 + 0.4 * mod(floor(p.x) + floor(p.z), 2.0));
			break;
        case 3:
        	m = vec3(0.7, 0.8, 0.9);
			break;
        case 4:
        	vec2 i = step(fract(0.5 * p.xz), vec2(1.0 / 10.0));
        	m = ((1.0 - i.x) * (1.0 - i.y)) * vec3(0.37, 0.12, 0.0);
			break;
        case 5:
        	m = tri_planar(u_texture1, p * CUBE_SCALE, normal);
			break;
        // floor
        case 6:
        	m = tri_planar(u_texture2, p * FLOOR_SCALE, normal);
			break;
        // walls
        case 7:
        	m = tri_planar(u_texture3, p * WALL_SCALE, normal);
			break;
        // roof
        case 8:
        	m = tri_planar(u_texture4, p * ROOF_SCALE, normal);
			break;
        // pedestal
        case 9:
        	m = tri_planar(u_texture5, p * PEDESTAL_SCALE, normal);
			break;
        // sphere
        case 10:
        	//translate_sphere(p);
        	//rotate_sphere(p);
        	//rotate_sphere(normal);
        	m = tri_planar(u_texture6, p * SPHERE_SCALE, normal);
			break;
        // roof bump
        case 11:
        	m = tri_planar(u_texture7, p * ROOF_SCALE, normal);
			break;
		case 12:
        	m = vec3(0.6, 0.0, 0.0);
			break;
        default:
        	m = vec3(0.4);
			break;
    }
	
    return m;
}

vec2 raymarch(vec3 ro, vec3 rd) {
	vec2 hit, object;
	
	for(int i = 0; i < max_steps; i++) {
		vec3 p = ro + object.x * rd;
		hit = map(p);
		object.x += hit.x;
		object.y = hit.y;
		
		if (object.x > MAX_DIST) break;
		if(abs(hit.x) < EPSILON) break;
	}
	
	return object;
}

vec3 get_normal(vec3 pos) {
	float d = map(pos).x;
	vec2 e = vec2(EPSILON, 0.0);
	vec3 n = d - vec3(
		map(pos - e.xyy).x,
		map(pos - e.yxy).x,
		map(pos - e.yyx).x);
	return normalize(n);
}

float get_soft_shadow(vec3 p, vec3 light_pos) {
    float res = 1.0;
    float dist = 0.01;
    float light_size = 0.04;
	
    for (int i = 0; i < max_steps; i++) {
        float hit = map(p + light_pos * dist).x;
        res = min(res, hit / (dist * light_size));
        dist += hit;
		
        if (hit < 0.0001 || dist > 60.0) {
			break;
		}
    }
	
    return clamp(res, 0.0, 1.0);
}

float get_ambient_occlusion(vec3 p, vec3 normal) {
    float ao = 0.0;
    float weight = 1.0;
	
    for (int i = 0; i < 8; i++) {
        float len = 0.01 + 0.02 * float(i * i);
        float dist = map(p + normal * len).x;
        ao += (len - dist) * weight;
        weight *= 0.85;
    }
	
    return 1.0 - clamp(0.6 * ao, 0.0, 1.0);
}

vec3 get_light(vec3 p, vec3 rd, float id) {
	vec3 N = get_normal(p);
    vec3 color = get_material(p, id, N);
	vec3 light_pos = vec3(10.0, 55.0, -20.0);
	vec3 L = normalize(light_pos - p);
	vec3 V = -rd;
	vec3 R = reflect(-L, N);
	
	vec3 specular_color = vec3(0.6, 0.5, 0.4);
    vec3 specular = 1.3 * specular_color * pow(clamp(dot(R, V), 0.0, 1.0), 10.0);
    vec3 diffuse = 0.9 * color * clamp(dot(L, N), 0.0, 1.0);
    vec3 ambient = 0.05 * color;
    vec3 fresnel = 0.15 * color * pow(1.0 + dot(rd, N), 3.0);
	
	float shadow = get_soft_shadow(p + N, normalize(light_pos));
	float ao = get_ambient_occlusion(p, N);
	vec3 back = 0.05 * color * clamp(dot(N, -L), 0.0, 1.0);
	
	return (back + ambient + fresnel) * ao + (specular * ao + diffuse) * shadow;
}

vec4 render(in vec2 uv, in mat4 inv_view, in mat4 inv_projection) {
	vec4 camera = inv_view * inv_projection * vec4(uv, 1, 1);
	
	vec3 ro = inv_view[3].xyz;
	vec3 rd = normalize(camera.xyz);
	
	vec3 color = vec3(0);
	vec2 object = raymarch(ro, rd);
	
	if(object.x < MAX_DIST) {
		vec3 p = ro + object.x * rd;
        color += get_light(p, rd, object.y);
	}
	
	return vec4(color, object.x);
}

vec2 get_uv(in vec2 uv, in vec2 resolution, in vec2 offset) {
	vec2 o = vec2(offset) / resolution;
	return (uv + o) * 2.0 - 1.0;
}

vec4 render_without_aa(in vec2 uv, in vec2 resolution, in mat4 inv_view, in mat4 inv_projection) {
    return render(get_uv(uv, resolution, vec2(0.0)), inv_view, inv_projection);
}

vec4 render_with_aa(in vec2 uv, in vec2 resolution, in mat4 inv_view, in mat4 inv_projection) {
    vec4 e = vec4(0.125, -0.125, 0.375, -0.375);
    vec4 color = render(get_uv(uv, resolution, e.xz), inv_view, inv_projection) + 
				render(get_uv(uv, resolution, e.yw), inv_view, inv_projection) + 
				render(get_uv(uv, resolution, e.wx), inv_view, inv_projection) + 
				render(get_uv(uv, resolution, e.zy), inv_view, inv_projection);
    return color /= 4.0;
}

vec3 render_fog(in vec4 color, in vec3 rd) {
	vec3 result = color.rgb;
	
	vec3 background = vec3(0.4, 0.5, 1.0);
    result.rgb = mix(result.rgb, background, 1.0 - exp(-0.00001 * color.a * color.a));
	
	return result;
}

void fragment() {
	vec2 size = vec2(textureSize(screen_texture, 0).xy);
	vec4 camera = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(get_uv(SCREEN_UV, size, vec2(0)), 1, 1);
	vec3 rd = normalize(camera.xyz);
	vec4 color = vec4(0);
	
	if(AA == 1) {
		color = render_with_aa(SCREEN_UV.xy, size, INV_VIEW_MATRIX, INV_PROJECTION_MATRIX);
	} else {
		color = render_without_aa(SCREEN_UV.xy, size, INV_VIEW_MATRIX, INV_PROJECTION_MATRIX);
	}
	
	color.rgb = render_fog(color, rd);
	
	// gamma correction
	color.rgb = pow(color.rgb, vec3(0.4545));
	
	ALBEDO.rgb = color.rgb;
	ALPHA = 1.0;
}
