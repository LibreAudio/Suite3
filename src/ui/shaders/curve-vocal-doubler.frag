/* ===========================================================================
   LAS Vocal Doubler (v8) - modulation-scope CURVE, Shadertoy port
   ---------------------------------------------------------------------------
   Two rainbow voice traces riding on the wet-EQ response (HP + LP + presence
   bell), with the De-Ess dynamic downward shelf on top. Curve only: the
   background stays black and fully transparent (alpha 0), so it drops onto
   anything.

   Every parameter that shapes the curve is a `uniform float` below. Drive
   them from your host. For standalone testing in the Shadertoy editor (which
   can't set custom uniforms), leave USE_DEFAULTS at 1 to use the constants.
   =========================================================================== */

#define DBMAX 18.0   /* top of the dB window */
#define DBMIN -42.0  /* bottom of the dB window */
#define WIN  2.0     /* time window shown, seconds */
#define THICK 3.0    /* line thickness, pixels */
#define GLOW 0.60    /* glow strength (0 .. 1) */
#define GLOWW 7.0    /* glow radius, pixels */
#define FILL 0.35    /* fill opacity between the two voices (0 .. 1) */
#define FMIN 20.0    /* frequency axis min, Hz (left edge) */
#define FMAX 10000.0 /* frequency axis max, Hz (right edge) */

#define DEESSFREQ 3000.0 /* De-Ess shelf crossover, Hz */
#define LPRES 0.0        /* low-pass resonance bump  (0 .. 1) */
#define HPRES 0.0        /* high-pass resonance bump (0 .. 1) */

/* standalone defaults (Shadertoy editor has no custom uniforms) */
#ifndef LIBREAUDIO_HOSTED
#define R1       0.55   /* voice 1 trace rate, Hz */
#define R2       0.85   /* voice 2 trace rate, Hz */
#define DEPTH    0.35    /* trace amplitude / wet depth (0 .. 1) */
#define SHOWB    1.0     /* draw the 2nd voice? (0 or 1) - on in 1/3 Doubler & 2-voice ADT */
#define LPHZ     7000.0   /* wet-EQ low-pass corner, Hz */
#define HPHZ     20.0     /* wet-EQ high-pass corner, Hz */
#define PRESENCE 0.62    /* presence bell (0 .. 1, 0.5 = flat), +-12 dB at 2 kHz */
#define DEESS    0.6     /* De-Ess amount (0 .. 1) */
#else
/* adjustable plugin parameters */
uniform float u_adt_2voice;
uniform float u_adt_wow_depth;
uniform float u_adt_wow_rate;
uniform float u_deess_amount;
uniform float u_deess_meter;
uniform float u_doubler_wander_depth;
uniform float u_doubler_wander_rate;
uniform float u_eq_hp;
uniform float u_eq_lp;
uniform float u_mode;
uniform float u_presence;
uniform float u_take_pitch;
uniform float u_take_timing;
#define R1 (u_mode == 0.0 ? (u_adt_wow_rate / 5.0) : u_mode == 1.0 ? (u_doubler_wander_rate / 2.0) : 0.55)
#define R2 (u_mode == 0.0 ? (u_adt_wow_rate / 5.0 * 0.73) : u_mode == 1.0 ? (u_doubler_wander_rate / 2.0 * 1.21) : 0.85)
#define DEPTH (u_mode == 0.0 ? (u_adt_wow_depth / 10.0) : u_mode == 1.0 ? (u_doubler_wander_depth / 25.0) : (u_take_timing / 80.0) + (u_take_pitch / 60.0))
#define SHOWB (u_mode == 1.0 || (u_mode == 0.0 && u_adt_2voice == 2.0) ? 1.0 : 0.0)
#define LPHZ u_eq_lp
#define HPHZ u_eq_hp
#define PRESENCE ((u_presence + 12.0) / 24.0)
#define DEESS (u_deess_amount * 0.01)
#endif

#define TAU 6.28318530718
#define REF_H 210.0   /* reference scope height the plugin's px amplitudes assume */

float log10_(float x){ return log(x) * 0.43429448190325176; }
float log2_ (float x){ return log(x) * 1.44269504088896341; }

/* resonance peak on the filter response (Gaussian in log-freq) */
float bump(float f, float fc, float res){
    if (res < 0.001) return 0.0;
    float x = log2_(f / fc);
    return res * 17.0 * exp(-(x * x) / (2.0 * 0.45 * 0.45));
}

/* presence bell: +-12 dB, centred at 2 kHz, wide (sigma 0.9 octaves) */
float presBell(float f){
    float presDb = (PRESENCE - 0.5) * 24.0;
    if (abs(presDb) < 0.05) return 0.0;
    float x = log2_(f / 2000.0);
    return presDb * exp(-(x * x) / (2.0 * 0.9 * 0.9));
}

/* wet-EQ magnitude response, dB */
float fdb(float f){
    float lp = -10.0 * log10_(1.0 + pow(f / LPHZ, 16.0));
    float hp = -10.0 * log10_(1.0 + pow(HPHZ / f, 16.0));
    return lp + hp + bump(f, LPHZ, LPRES) + bump(f, HPHZ, HPRES) + presBell(f);
}

/* exact 7-stop scope palette (evenly spaced), lerped in sRGB like the SVG gradient */
vec3 rainbow(float x){
    x = clamp(x, 0.0, 1.0) * 6.0;      // 7 stops -> 6 segments
    int i = int(floor(x));
    float f = fract(x);
    vec3 c0 = vec3(1.000, 0.749, 0.796); // #ffbfcb
    vec3 c1 = vec3(1.000, 0.875, 0.678); // #ffdfad
    vec3 c2 = vec3(0.824, 0.992, 0.827); // #d2fdd3
    vec3 c3 = vec3(0.745, 0.945, 1.000); // #bef1ff
    vec3 c4 = vec3(0.765, 0.851, 1.000); // #c3d9ff
    vec3 c5 = vec3(0.855, 0.757, 0.953); // #dac1f3
    vec3 c6 = vec3(1.000, 0.863, 0.961); // #ffdcf5
    vec3 a = c0, b = c1;
    if      (i == 1){ a = c1; b = c2; }
    else if (i == 2){ a = c2; b = c3; }
    else if (i == 3){ a = c3; b = c4; }
    else if (i == 4){ a = c4; b = c5; }
    else if (i >= 5){ a = c5; b = c6; }
    return mix(a, b, f);
}

/* baseline (wet-EQ response + De-Ess shelf) in height fractions, 0 = top */
float baseY(float t, float env){
    /* x -> frequency, log axis */
    float freq = FMIN * pow(FMAX / FMIN, t);

    /* wet-EQ response, normalised into the dB window */
    float db = min(DBMAX, fdb(freq));
    float baseNorm = (DBMAX - db) / (DBMAX - DBMIN);

    /* De-Ess: downward high-shelf above the crossover, softer knee (^3) than
       the chorus. The shelf pulls the curve DOWN (bigger y). */
    float wsh = 1.0 / (1.0 + pow(DEESSFREQ / freq, 3.0));
    float shelfNorm = (DEESS * 15.0 * env) * wsh / (DBMAX - DBMIN);

    return baseNorm + shelfNorm;
}

/* One voice trace riding on the baseline. `phase` is the scroll position in
   cycles, already wrapped to [0,1) by the caller - only its fractional part
   matters, and keeping it small stops the sine argument from quantising. */
float traceY(float t, float env, float rate, float amp, float phase){
    return baseY(t, env) - amp * sin(TAU * (t * rate * WIN - phase));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 uv = fragCoord / iResolution.xy;
    float t  = uv.x;               // 0..1 left->right (time & frequency axis)
    float py = 1.0 - uv.y;         // 0 at top, 1 at bottom (matches the plugin)

    /* De-Ess amount animated per frame to read as dynamic (sibilant) gain
       reduction, faster pump than the chorus, matching v8 */
    float env = 0.0;
    if (DEESS > 0.001){
#ifndef LIBREAUDIO_HOSTED
        max(0.0, 0.6 * sin(TAU * fract(iTime * 4.0)) + 0.4 * sin(TAU * fract(iTime * 6.3) + 1.1));
#else
        env = u_deess_meter / 30.0;
#endif
    }

    /* trace amplitudes, in height fractions (plugin: a1 = 4 + depth*10 px @210, a2 = 0.75*a1) */
    float a1 = (4.0 + DEPTH * 10.0) / REF_H;
    float a2 = a1 * 0.75;

    /* Scroll positions, wrapped to [0,1). Wrapping here is what keeps the sine
       argument small: unwrapped, TAU * rate * iTime lands where a single float
       step is a large fraction of a radian and the trace visibly staircases. */
    float ph1 = fract(R1 * iTime);
    float ph2 = fract(R2 * iTime + 0.25);

    float y1 = traceY(t, env, R1, a1, ph1);
    float y2 = traceY(t, env, R2, a2, ph2);

    /* Curve slope in pixels-of-y per pixel-of-x, by central difference one
       pixel either side. The EQ skirts are ~160 dB/decade, so squeezed into
       the dB window they run near-vertical: without this a vertical-only
       distance test pinches the stroke to a hairline and the line reads as
       broken. Central (not forward) difference so the DBMAX clamp kink stays
       symmetric. */
    float dtx = 1.0 / iResolution.x;
    float s1 = (traceY(t + dtx, env, R1, a1, ph1) - traceY(t - dtx, env, R1, a1, ph1))
             * 0.5 * iResolution.y;
    float s2 = (traceY(t + dtx, env, R2, a2, ph2) - traceY(t - dtx, env, R2, a2, ph2))
             * 0.5 * iResolution.y;

    /* perpendicular distance to each trace, in pixels */
    float d1 = abs(py - y1) * iResolution.y * inversesqrt(1.0 + s1 * s1);
    float d2 = abs(py - y2) * iResolution.y * inversesqrt(1.0 + s2 * s2);

    /* antialiased line coverage (constant width whatever the slope) */
    float hw  = THICK * 0.5;
    float aa  = 1.5 / iResolution.y;
    float c1 = 1.0 - smoothstep(hw, hw + 1.5, d1);
    float c2 = (SHOWB > 0.5) ? 1.0 - smoothstep(hw, hw + 1.5, d2) : 0.0;
    float cov = max(c1, c2);

    /* soft glow bloom around each trace (a wide gaussian falloff) */
    float gw = max(GLOWW, 0.001);
    float g1 = exp(-(d1 * d1) / (gw * gw));
    float g2 = (SHOWB > 0.5) ? exp(-(d2 * d2) / (gw * gw)) : 0.0;
    float glow = max(g1, g2) * GLOW;

    vec3 col = rainbow(t);

    /* fill between the two voice traces (FILL defaults to the SVG's fillOpacity) */
    float fill = 0.0;
    if (SHOWB > 0.5){
        float lo = min(y1, y2), hi = max(y1, y2);
        float band = smoothstep(-aa, aa, py - lo) * smoothstep(-aa, aa, hi - py);
        fill = band * FILL;
    }

    /* composite: fill, then glow, then the crisp lines on top */
    float a = fill;
    a = glow + a * (1.0 - glow);
    a = cov  + a * (1.0 - cov);
    /* premultiplied output: black background is alpha 0 and lifts away cleanly */
    fragColor = vec4(col * a, a);
}
