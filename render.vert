#version 460

// THE FIX: Switch from float to uint so we can read the Index Buffer natively
layout(set = 0, binding = 0) readonly buffer MasterBuffer {
    uint data[];
} vram;

layout(push_constant) uniform PushConstants {
    mat4 viewProj;
    uint pos_x_idx; uint pos_y_idx; uint pos_z_idx;
    uint particle_count; float dt;
    uint vel_x_idx; uint vel_y_idx; uint vel_z_idx;
    uint target_state; uint push_active; uint pull_active;
    float mouse_x; float mouse_y;
    // THE FUSE: Added index offsets
    uint sorted_idx; uint cell_counters_idx; uint cell_offsets_idx;
} pc;

layout(location = 0) out vec3 fragColor;
layout(location = 1) out vec3 v_worldPos;
layout(location = 2) flat out uint v_shapeID;

const vec3 SHAPE_LIBRARY[14] = vec3[](
    vec3(0.0,  1.5,  0.0), vec3(0.0, -0.5,  0.0), vec3(-1.0, 0.0,  1.0),
    vec3( 1.0, 0.0,  1.0), vec3( 1.0, 0.0, -1.0), vec3(-1.0, 0.0, -1.0),
    vec3(-1.0, -1.0,  1.0), vec3( 1.0, -1.0,  1.0), vec3( 1.0,  1.0,  1.0),
    vec3(-1.0,  1.0,  1.0), vec3(-1.0, -1.0, -1.0), vec3( 1.0, -1.0, -1.0),
    vec3( 1.0,  1.0, -1.0), vec3(-1.0,  1.0, -1.0)
);

// The user's exact requested friendly palette
const vec3 PALETTE[7] = vec3[](
    vec3(1.00, 0.40, 0.70), // 0: Pink
    vec3(0.15, 0.40, 0.90), // 1: Blue
    vec3(0.65, 0.70, 0.75), // 2: Grey
    vec3(0.60, 0.45, 0.35), // 3: Brownish
    vec3(0.10, 0.50, 0.25), // 4: Dark Green
    vec3(0.40, 0.85, 1.00), // 5: Light Blue
    vec3(0.95, 0.15, 0.20)  // 6: Vibrant Red
);

float hash(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & uvec3(0x7fffffffU)) / float(0x7fffffff);
}

mat3 rotate3D(float x, float y, float z) {
    float cx = cos(x), sx = sin(x);
    float cy = cos(y), sy = sin(y);
    float cz = cos(z), sz = sin(z);
    return mat3(
        cy*cz, -cx*sz + sx*sy*cz,  sx*sz + cx*sy*cz,
        cy*sz,  cx*cz + sx*sy*sz, -sx*cz + cx*sy*sz,
       -sy,     sx*cy,             cx*cy
    );
}

void main() {
    // 1. The GPU gives us our sequential draw index
    uint p_id = gl_InstanceIndex;
    
    // 2. We use it to look up the physically sorted Particle ID!
    uint real_p_id = vram.data[pc.sorted_idx + p_id];

    // 3. We pull the raw floats safely using uintBitsToFloat
    vec3 anchor = vec3(
        uintBitsToFloat(vram.data[pc.pos_x_idx + real_p_id]),
        uintBitsToFloat(vram.data[pc.pos_y_idx + real_p_id]),
        uintBitsToFloat(vram.data[pc.pos_z_idx + real_p_id])
    );

    // Make sure we feed real_p_id to the hash so colors don't flicker!
    float h1 = hash(real_p_id);
    float h2 = hash(real_p_id + 1337);
    float h3 = hash(real_p_id + 42069);

    // ==============================================================
    // THE FIX: Unconditional assignment ensures the SPIR-V compiler 
    // permanently bakes the PointSize capability into the module.
    // ==============================================================
    gl_PointSize = 2.0 + (h1 * 10.0);

    vec3 local_pos;

    if (pc.target_state == 88) {
        local_pos = vec3(0.0);
        // gl_PointSize removed from here
    } else {
        local_pos = SHAPE_LIBRARY[gl_VertexIndex];
        vec3 scale = vec3(0.5 + h1 * 1.5, 0.5 + h2 * 3.0, 0.5 + h3 * 1.5) * 500.0;

        if (pc.target_state == 99) scale *= 1.8;

        local_pos *= scale;
        float rx = (h1 * 6.28) + (pc.dt * (h1 - 0.5) * 0.8);
        float ry = (h2 * 6.28) + (pc.dt * (h2 - 0.5) * 0.8);
        float rz = (h3 * 6.28) + (pc.dt * (h3 - 0.5) * 0.8);
        local_pos = rotate3D(rx, ry, rz) * local_pos;
    }

    anchor.y += sin(pc.dt * 0.5 + h1 * 6.28) * 150.0;
    vec3 final_world_pos = anchor + local_pos;
    
    gl_Position = pc.viewProj * vec4(final_world_pos, 1.0);
    v_worldPos = final_world_pos;
    v_shapeID = pc.target_state;

    // --- DISCRETE SPATIAL COLOR BANDING ---
    // Create large regions in 3D space (-1.0 to 1.0 roughly)
    float spatial_wave = sin(anchor.x * 0.00012) * cos(anchor.y * 0.00015) + sin(anchor.z * 0.0001);
    float norm_wave = spatial_wave * 0.5 + 0.5;

    // Map to our 7 colors. We add h1 noise so the borders between color regions are fuzzy/dithered
    float color_band = clamp((norm_wave * 6.99) + (h1 * 1.5 - 0.75), 0.0, 6.99);
    uint color_idx = uint(color_band);
    
    vec3 swarm_color = PALETTE[color_idx];

    // Give each individual particle a slight brightness variation (75% to 125%)
    swarm_color *= (0.75 + 0.5 * h2);

    fragColor = swarm_color; 
}
