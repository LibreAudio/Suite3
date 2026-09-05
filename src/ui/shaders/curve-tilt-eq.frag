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
   LAS Tilt EQ - filter-response CURVE, Shadertoy port
   ---------------------------------------------------------------------------
   One rainbow trace showing the tilt the plugin is applying: lows and highs
   see-sawing about the Frequency knob. All three modes of tiltEQ.dsp are
   drawn from the same transfer functions the DSP uses --

     mode 0  Linear          fi.spectral_tilt, an 8-section pole/zero cascade
     mode 1  Shelf+Resonance fi.svf.ls -> fi.svf.hs (Simper SVF shelves)
     mode 2  Dual Shelf      1st-order fi.highshelf/lowshelf + a mirrored
                             fi.svf.bell pair

   Curve only: the background stays black and fully transparent (alpha 0), so
   it drops onto anything. The faint shading sits between the trace and the
   0 dB line, so boost and cut read apart at a glance.

   Everything is evaluated as the analog prototype, because the shader is never
   told the sample rate and so cannot prewarp. Measured against the compiled
   DSP that is worth < 0.25 dB up to 5 kHz at 44.1 kHz, growing towards Nyquist
   -- worst case ~7 dB at 20 kHz (Linear mode, tilt +12, freq 5 kHz), and it
   shrinks fourfold per doubling of the sample rate. If a sample-rate uniform
   ever reaches this widget, replacing every `f / fc` ratio below with
   tan(PI*f/SR) / tan(PI*fc/SR) makes the curve exact.

   The dB window is fixed and symmetric so the pivot sits mid-height. Tilt on
   its own stays inside it; Shelf + Resonance at high Q can reach +-43 dB, and
   those peaks clamp flat against the top and bottom edges.

   Every parameter that shapes the curve is a `uniform float` below. Drive
   them from your host. For standalone testing in the Shadertoy editor (which
   can't set custom uniforms), the defaults under USE_DEFAULTS take over.
   =========================================================================== */

#define DBMAX 18.0    /* top of the dB window (tilt is +-12, plus resonance) */
#define DBMIN -18.0   /* bottom - symmetric, so the pivot sits mid-height */
#define GLOW 0.60     /* glow strength (0 .. 1) */
#define FILL 0.12     /* shading between the curve and the 0 dB line (0 .. 1) */
#define FMIN 20.0     /* frequency axis min, Hz (left edge) */
#define FMAX 20000.0  /* frequency axis max, Hz (right edge), matches the analyser */

/* --- constants mirrored from tiltEQ.dsp ---------------------------------- */
#define LIN_ORDER 8         /* spectral-tilt order (mode 0) */
#define LIN_F0    10.0      /* Hz, roll-off band low edge */
#define LIN_F1    18000.0   /* Hz, band high edge */
#define DSQMIN    0.5       /* dual-shelf bell Q at zero resonance */
#define DSQMAX    6.0       /* ... at full resonance */

/* standalone defaults (Shadertoy editor has no custom uniforms) */
#ifndef LIBREAUDIO_HOSTED
#define MODE   (floor(mod(iTime / 6.0, 3.0)))  /* cycle the three modes */
#define TILT   (9.0 * sin(iTime * 0.5))        /* dB, -12 .. 12 -- swept so it moves */
#define FREQ   630.0                           /* Hz, 20 .. 20000 */
#define RES    0.707                           /* mode 1 Q, 0.4 .. 8 */
#define SPREAD 2.0                             /* mode 2 spread, 1 .. 20 */
#define DSRES  0.0                             /* mode 2 bell gain, dB, 0 .. 12 */
#define GLOWW  4.0                             /* glow radius, pixels */
#define THICK  3.0                             /* line thickness, pixels */
#else
/* adjustable plugin parameters (u_ + the Faust [symbol:] of each control) */
uniform float u_mode;
uniform float u_tilt;
uniform float u_freq;
uniform float u_res;
uniform float u_spread;
uniform float u_ds_res;
#define MODE   u_mode
#define TILT   u_tilt
#define FREQ   u_freq
#define RES    u_res
#define SPREAD u_spread
#define DSRES  u_ds_res
#define GLOWW  (2.0 * _dpf_scale_factor)
#define THICK  (1.5 * _dpf_scale_factor)
#endif

float log10_(float x){ return log(x) * 0.43429448190325176; }
float db2lin(float db){ return pow(10.0, db / 20.0); }

/* --- Simper state-variable filter (fi.svf) -------------------------------
   One stage is H(s) = m0 + m1*BP(s) + m2*LP(s) with s = j*f/fg and
   LP = 1/(s^2 + k*s + 1), BP = s/(s^2 + k*s + 1). Putting that over the
   common denominator D = (1 - x^2) + j*k*x leaves

        H = (m0*D + m2 + j*m1*x) / D,   x = f/fg

   so the magnitude is two vec2 lengths -- no complex division needed. The
   mix vectors and the fg / k warping below are copied straight out of the
   `svf` environment in filters.lib. */
float svfDb(float f, float fg, float k, float m0, float m1, float m2){
    float x = f / fg;
    vec2 den = vec2(1.0 - x * x, k * x);
    vec2 num = vec2(m0 * den.x + m2, m0 * den.y + m1 * x);
    return 20.0 * log10_(length(num) / length(den));
}
/* fi.svf.ls: fg = f0/sqrt(A), mix = (1, k*(A-1), A^2-1). Gain A^2 at DC. */
float svfLsDb(float f, float f0, float q, float g){
    float a = pow(10.0, g / 40.0);
    float k = 1.0 / q;
    return svfDb(f, f0 / sqrt(a), k, 1.0, k * (a - 1.0), a * a - 1.0);
}
/* fi.svf.hs: fg = f0*sqrt(A), mix = (A^2, k*(1-A)*A, 1-A^2). Gain A^2 at SR/2. */
float svfHsDb(float f, float f0, float q, float g){
    float a = pow(10.0, g / 40.0);
    float k = 1.0 / q;
    return svfDb(f, f0 * sqrt(a), k, a * a, k * (1.0 - a) * a, 1.0 - a * a);
}
/* fi.svf.bell: k = 1/(Q*A), mix = (1, k*(A^2-1), 0). Gain A^2 at f0. */
float svfBellDb(float f, float f0, float q, float g){
    float a = pow(10.0, g / 40.0);
    float k = 1.0 / (q * a);
    return svfDb(f, f0, k, 1.0, k * (a * a - 1.0), 0.0);
}

/* --- first-order JOS shelves (fi.lowshelf / fi.highshelf, N = 1) ----------
   filterbank(1, fx) splits into LP1 + HP1 at fx (the -3 dB crossover, not the
   half-gain point) and scales one band, so with w = f/fx:
     lowshelf  H = (g + j*w) / (1 + j*w)      -- g at DC, unity at SR/2
     highshelf H = (1 + j*g*w) / (1 + j*w)    -- unity at DC, g at SR/2 */
float lowShelf1Db(float f, float fx, float l0){
    float g = db2lin(l0);
    float w = f / fx;
    return 10.0 * log10_((g * g + w * w) / (1.0 + w * w));
}
float highShelf1Db(float f, float fx, float lpi){
    float g = db2lin(lpi);
    float w = f / fx;
    return 10.0 * log10_((1.0 + g * g * w * w) / (1.0 + w * w));
}

/* --- mode 0: Linear ------------------------------------------------------
   fi.spectral_tilt(N,f0,bw,alpha) is N sections of (a/b)*(s+b)/(s+a) with the
   poles spaced geometrically by r across the band and each zero pushed alpha
   steps off its pole -- that offset is what makes the straight log-log line.
   Evaluated section by section (rather than as the idealised straight line)
   so the flattening above LIN_F1 and the slight ripple both show up.

   compGain from the DSP is folded in at the end: the (LIN_F0/freq)^alpha
   factor and the Koff polynomial together drop the line to 0 dB at freq. */
float linearDb(float f){
    float alpha = TILT / 30.0;
    float r  = pow(LIN_F1 / LIN_F0, 1.0 / float(LIN_ORDER - 1));
    float f2 = f * f;

    float db = 0.0;
    for (int i = 0; i < LIN_ORDER; ++i){
        float fp = LIN_F0 * pow(r, float(i));           // minus pole i
        float fz = fp * pow(r, -alpha);                 // minus zero i
        db += 20.0 * log10_(fp / fz)                    // unity dc-gain scaling
            + 10.0 * log10_((f2 + fz * fz) / (f2 + fp * fp));
    }

    float koff = alpha * (4.70119 + alpha * (4.70851 - 0.13213 * alpha));
    return db + alpha * 20.0 * log10_(LIN_F0 / FREQ) - koff;
}

/* --- mode 1: Shelf + Resonance ------------------------------------------- */
float shelfResDb(float f){
    return svfLsDb(f, FREQ, RES, -TILT) + svfHsDb(f, FREQ, RES, TILT);
}

/* --- mode 2: Dual Shelf (symmetric) + resonance bells ---------------------
   Corners sit at freq*dsBh*spread and freq*dsBh/spread, dsBh = 10^(tilt/40).
   Their product is freq^2 * 10^(tilt/20), which is exactly the condition that
   makes |H| antisymmetric in dB about freq -- hence no pivot compensation.
   The bell pair is mirrored the same way (freq*spread and freq/spread). */
float dualShelfDb(float f){
    float bh = db2lin(TILT * 0.5);      // 10^(tilt/40)

    float db = highShelf1Db(f, FREQ * bh * SPREAD,  TILT)
             + lowShelf1Db (f, FREQ * bh / SPREAD, -TILT);

    float sgn = TILT < 0.0 ? -DSRES : DSRES;   // follow the shelf's direction
    float q   = DSQMIN + (DSRES / 12.0) * (DSQMAX - DSQMIN);

    return db + svfBellDb(f, FREQ * SPREAD, q,  sgn)
              + svfBellDb(f, FREQ / SPREAD, q, -sgn);
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

/* Response of the active mode, dB. Hard select, exactly like ba.selectn in
   the DSP -- every mode pivots at freq, so switching never jumps the curve. */
float fdb(float f){
    float m = floor(MODE + 0.5);
    if (m < 0.5) return linearDb(f);
    if (m < 1.5) return shelfResDb(f);
    return dualShelfDb(f);
}

/* curve height in height fractions, 0 = top */
float curveY(float t){
    /* x -> frequency, log axis */
    float freq = FMIN * pow(FMAX / FMIN, t);
    float db = clamp(fdb(freq), DBMIN, DBMAX);
    return (DBMAX - db) / (DBMAX - DBMIN);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 uv = fragCoord / iResolution.xy;
    float t  = uv.x;               // 0..1 left->right (frequency axis)
    float py = 1.0 - uv.y;         // 0 at top, 1 at bottom (matches the plugin)

    float y = curveY(t);

    /* Curve slope in pixels-of-y per pixel-of-x, by central difference one
       pixel either side. A resonant shelf squeezed into the dB window runs
       steeply: without this a vertical-only distance test pinches the stroke
       to a hairline and the line reads as broken. Central (not forward)
       difference so the DBMAX/DBMIN clamp kinks stay symmetric. */
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

    /* Shade between the trace and the 0 dB line, so the boosted half and the
       cut half of the tilt read apart. Kept faint so the spectrum behind it
       still shows through. */
    float zero = DBMAX / (DBMAX - DBMIN);
    float aa = 1.5 / iResolution.y;
    float lo = min(y, zero);
    float hi = max(y, zero);
    float fill = smoothstep(-aa, aa, py - lo) * (1.0 - smoothstep(-aa, aa, py - hi)) * FILL;

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
