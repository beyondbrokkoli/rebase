#version 460
layout(set = 0, binding = 0) readonly buffer MasterBuffer { uint data[]; } vram;

layout(push_constant) uniform PushConstants {
    mat4 viewProj;
    uint pos_x_idx; uint pos_y_idx; uint pos_z_idx;
    uint particle_count; float dt;
    float total_time; float spread; float highlight_power;
    uint algae_color; uint water_color; uint bg_color_a; uint bg_color_b;
    uint target_state;
    uint sorted_idx; uint cell_counters_idx; uint cell_offsets_idx;
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
    uint p_id = gl_InstanceIndex;
    
    // 1. THE SEPARATION: 1:1 Mapping. 
    // We completely ignore pc.sorted_idx. This kills the ring-buffer flicker permanently.
    uint real_p_id = p_id; 

    vec3 anchor = vec3(
        uintBitsToFloat(vram.data[pc.pos_x_idx + real_p_id]),
        uintBitsToFloat(vram.data[pc.pos_y_idx + real_p_id]),
        uintBitsToFloat(vram.data[pc.pos_z_idx + real_p_id])
    );

    // 2. DENSITY READ
    uint cell = get_cell_id(anchor);
    uint density = vram.data[pc.cell_counters_idx + cell];

    // 3. HASH GENERATION (Unchanged)
    float h1 = hash(real_p_id);
    float h2 = hash(real_p_id + 1337);
    float h3 = hash(real_p_id + 42069);
    float h4 = hash(real_p_id + 9999); // The Phantom Decimation Dice

    // 4. THE SPLIT DENSITY ENGINE (Heat & Culling)
    float ALLOWED_DENSITY = 5.0;
    float overcrowded = max(float(density) - ALLOWED_DENSITY, 0.0);
    
    // "heat" goes from 0.0 (calm) to 1.0 (highly overcrowded)
    float heat = clamp(overcrowded * 0.05, 0.0, 1.0); 

    // Point Cloud: Physical Decimation
    float point_scale_fade = 1.0;
    if (pc.target_state == 88) {
        float survival_rate = 1.0 - heat;
        point_scale_fade = smoothstep(0.0, 0.5, survival_rate - h4 + 0.25);

        // ZERO-COST CULL: Only applies to points now! Geometry is structurally immune.
        if (point_scale_fade <= 0.001) {
            gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
            return;
        }
    }

    // [Space Warp logic goes here (Unchanged)]
    float normalized_y = clamp((anchor.y + 5000.0) / 10000.0, 0.0, 1.0);
    float meridian_curve = smoothstep(0.3, 0.7, normalized_y);
    // anchor.y += pc.spread * meridian_curve * 100.0;
    // anchor.x += sin(pc.total_time * 5.0 + anchor.y * 0.01) * 20.0;

    vec3 local_pos = vec3(0.0);

    // 5. GEOMETRY GENERATION
    if (pc.target_state == 88) {
        // Points use the physical fade
        gl_PointSize = (2.0 + (h2 * 8.0)) * point_scale_fade;
    } else {
        local_pos = SHAPE_LIBRARY[gl_VertexIndex];
        // Geometry ignores scale_fade, retaining full 1.0 volume
        vec3 scale = vec3(0.5 + h1 * 1.5, 0.5 + h2 * 3.0, 0.5 + h3 * 1.5) * 500.0;
        local_pos *= scale;

        float rx = (h1 * 6.28) + (pc.total_time * (h1 - 0.5) * 0.8);
        float ry = (h2 * 6.28) + (pc.total_time * (h2 - 0.5) * 0.8);
        float rz = (h3 * 6.28) + (pc.total_time * (h3 - 0.5) * 0.8);
        local_pos = rotate3D(rx, ry, rz) * local_pos;
    }

    vec3 final_pos = anchor + local_pos;
    
    // 6. DENSITY COLOR FADING (The Heatmap Effect)
    vec3 c_algae = unpackUnorm4x8(pc.algae_color).rgb;
    vec3 c_water = unpackUnorm4x8(pc.water_color).rgb;
    vec3 base_color = mix(c_water, c_algae, meridian_curve);
    
    // Define an "Overcrowded" energy color (e.g., bright neon pink/magenta)
    // You can customize this vec3 to whatever fits your engine's aesthetic
    vec3 heat_color = vec3(1.0, 0.2, 0.6); 
    
    // Shift the color based on the cell's heat. 
    // Crowded geometry will glow hot, sparse geometry stays natural.
    vec3 final_color = mix(base_color, heat_color, heat);
    final_color *= (0.75 + 0.5 * h1);

    v_worldPos = final_pos;
    gl_Position = pc.viewProj * vec4(final_pos, 1.0);

    fragColor = final_color;
    v_shapeID = pc.target_state;
    v_colorIdx = meridian_curve;
}
