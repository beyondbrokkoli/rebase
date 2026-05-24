#version 460
layout(set = 0, binding = 0) readonly buffer MasterBuffer { uint data[]; } vram;

layout(push_constant) uniform PushConstants {
    mat4 viewProj;                    // 0-63: 64 bytes (Row-Major memory)
    uint soa_upload_idx;              // 64-67
    uint aos_current_idx;             // 68-71
    uint aos_prev_idx;                // 72-75
    uint particle_count;              // 76-79
    float dt;                         // 80-83
    float total_time;                 // 84-87
    float spread;                     // 88-91
    float highlight_power;            // 92-95
    uint algae_color;                 // 96-99
    uint water_color;                 // 100-103
    uint bg_color_a;                  // 104-107
    uint bg_color_b;                  // 108-111
    uint target_state;                // 112-115
    uint sorted_idx;                  // 116-119
    uint cell_counters_idx;           // 120-123
    uint cell_offsets_idx;            // 124-127
} pc;

layout(location = 0) out vec3 fragColor;
layout(location = 1) out vec3 v_worldPos;
layout(location = 2) flat out uint v_shapeID;
layout(location = 3) flat out float v_colorIdx;

const vec3 SHAPE_LIBRARY[14] = vec3[](
    vec3(0.0,  1.5,  0.0), vec3(0.0, -0.5,  0.0), vec3(-1.0, 0.0,  1.0),
    vec3( 1.0, 0.0,  1.0), vec3( 1.0, 0.0, -1.0), vec3(-1.0, 0.0, -1.0),
    vec3(-1.0, -1.0,  1.0), vec3( 1.0, -1.0,  1.0), vec3( 1.0,  1.0,  1.0),
    vec3(-1.0,  1.0,  1.0), vec3(-1.0, -1.0, -1.0), vec3( 1.0, -1.0, -1.0),
    vec3( 1.0,  1.0, -1.0), vec3(-1.0,  1.0, -1.0)
);

float hash(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & uvec3(0x7fffffffU)) / float(0x7fffffff);
}

mat3 rotate3D(float x, float y, float z) {
    float cx = cos(x), sx = sin(x); float cy = cos(y), sy = sin(y); float cz = cos(z), sz = sin(z);
    return mat3(cy*cz, -cx*sz + sx*sy*cz, sx*sz + cx*sy*cz, cy*sz, cx*cz + sx*sy*sz, -sx*cz + cx*sy*sz, -sy, sx*cy, cx*cy);
}

uint get_cell_id(vec3 pos) {
    ivec3 p = ivec3(pos * 0.005);
    uint h = (uint(p.x) * 73856093U) ^ (uint(p.y) * 19349663U) ^ (uint(p.z) * 83492791U);
    return h % 262144U;
}

void main() {
    uint real_p_id = gl_InstanceIndex;
    uint sorted_p_id = vram.data[pc.sorted_idx + real_p_id];

    // --- PREDICATED CULLING (Stable Identities) ---
    // pc.bg_color_a: 0 = DUAL, 1 = GEOM ONLY, 2 = POINTS ONLY
    if (pc.bg_color_a == 0) {
        if (pc.target_state != 88 && (sorted_p_id % 2) != 0) {
            gl_Position = vec4(0.0, 0.0, 2.0, 1.0); 
            return;
        }
        if (pc.target_state == 88 && (sorted_p_id % 2) == 0) {
            gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
            return;
        }
    }

    // --- DATA FETCH ---
    uint aos_base = pc.aos_current_idx + (sorted_p_id * 4);
    vec3 anchor = vec3(
        uintBitsToFloat(vram.data[aos_base + 0]),
        uintBitsToFloat(vram.data[aos_base + 1]),
        uintBitsToFloat(vram.data[aos_base + 2])
    );

    float h1 = hash(sorted_p_id);
    float h2 = hash(sorted_p_id + 1337);
    float h3 = hash(sorted_p_id + 42069);

    // --- CALCULATE POSITION ---
    vec3 local_pos = vec3(0.0);
    if (pc.target_state != 88) {
        local_pos = SHAPE_LIBRARY[gl_VertexIndex];
        vec3 scale = vec3(0.5 + h1 * 1.5, 0.5 + h2 * 3.0, 0.5 + h3 * 1.5) * 500.0;
        local_pos *= scale;

        float rx = (h1 * 6.28) + (pc.total_time * (h1 - 0.5) * 0.8);
        float ry = (h2 * 6.28) + (pc.total_time * (h2 - 0.5) * 0.8);
        float rz = (h3 * 6.28) + (pc.total_time * (h3 - 0.5) * 0.8);
        local_pos = rotate3D(rx, ry, rz) * local_pos;
    }

    vec3 final_pos = anchor + local_pos;
    vec4 clip_pos = pc.viewProj * vec4(final_pos, 1.0);
    float dist = max(clip_pos.w, 0.001);

    // --- POINT SCALING (No disappearing!) ---
    if (pc.target_state == 88) {
        float base_size = 2.0 + (h2 * 8.0);
        float projected_size = (base_size * pc.spread * 60.0) / dist;
        
        // Clamp to 2.0 to prevent sub-pixel rasterization twinkling
        gl_PointSize = max(2.0, projected_size);
    }

    // --- SPATIAL DATA (Maintained for future UI/Physics logic) ---
    uint cell = get_cell_id(anchor);
    uint density = vram.data[pc.cell_counters_idx + cell]; 
    // We fetch density but no longer use it to turn things red. 

    // --- CLEAN COLOR & OUTPUT ---
    float normalized_y = clamp((anchor.y + 5000.0) / 10000.0, 0.0, 1.0);
    float meridian_curve = smoothstep(0.3, 0.7, normalized_y);

    vec3 c_algae = unpackUnorm4x8(pc.algae_color).rgb;
    vec3 c_water = unpackUnorm4x8(pc.water_color).rgb;
    vec3 base_color = mix(c_water, c_algae, meridian_curve);

    vec3 final_color = base_color * (0.75 + 0.5 * h1); // Retain slight per-particle variance

    v_worldPos = final_pos;
    gl_Position = clip_pos;
    fragColor = final_color;
    v_shapeID = pc.target_state;
    v_colorIdx = meridian_curve;
}
