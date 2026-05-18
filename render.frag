#version 460

layout(location = 0) in vec3 fragColor;
layout(location = 1) in vec3 v_worldPos;

layout(location = 0) out vec4 outColor;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    // --- THE MAGIC TRICK: Procedural Flat Normals ---
    // Calculate the rate of change of the world position relative to the screen pixels.
    // The cross product of these two tangents gives us a perfect perpendicular normal!
    vec3 dpdx = dFdx(v_worldPos);
    vec3 dpdy = dFdy(v_worldPos);
    vec3 normal = normalize(cross(dpdx, dpdy));

    // Environmental Lighting
    vec3 lightDir = normalize(vec3(0.5, 1.0, 0.8));
    vec3 viewDir = vec3(0.0, 0.0, 1.0);
    vec3 halfDir = normalize(lightDir + viewDir);

    // --- GLACIAL MUD MATERIAL ---
    float luminance = dot(fragColor, vec3(0.299, 0.587, 0.114));
    vec3 mudColor = vec3(0.35, 0.22, 0.12); 
    vec3 iceColor = vec3(0.70, 0.95, 1.00); 

    // Generate static grit based on the world position so it sticks to the ice
    float grit = hash(v_worldPos.xz * 0.1);

    float mudFactor = smoothstep(0.45, 0.1, luminance);
    vec3 material = mix(fragColor, mudColor, mudFactor + (grit * mudFactor * 0.5));

    // --- FACETED ICE LIGHTING ---
    // Harsh, sharp specular reflection for frozen surfaces
    float specular = pow(max(dot(normal, halfDir), 0.0), 64.0) * 1.5;

    // Diffuse shading to give the shard volume
    float diffuse = max(dot(normal, lightDir), 0.2);

    // Combine
    vec3 litColor = (material * diffuse) + (iceColor * specular);

    // Solid geometry! No alpha blending required. Early-Z will handle the rest.
    outColor = vec4(litColor, 1.0);
}
