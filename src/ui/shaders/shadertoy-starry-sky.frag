// https://www.shadertoy.com/view/MlSfzz

#define highp

float rand(vec2 uv) {
    const highp float a = 12.9898;
    const highp float b = 78.233;
    const highp float c = 43758.5453;
    highp float dt = dot(uv, vec2(a, b));
    highp float sn = mod(dt, 3.1415);
    return fract(sin(sn) * c);
}

void draw_stars(inout vec4 color, vec2 uv) {
    float t = sin(iTime * 2.0 * rand(-uv)) * 0.5 + 0.5;
    //color += step(0.99, stars) * t;
    color += smoothstep(0.975, 1.0, rand(uv)) * t;
}

#define nsin(x) (sin(x) * 0.5 + 0.5)

void draw_auroras(inout vec4 color, vec2 uv) {
    const vec4 aurora_color_a = vec4(0.0, 1.2, 0.5, 1.0);
    const vec4 aurora_color_b = vec4(0.0, 0.4, 0.6, 1.0);
    
    float t = nsin(-iTime + uv.x * 100.0) * 0.075 + nsin(iTime + uv.x * distance(uv.x, 0.5) * 100.0) * 0.1 - 0.5;
    t = 1.0 - smoothstep(uv.y - 4.0, uv.y * 2.0, t);
    
    vec4 final_color = mix(aurora_color_a, aurora_color_b, clamp(1.0 - uv.y * t, 0.0, 1.0));
    final_color += final_color * final_color;
    color += final_color * t * (t + 0.5) * 0.75;
}

void mainImage(out vec4 color, vec2 coord) {
    vec2 ps = vec2(1.0) / iResolution.xy;
    vec2 uv = coord * ps;
    color = vec4(0.0);
    
//    draw_stars(color, uv);
    draw_auroras(color, uv);
}
