#version 460
layout(location = 0) in vec3 fragColor;
layout(location = 1) in vec3 v_worldPos;
layout(location = 2) flat in uint v_shapeID;
layout(location = 0) out vec4 outColor;

void main() {
    vec3 dpdx = dFdx(v_worldPos);
    vec3 dpdy = dFdy(v_worldPos);
    vec3 normal = normalize(cross(dpdx, dpdy));

    vec3 lightDir = normalize(vec3(0.5, 1.0, 0.8));
    vec3 viewDir = vec3(0.0, 0.0, 1.0);
    vec3 halfDir = normalize(lightDir + viewDir);

    float diffuse = max(dot(normal, lightDir), 0.25);
    vec3 litColor = fragColor * diffuse;

    float specPower = (v_shapeID == 99) ? 16.0 : 48.0;
    float specIntensity = (v_shapeID == 99) ? 0.3 : 0.8;
    vec3 specTint = (v_shapeID == 99) ? vec3(0.9) : vec3(1.0);

    float specular = pow(max(dot(normal, halfDir), 0.0), specPower) * specIntensity;
    outColor = vec4(litColor + (specTint * specular), 1.0);
}
