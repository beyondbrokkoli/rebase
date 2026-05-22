#version 460
layout(set = 0, binding = 0) readonly buffer MasterBuffer { float data[]; } vram;
layout(push_constant) uniform PushConstants {
    mat4 viewProj; uint pos_x_idx; uint pos_y_idx; uint pos_z_idx;
    uint particle_count; float dt;
    uint vel_x_idx; uint vel_y_idx; uint vel_z_idx; uint target_state;
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

const vec3 PALETTE[7] = vec3[](
    vec3(1.00, 0.40, 0.70), vec3(0.15, 0.40, 0.90), vec3(0.65, 0.70, 0.75),
    vec3(0.60, 0.45, 0.35), vec3(0.10, 0.50, 0.25), vec3(0.40, 0.85, 1.00), vec3(0.95, 0.15, 0.20)
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

void main() {
    uint p_id = gl_InstanceIndex;
    vec3 anchor = vec3(vram.data[pc.pos_x_idx + p_id], vram.data[pc.pos_y_idx + p_id], vram.data[pc.pos_z_idx + p_id]);
    float h1 = hash(p_id); float h2 = hash(p_id + 1337); float h3 = hash(p_id + 42069);

    vec3 local_pos = SHAPE_LIBRARY[gl_VertexIndex];
    vec3 scale = vec3(0.5 + h1 * 1.5, 0.5 + h2 * 3.0, 0.5 + h3 * 1.5) * 500.0;
    if (pc.target_state == 99) scale *= 1.8;
    local_pos *= scale;
    
    local_pos = rotate3D((h1 * 6.28) + (pc.dt * (h1 - 0.5) * 0.8), (h2 * 6.28) + (pc.dt * (h2 - 0.5) * 0.8), (h3 * 6.28) + (pc.dt * (h3 - 0.5) * 0.8)) * local_pos;

    anchor.y += sin(pc.dt * 0.5 + h1 * 6.28) * 150.0;
    vec3 final_world_pos = anchor + local_pos;

    gl_Position = pc.viewProj * vec4(final_world_pos, 1.0);
    v_worldPos = final_world_pos;
    v_shapeID = pc.target_state;

    float spatial_wave = sin(anchor.x * 0.00012) * cos(anchor.y * 0.00015) + sin(anchor.z * 0.0001);
    fragColor = PALETTE[uint(clamp(((spatial_wave * 0.5 + 0.5) * 6.99) + (h1 * 1.5 - 0.75), 0.0, 6.99))] * (0.75 + 0.5 * h2);
}
