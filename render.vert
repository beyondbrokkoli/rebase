#version 460

layout(set = 0, binding = 0) readonly buffer MasterBuffer {
    float data[];
} vram;

layout(push_constant) uniform PushConstants {
    mat4 viewProj;
    uint pos_x_idx;
    uint pos_y_idx;
    uint pos_z_idx;
    uint particle_count;
    float dt;
    uint vel_x_idx;
    uint vel_y_idx;
    uint vel_z_idx;
    uint target_state;
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
    uint p_id = gl_InstanceIndex;
    vec3 anchor = vec3(
        vram.data[pc.pos_x_idx + p_id],
        vram.data[pc.pos_y_idx + p_id],
        vram.data[pc.pos_z_idx + p_id]
    );

    float h1 = hash(p_id);
    float h2 = hash(p_id + 1337);
    float h3 = hash(p_id + 42069);

    vec3 local_pos;

    // --- DYNAMIC STATE BRANCHING ---
    if (pc.target_state == 88) {
        local_pos = vec3(0.0);
        gl_PointSize = 2.0 + (h1 * 8.0);
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

    // --- CALCULATE COLOR HERE (Faster, passes via fragColor) ---
    float spatial_wave = sin(anchor.x * 0.00015) * cos(anchor.z * 0.00015) * sin(anchor.y * 0.0001);
    float norm_wave = spatial_wave * 0.5 + 0.5;

    vec3 c_meridian = vec3(0.0, 0.25, 0.85);
    vec3 c_cyan     = vec3(0.10, 0.85, 0.70);
    vec3 c_gold     = vec3(1.0, 0.65, 0.10);  

    vec3 swarm_color;
    if (norm_wave < 0.6) {
        swarm_color = mix(c_meridian, c_cyan, norm_wave * 1.66);
    } else {
        swarm_color = mix(c_cyan, c_gold, (norm_wave - 0.6) * 2.5);
    }

    swarm_color = mix(swarm_color, vec3(h1, h2, h3), 0.15);

    if (pc.target_state == 99) {
        swarm_color = mix(vec3(0.04, 0.06, 0.10), vec3(0.10, 0.25, 0.35), h2);
    }

    // Output to fragment shader!
    fragColor = swarm_color; 
}
