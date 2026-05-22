#version 460

layout(location = 0) in vec3 fragColor;
layout(location = 1) in vec3 v_worldPos;
layout(location = 2) flat in uint v_shapeID;

layout(location = 0) out vec4 outColor;

// ... [existing inputs] ...

void main() {
    // 1. GENERATE DIVERSE BASE COLORS
    float spatial_wave = sin(v_worldPos.x * 0.00015) * cos(v_worldPos.z * 0.00015) * sin(v_worldPos.y * 0.0001);
    float norm_wave = spatial_wave * 0.5 + 0.5;

    // A richer, more diverse palette
    vec3 c_meridian = vec3(0.0, 0.25, 0.85); // Deep Blue
    vec3 c_cyan     = vec3(0.10, 0.85, 0.70); // Teal/Cyan
    vec3 c_gold     = vec3(1.0, 0.65, 0.10);  // High-contrast Gold

    vec3 swarm_color;
    if (norm_wave < 0.6) {
        swarm_color = mix(c_meridian, c_cyan, norm_wave * 1.66);
    } else {
        swarm_color = mix(c_cyan, c_gold, (norm_wave - 0.6) * 2.5);
    }

    // --- POINT CLOUD SPECIFIC LOGIC ---
    if (v_shapeID == 88) {
        // gl_PointCoord gives us a 2D coordinate from (0,0) to (1,1) across the point square
        vec2 ptc = gl_PointCoord - vec2(0.5);
        
        // Pythagorean distance from the center of the point
        float distSq = dot(ptc, ptc);
        
        // Discard pixels outside the circle radius (0.5^2 = 0.25)
        if (distSq > 0.25) {
            discard;
        }

        // Create a smooth glowing falloff from the center to the edge
        float alpha = 1.0 - (sqrt(distSq) * 2.0);
        
        // Boost the brightness so the points look like emissive light sources
        fragColor = swarm_color * alpha * 2.5; 
    } 
    // --- GEOMETRY SPECIFIC LOGIC ---
    else {
        // Optional: Add simple fake lighting to the geometry to make it pop
        vec3 normal = normalize(cross(dFdx(v_worldPos), dFdy(v_worldPos)));
        vec3 lightDir = normalize(vec3(0.5, 1.0, 0.3));
        float diffuse = max(dot(normal, lightDir), 0.2); // 0.2 ambient
        
        fragColor = swarm_color * diffuse;
    }
}
