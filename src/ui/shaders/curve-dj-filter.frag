/* Libre Audio Suite - https://libreaudio.org
 * Copyright (C) 2026 Klaus Scheuermann <klaus@libreaudio.org>
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * This file is part of the Libre Audio Suite. It comes with ABSOLUTELY NO
 * WARRANTY; see the LICENSE file in the project root for the full terms.
 *
 * For some parts, a large language model was involved as a coding assistant.
 * The ideas, the design decisions and the listening behind it are purely human.
*/

/* ===========================================================================
   LAS DJ Filter - filter-response CURVE, Shadertoy port
   ---------------------------------------------------------------------------
   One rainbow trace showing what the DJ Filter's one knob is doing to the
   spectrum: a 2-pole high-pass sweeping up as the knob turns right, a 2-pole
   low-pass sweeping down as it turns left, both with the resonance knob
   lifting Q. Curve only: the background stays black and fully transparent
   (alpha 0), so it drops onto anything.

   Only the two filters are drawn for now -- the overdrive, the reverb send
   and the volume fadeout at the knob extremes are not reflected here.

   Every parameter that shapes the curve is a `uniform float` below. Drive
   them from your host. For standalone testing in the Shadertoy editor (which
   can't set custom uniforms), the defaults under USE_DEFAULTS take over.
   =========================================================================== */

#define DBMAX 18.0    /* top of the dB window (room for the Q peak) */
#define DBMIN -30.0   /* bottom of the dB window */
#define GLOW 0.60     /* glow strength (0 .. 1) */
#define FILL 0.12     /* shading under the curve, i.e. the passband (0 .. 1) */
#define FMIN 20.0     /* frequency axis min, Hz (left edge) */
#define FMAX 20000.0  /* frequency axis max, Hz (right edge), matches the analyser */

/* --- constants mirrored from djFilter.dsp -------------------------------- */
#define NEUTRAL    0.1     /* knob centre zone that passes clean */
#define FADE_WIDTH 0.05    /* knob travel over which dry crossfades to filtered */
#define HP_LO     20.0     /* high-pass corner at the neutral edge, Hz */
#define HP_HI  20000.0     /* high-pass corner at full right, Hz */
#define LP_LO     20.0     /* low-pass corner at full left, Hz */
#define LP_HI  20000.0     /* low-pass corner at the neutral edge, Hz */
#define QMIN       0.7     /* Q with the resonance knob down */
#define QMAX       6.0     /* Q with the resonance knob up (at full knob travel) */

/* standalone defaults (Shadertoy editor has no custom uniforms) */
#ifndef LIBREAUDIO_HOSTED
#define KNOB  (sin(iTime * 0.35))  /* filter knob, -1 .. 1 -- swept so it moves */
#define RES   0.5                  /* resonance, 0 .. 1 */
#define GLOWW 2.0                  /* glow radius, pixels */
#define THICK 1.5                  /* line thickness, pixels */
#else
/* adjustable plugin parameters */
uniform float u_knob;
uniform float u_emphasize_q;
#define KNOB  u_knob
#define RES   u_emphasize_q
#define GLOWW (2.0 * _dpf_scale_factor)
#define THICK (1.5 * _dpf_scale_factor)
#endif

float log10_(float x){ return log(x) * 0.43429448190325176; }

/* Filter position, normalised 0..1 within each active zone -- 0 at the neutral
   boundary, 1 at full travel. Same mapping as t_highpass / t_lowpass in the DSP. */
float tHighpass(){ return max(0.0, ( KNOB - NEUTRAL) / (1.0 - NEUTRAL)); }
float tLowpass (){ return max(0.0, (-KNOB - NEUTRAL) / (1.0 - NEUTRAL)); }

/* 2-pole (SVF) magnitude responses in dB, w = f / fc.
   |H_lp|^2 = 1 / ((1-w^2)^2 + (w/Q)^2), |H_hp|^2 = w^4 * the same denominator.
   The Q term is what draws the resonant peak -- no faked bump needed. */
float svfDen(float w, float q){
    float a = 1.0 - w * w;
    float b = w / q;
    return a * a + b * b;
}
float hpDb(float f, float fc, float q){
    float w = f / fc;
    float w2 = w * w;
    return 10.0 * log10_(w2 * w2 / svfDen(w, q));
}
float lpDb(float f, float fc, float q){
    float w = f / fc;
    return 10.0 * log10_(1.0 / svfDen(w, q));
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

/* Combined response of the two filter stages, dB.
   The DSP crossfades dry into filtered over FADE_WIDTH of knob travel, so the
   curve fades between flat and the full filter shape the same way. */
float fdb(float f){
    float th = tHighpass();
    float tl = tLowpass();

    float db = 0.0;

    if (th > 0.0){
        float fc = HP_LO * pow(HP_HI / HP_LO, th);
        float q  = QMIN * pow(QMAX / QMIN, RES * th);
        db += hpDb(f, fc, q) * min(1.0, th / FADE_WIDTH);
    }

    if (tl > 0.0){
        float fc = LP_HI * pow(LP_LO / LP_HI, tl);
        float q  = QMIN * pow(QMAX / QMIN, RES * tl);
        db += lpDb(f, fc, q) * min(1.0, tl / FADE_WIDTH);
    }

    return db;
}

/* curve height in height fractions, 0 = top */
float curveY(float t){
    /* x -> frequency, log axis */
    float freq = FMIN * pow(FMAX / FMIN, t);
    float db = min(DBMAX, fdb(freq));
    return (DBMAX - db) / (DBMAX - DBMIN);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 uv = fragCoord / iResolution.xy;
    float t  = uv.x;               // 0..1 left->right (frequency axis)
    float py = 1.0 - uv.y;         // 0 at top, 1 at bottom (matches the plugin)

    float y = curveY(t);

    /* Curve slope in pixels-of-y per pixel-of-x, by central difference one
       pixel either side. A 2-pole skirt squeezed into the dB window runs
       steeply: without this a vertical-only distance test pinches the stroke
       to a hairline and the line reads as broken. Central (not forward)
       difference so the DBMAX clamp kink stays symmetric. */
    float dtx = 1.0 / iResolution.x;
    float s = (curveY(t + dtx) - curveY(t - dtx)) * 0.5 * iResolution.y;

    /* perpendicular distance to the trace, in pixels */
    float d = abs(py - y) * iResolution.y * inversesqrt(1.0 + s * s);

    /* antialiased line coverage (constant width whatever the slope) */
    float hw = THICK * 0.5;
    float cov = 1.0 - smoothstep(hw, hw + 1.5, d);

    /* soft glow bloom around the trace (a wide gaussian falloff) */
    float gw = max(GLOWW, 0.001);
    float glow = exp(-(d * d) / (gw * gw)) * GLOW;

    vec3 col = rainbow(t);

    /* shade the passband: everything below the curve, kept faint so the
       spectrum behind it still reads */
    float aa = 1.5 / iResolution.y;
    float fill = smoothstep(-aa, aa, py - y) * FILL;

    /* composite: fill, then glow, then the crisp line on top */
    float a = fill;
    a = glow + a * (1.0 - glow);
    a = cov  + a * (1.0 - cov);
    /* Straight (non-premultiplied) alpha: DPF draws with
       glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA), so premultiplying here
       would darken the colour a second time -- the glow and the antialiased
       edges would fringe towards black instead of fading to transparent. */
    fragColor = vec4(col, a);
}
