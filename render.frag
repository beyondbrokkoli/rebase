#version 460

layout(location = 0) in vec3 fragColor;
layout(location = 1) in vec3 v_worldPos;
layout(location = 2) flat in uint v_shapeID;

layout(location = 0) out vec4 outColor;

void main() {
    if (v_shapeID == 88) {
        // --- POINT CLOUD RENDERING ---
        vec2 ptc = gl_PointCoord - vec2(0.5);
        float distSq = dot(ptc, ptc);

        if (distSq > 0.25) discard;

        // Exponential falloff creates a hot center and soft glowing edge
        float alpha = 1.0 - (sqrt(distSq) * 2.0);
        alpha = pow(alpha, 1.2); 
        
        // Emissive boost makes the colors pop against the dark background
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

        // Friendly ambient lighting (0.25 instead of 0.15)
        float diffuse = max(dot(normal, lightDir), 0.25);
        vec3 litColor = fragColor * diffuse;

        // Punchy, sharp specular highlights
        float specPower = 48.0;
        float specIntensity = 0.8;
        vec3 specTint = vec3(1.0); // Pure white specular looks cleanest on vibrant colors

        if (v_shapeID == 99) {
            // Asteroids remain slightly duller
            specPower = 16.0;
            specIntensity = 0.3;
            specTint = vec3(0.9);
        }

        float specular = pow(max(dot(normal, halfDir), 0.0), specPower) * specIntensity;
        litColor += (specTint * specular);

        outColor = vec4(litColor, 1.0);
    }
}
