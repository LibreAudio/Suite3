// ChorusScope - standalone Shadertoy port of the Vocal Doubler rainbow LFO traces.
// Self-contained: computes both traces in-shader, no iChannel needed.
// Paste into a new Shadertoy shader (Image tab) and hit Alt+Enter.

uniform float hpHz; // high-pass corner

// -- palette: the 7 Libre Audio rainbow stops --
vec3 rainbow(float t){
    t = clamp(t, 0.0, 1.0);
    vec3 c0=vec3(255.,191.,203.)/255., c1=vec3(255.,223.,173.)/255., c2=vec3(210.,253.,211.)/255.,
         c3=vec3(190.,241.,255.)/255., c4=vec3(195.,217.,255.)/255., c5=vec3(218.,193.,243.)/255.,
         c6=vec3(255.,220.,245.)/255.;
    float x = t*6.0; float f = fract(x); int i = int(floor(x));
    vec3 a = i==0?c0:i==1?c1:i==2?c2:i==3?c3:i==4?c4:i==5?c5:c6;
    vec3 b = i==0?c1:i==1?c2:i==2?c3:i==3?c4:i==4?c5:c6;
    return mix(a, b, f);
}

// distance from point p to segment a-b
float segDist(vec2 p, vec2 a, vec2 b){
    vec2 pa=p-a, ba=b-a; float t=clamp(dot(pa,ba)/max(dot(ba,ba),1e-6),0.0,1.0);
    return length(pa-ba*t);
}

// -- scope model (ported from the JS ChorusScope) --
// t01 = 0..1 across the display maps to 20 Hz .. 20 kHz (log).
const float FMIN = 20.0;
const float FMAX = 20000.0;
const float DB_MAX = 18.0;
const float DB_MIN = -42.0;

float normToFreq(float t){ return FMIN * pow(FMAX/FMIN, t); }

// combined 48 dB/oct LP + HP response + a presence bell, in dB.
// tweak these four to taste - they are the "knobs".
float responseDb(float f){
    float lpHz = 8000.0;   // low-pass corner
    float presence = 0.2;   // 0..1, bell around 2 kHz
    float presDb = (presence - 0.5) * 24.0;
    float x = log2(f/2000.0);
    float presBell = presDb * exp(-(x*x)/(2.0*0.9*0.9));
    float lp = -10.0 * log(1.0 + pow(f/lpHz, 16.0)) / log(10.0);
    float hp = -10.0 * log(1.0 + pow(hpHz/f, 16.0)) / log(10.0);
    return lp + hp + presBell;
}

// baseline y (pixels, top-down) that both traces ride on
float baseY(float t01, float H){
    float db = min(DB_MAX, responseDb(normToFreq(t01)));
    return (DB_MAX - db) / (DB_MAX - DB_MIN) * H;
}

// one animated LFO trace: baseline + sine wiggle. hz = LFO rate, amp = px, ph = phase.
float traceY(float t01, float H, float hz, float amp, float ph){
    const float WIN = 2.0;                       // seconds shown across the width
    float y = baseY(t01, H) - amp * sin(6.28318530718 * (t01 * hz * WIN - ph));
    return clamp(y, -40.0, H + 40.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 res = iResolution.xy;
    float px = fragCoord.x;
    float py = res.y - fragCoord.y;              // flip to top-down like SVG
    float t  = clamp(px / res.x, 0.0, 1.0);
    float H  = res.y;

    // -- trace parameters (mode2 = show the 2nd trace + fill) --
    bool  mode2 = true;
    float depth = 1.0;                           // 0..1
    float glow  = 0.25;                           // halo strength 0..~0.5
    float fillO = 0.50;                           // inter-trace fill opacity

    float a1 = 10.0 + depth * 20.0;              // deep LFO swing
    float a2 = a1 * 0.75;
    float hz1 = 0.9, hz2 = 1.35;                  // the two LFO rates
    float ph1 = iTime * hz1;
    float ph2 = iTime * hz2 + 0.25;

    // sample the trace at this column and one step over, for a proper AA segment
    float dx = 1.0 / res.x;
    float t0 = t, t1 = clamp(t + dx, 0.0, 1.0);
    float x0 = t0 * res.x, x1 = t1 * res.x;

    float y1a = traceY(t0, H, hz1, a1, ph1), y1b = traceY(t1, H, hz1, a1, ph1);
    float d1  = segDist(vec2(px,py), vec2(x0,y1a), vec2(x1,y1b));
    float cov = max(1.0-smoothstep(2.0,4.0,d1), (1.0-smoothstep(6.0,12.0,d1))*glow);

    float fill = 0.0;
    if (mode2)
    {
        float y2a = traceY(t0, H, hz2, a2, ph2), y2b = traceY(t1, H, hz2, a2, ph2);
        float d2  = segDist(vec2(px,py), vec2(x0,y2a), vec2(x1,y2b));
        cov = max(cov, max(1.0-smoothstep(2.0,4.0,d2), (1.0-smoothstep(6.0,12.0,d2))*glow));
        float lo = min(y1a, y2a), hi = max(y1a, y2a);
        fill = smoothstep(lo-0.5,lo+0.5,py) * (1.0-smoothstep(hi-0.5,hi+0.5,py)) * fillO;
    }

    float alpha = cov + fill*(1.0-cov);
    fragColor   = vec4(rainbow(t) * alpha, alpha);
}
