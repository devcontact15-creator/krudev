#version 460 core
#include <flutter/runtime_effect.glsl>

uniform sampler2D videoTexture;
uniform float brightness;
uniform float contrast;
uniform float saturation;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy;
    vec4 color = texture(videoTexture, uv);
    
    color.rgb += brightness;
    color.rgb = ((color.rgb - 0.5) * max(contrast, 0.0)) + 0.5;
    
    float luminance = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
    color.rgb = mix(vec3(luminance), color.rgb, saturation);
    
    fragColor = color;
}
