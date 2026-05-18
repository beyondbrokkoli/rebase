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
    float total_time;
} pc;

layout(location = 0) out vec3 fragColor;
layout(location = 1) out vec3 v_worldPos;

// An elongated Bi-Pyramid (Ice Shard). 8 faces, 3 verts per face = 24 vertices.
const vec3 shard[24] = vec3[](
    // Top pyramid
    vec3(0, 1.5, 0), vec3(-1, 0, 1), vec3(1, 0, 1),    
    vec3(0, 1.5, 0), vec3(1, 0, 1), vec3(1, 0, -1),    
    vec3(0, 1.5, 0), vec3(1, 0, -1), vec3(-1, 0, -1),  
    vec3(0, 1.5, 0), vec3(-1, 0, -1), vec3(-1, 0, 1),  

    // Bottom pyramid
    vec3(0, -0.5, 0), vec3(1, 0, 1), vec3(-1, 0, 1),   
    vec3(0, -0.5, 0), vec3(1, 0, -1), vec3(1, 0, 1),   
    vec3(0, -0.5, 0), vec3(-1, 0, -1), vec3(1, 0, -1), 
    vec3(0, -0.5, 0), vec3(-1, 0, 1), vec3(-1, 0, -1)  
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
    uint v_id = gl_VertexIndex % 24;   

    // 1. Fetch CPU Macro-State
    vec3 anchor = vec3(
        vram.data[pc.pos_x_idx + p_id],
        vram.data[pc.pos_y_idx + p_id],
        vram.data[pc.pos_z_idx + p_id]
    );

    vec3 local_pos = shard[v_id];

    // 2. Procedural Deformation
    float h1 = hash(p_id);
    float h2 = hash(p_id + 1337);
    float h3 = hash(p_id + 42069);

    // CRANK THE SCALE: Multiplier set to 500.0 for massive boulders
    vec3 scale = vec3(
        0.5 + h1 * 1.5,
        0.5 + h2 * 3.0, 
        0.5 + h3 * 1.5
    ) * 500.0; 

    local_pos *= scale;

    // 3. Smooth, Majestic Tumble
    // Generate a unique, very slow rotation speed for this chunk (-0.5 to 0.5)
    float speed_x = (h1 - 0.5) * 0.8;
    float speed_y = (h2 - 0.5) * 0.8;
    float speed_z = (h3 - 0.5) * 0.8;

    // Combine static random starting angle with continuous time rotation
    float rx = (h1 * 6.28) + (pc.total_time * speed_x);
    float ry = (h2 * 6.28) + (pc.total_time * speed_y);
    float rz = (h3 * 6.28) + (pc.total_time * speed_z);

    local_pos = rotate3D(rx, ry, rz) * local_pos;

    // 4. Gentle Float
    // Replaced the erratic splash with a very slow, microscopic vertical heave
    float heave = sin(pc.total_time * 0.5 + h1 * 6.28) * 150.0;
    anchor.y += heave;

    vec3 final_world_pos = anchor + local_pos;
    gl_Position = pc.viewProj * vec4(final_world_pos, 1.0);
    v_worldPos = final_world_pos;

    // 5. Glacial Base Color
    vec3 c_abyss  = vec3(0.09, 0.11, 0.17);
    vec3 c_marine = vec3(0.18, 0.35, 0.58);
    vec3 c_cyan   = vec3(0.53, 0.86, 0.81);

    float dist = length(anchor.xz);
    float struct_norm = clamp(dist * 0.0001, 0.0, 1.0);
    
    // Smooth color banding
    vec3 base_color = mix(c_abyss, c_marine, struct_norm);
    if(struct_norm > 0.8) {
         base_color = mix(c_marine, c_cyan, (struct_norm - 0.8) * 5.0);
    }

    fragColor = base_color;
}
