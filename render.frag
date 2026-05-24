#version 460

layout(location = 0) in vec3 fragColor;
layout(location = 1) in vec3 v_worldPos;
layout(location = 2) flat in uint v_shapeID;
layout(location = 3) flat in float v_colorIdx;

layout(push_constant) uniform PushConstants {
    mat4 viewProj;                    // 0-63: 64 bytes (Row-Major memory)

    uint soa_upload_idx;              // 64-67: CPU writes SoA here
    uint aos_current_idx;             // 68-71: GPU translates AoS here
    uint aos_prev_idx;                // 72-75: GPU reads t-1 AoS from here
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

layout(location = 0) out vec4 outColor;

void main() {
    if (v_shapeID == 88) {
        // --- POINT CLOUD RENDERING ---
        vec2 ptc = gl_PointCoord - vec2(0.5);
        float distSq = dot(ptc, ptc);
        
        // Remove the hard discard! Replace it with a soft, anti-aliased edge.
        // This smoothly fades the alpha from 1.0 to 0.0 at the circle's edge.
        float circle_mask = 1.0 - smoothstep(0.15, 0.25, distSq);

        // Your existing inner glow math
        float glow = 1.0 - (sqrt(distSq) * 2.0);
        glow = max(0.0, glow); // Prevent negative numbers before pow()
        glow = pow(glow, 1.2);

        // Combine the mask and the glow
        float final_alpha = circle_mask * glow;

        outColor = vec4(fragColor * final_alpha * 2.8, 1.0);
    }
    else {
        // --- GEOMETRY RENDERING ---
        vec3 dpdx = dFdx(v_worldPos);
        vec3 dpdy = dFdy(v_worldPos);
        vec3 normal = normalize(cross(dpdx, dpdy));

        vec3 lightDir = normalize(vec3(0.5, 1.0, 0.8));
        vec3 viewDir = vec3(0.0, 0.0, 1.0);           
        vec3 halfDir = normalize(lightDir + viewDir);

        float diffuse = max(dot(normal, lightDir), 0.25); 
        
        // Specular intensity logic: 
        // Meridian (v_colorIdx ~0.0) gets high shine (1.8)
        // Algae (v_colorIdx ~1.0) gets matte finish (0.3)
        float spec_intensity = mix(1.8, 0.3, v_colorIdx); 
        float specular = pow(max(dot(normal, halfDir), 0.0), pc.highlight_power) * spec_intensity;

        vec3 final_shading = (fragColor * diffuse) + vec3(specular);
        outColor = vec4(final_shading, 1.0);
    }
}
