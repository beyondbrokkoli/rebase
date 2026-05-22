#version 460
layout(location = 0) in vec3 fragColor;
layout(location = 0) out vec4 outColor;

void main() {
    vec2 ptc = gl_PointCoord - vec2(0.5);
    float distSq = dot(ptc, ptc);
    
    if (distSq > 0.25) discard;

    float alpha = pow(1.0 - (sqrt(distSq) * 2.0), 1.2);
    outColor = vec4(fragColor * alpha * 2.8, 1.0);
}
