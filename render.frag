#version 460

layout(location = 0) in vec3 fragColor;
layout(location = 1) in vec3 v_worldPos;
layout(location = 2) flat in uint v_shapeID;
layout(location = 3) flat in float v_colorIdx;

layout(push_constant) uniform PushConstants {
    mat4 viewProj;
    uint pos_x_idx; uint pos_y_idx; uint pos_z_idx;
    uint particle_count; float dt;
    float total_time; float spread; float highlight_power;
    uint algae_color; uint water_color; uint bg_color_a; uint bg_color_b;
    uint target_state;
    uint sorted_idx; uint cell_counters_idx; uint cell_offsets_idx;
} pc;

layout(location = 0) out vec4 outColor;

void main() {
    if (v_shapeID == 88) {
        // --- POINT CLOUD RENDERING ---
        vec2 ptc = gl_PointCoord - vec2(0.5);
        float distSq = dot(ptc, ptc);
        if (distSq > 0.25) discard;

        float alpha = 1.0 - (sqrt(distSq) * 2.0);
        alpha = pow(alpha, 1.2);
        outColor = vec4(fragColor * alpha * 2.8, 1.0);
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
