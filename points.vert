#version 460
layout(set = 0, binding = 0) readonly buffer MasterBuffer { float data[]; } vram;
layout(push_constant) uniform PushConstants {
    mat4 viewProj; uint pos_x_idx; uint pos_y_idx; uint pos_z_idx;
    uint particle_count; float dt;
    uint vel_x_idx; uint vel_y_idx; uint vel_z_idx; uint target_state;
} pc;

layout(location = 0) out vec3 fragColor;

const vec3 PALETTE[7] = vec3[](
    vec3(1.00, 0.40, 0.70), vec3(0.15, 0.40, 0.90), vec3(0.65, 0.70, 0.75),
    vec3(0.60, 0.45, 0.35), vec3(0.10, 0.50, 0.25), vec3(0.40, 0.85, 1.00), vec3(0.95, 0.15, 0.20)
);

float hash(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & uvec3(0x7fffffffU)) / float(0x7fffffff);
}

void main() {
    uint p_id = gl_InstanceIndex;
    vec3 anchor = vec3(vram.data[pc.pos_x_idx + p_id], vram.data[pc.pos_y_idx + p_id], vram.data[pc.pos_z_idx + p_id]);
    float h1 = hash(p_id); 
    float h2 = hash(p_id + 1337);

    anchor.y += sin(pc.dt * 0.5 + h1 * 6.28) * 150.0;
    
    // Calculate final position first
    vec4 clip_pos = pc.viewProj * vec4(anchor, 1.0);
    gl_Position = clip_pos;

    // Scale point size inversely by depth (clip_pos.w), clamped to a minimum of 1 pixel
    float base_size = 2.0 + (h1 * 4.0);
    gl_PointSize = max(1.0, base_size / max(1.0, clip_pos.w * 0.005));

    float spatial_wave = sin(anchor.x * 0.00012) * cos(anchor.y * 0.00015) + sin(anchor.z * 0.0001);
    fragColor = PALETTE[uint(clamp(((spatial_wave * 0.5 + 0.5) * 6.99) + (h1 * 1.5 - 0.75), 0.0, 6.99))] * (0.75 + 0.5 * h2);
}
