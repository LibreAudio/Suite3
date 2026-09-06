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
   LAS Spring Reverb - three shaking springs, Shadertoy port
   ---------------------------------------------------------------------------
   Three horizontal rainbow springs, one per tank -- L on top, C in the middle,
   R at the bottom -- drawn as helices seen edge on. Each spring is clamped at
   both ends and shakes in its transverse modes:

     * how far it shakes, and how bright it is drawn <- the input level,
                             scaled by that tank's Spring L / C / R knob, so a
                             tank turned down barely stirs and fades away
     * how fast it shakes <- Tension: tighter springs run at a higher pitch,
                             carry more coils and shallower ones, and pass the
                             travelling coil wave along faster
     * how lush and how long it keeps shaking <- Dwell: a flatter modal
                             spectrum (more high modes alive at once) and more
                             weight on the slow level envelope, so a long dwell
                             carries on ringing after the input stops

   The springs are dispersive like the real thing: mode m sits slightly above
   m * f1, so the shapes never repeat exactly and the motion stays alive.

   Curve only: the background stays black and fully transparent (alpha 0), so
   it drops onto anything.

   Every parameter that shapes the springs is a `uniform float` below. Drive
   them from your host. For standalone testing in the Shadertoy editor (which
   can't set custom uniforms), the defaults below take over.
   =========================================================================== */

#define MODES 4      /* transverse modes summed per spring */
#define GLOW 1.0    /* glow strength (0 .. 1) */
#define YCENTER 0.36  /* where the group of three sits, 0 = top edge, 1 = bottom */
#define YSPACE 0.2  /* vertical distance between springs, height fractions */
#define SWAYMAX 0.075 /* peak centreline travel, height fractions */
#define SWAYIDLE 0.10 /* how much of that is left with no input at all */
#define BACKSHADE 0.0 /* brightness of the coil where it passes behind */
#define DIMMIN 0.10  /* how faint a tank turned fully down is drawn (0 .. 1) */
#define ENDS 0.1    /* how far in, in width fractions, the coils reach full depth */

/* standalone defaults (Shadertoy editor has no custom uniforms) */
#ifndef LIBREAUDIO_HOSTED
#define DWELL   0.5   /* 0 .. 1 */
#define TENSION 0.5   /* 0 .. 1 */
#define GAINL   0.0   /* Spring L, dB, -60 .. 0 */
#define GAINC  -6.0   /* Spring C, dB */
#define GAINR   0.0   /* Spring R, dB */
#define GLOWW   2.0   /* glow radius, pixels */
#define THICK   1.5   /* line thickness, pixels */
#else
/* adjustable plugin parameters (u_ + the Faust [symbol:] of each control) */
uniform float u_dwell;
uniform float u_tension;
uniform float u_Left;
uniform float u_Center;
uniform float u_Right;
#define DWELL   (u_dwell / 100.0)
#define TENSION (u_tension / 100.0)
#define GAINL   u_Left
#define GAINC   u_Center
#define GAINR   u_Right
#define GLOWW   (2.0 * _dpf_scale_factor)
#define THICK   (1.5 * _dpf_scale_factor)
#endif

#define TAU 6.28318530718
#define PI  3.14159265359

/* --- input level ---------------------------------------------------------
   Peak of the two input meters in dBFS, smoothed by the host over two time
   constants: iLevelSlow settles in about 5 s, iLevelFast in about 1.5 s. The
   smoothing cannot live here -- a fragment shader keeps no state between
   frames -- so these arrive already integrated, together with the integral of
   the slow envelope over time (iLevelSlowTime). A rate must be driven from
   that integral, never from iTime * level: scaling iTime would move every
   coil already on screen the moment the level changed. */
const float meterFloorDb = -40.0;
const float meterCeilDb  =   0.0;

#ifndef LIBREAUDIO_HOSTED
/* a plausible programme envelope so the springs move in the editor */
float levelSlowNorm(){ return 0.30 + 0.18 * sin(TAU * iTime * 0.09); }
float levelFastNorm(){ return levelSlowNorm() + 0.45 * pow(max(0.0, sin(TAU * iTime * 0.45)), 6.0); }
float levelTravel()  { return iTime * 0.35; }
#else
uniform float iLevelSlow;
uniform float iLevelFast;
uniform float iLevelSlowTime;
float norm_(float db){ return clamp((db - meterFloorDb) / (meterCeilDb - meterFloorDb), 0.0, 1.0); }
float levelSlowNorm(){ return norm_(iLevelSlow); }
float levelFastNorm(){ return norm_(iLevelFast); }
float levelTravel()  { return iLevelSlowTime; }
#endif

/* Spring L / C / R are dB trims. Amplitude follows the square root of the
   power gain, so a tank at -20 dB still visibly stirs instead of dropping to
   a tenth of the travel, while -60 dB reads as standing still. */
float springGain(float db){ return pow(10.0, db / 40.0); }

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

/* How hard the springs are being shaken, 0 .. ~1.2.

   Dwell decides which envelope carries the motion: at 0 it follows the fast
   one and settles as soon as the input does, at 1 it leans on the slow one and
   keeps swinging long after. The fast-minus-slow difference is what a
   transient looks like to the meters, so it is added on top as the whip that
   arrives with a hit. */
float drive(){
    float slow = levelSlowNorm();
    float fast = levelFastNorm();
    float sustain = mix(fast, slow, 0.25 + 0.6 * DWELL);
    float hit = max(fast - slow, 0.0);
    return min(sustain + 0.7 * hit, 1.2);
}

/* Transverse displacement of one clamped-clamped spring, height fractions.
   Mode m has the shape sin(m*PI*u), so every mode pins both ends. Its rate is
   slightly sharp of m * f1 (springs are dispersive: the higher the mode, the
   faster it travels), which keeps the sum from ever repeating. `lush` is the
   modal roll-off exponent -- small means the high modes stay loud. */
float sway(float u, float amp, float f1, float lush, float seed){
    float y = 0.0;
    float norm = 0.0;
    for (int m = 1; m <= MODES; ++m){
        float fm = float(m);
        float w = pow(fm, -lush);
        float rate = f1 * fm * sqrt(1.0 + (0.010 + 0.030 * TENSION) * fm * fm);
        y += w * sin(PI * fm * u) * sin(TAU * (rate * iTime + seed * fm));
        norm += w * w;
    }
    /* Quadratic sum, not the plain one: the modes drift in and out of phase,
       so dividing by sum(w) would leave the spring almost straight whenever
       they happen to cancel. */
    return amp * y * inversesqrt(norm);
}

/* The drawn coil: the centreline plus the helix seen edge on. `theta` comes
   back so the caller can shade the front of the coil brighter than the back.
   The coil depth tapers to nothing at both ends, where the spring is clamped. */
float coilY(float u, float yBase, float amp, float f1, float lush, float seed,
            float coils, float depth, float travel, out float theta)
{
    theta = TAU * (coils * u - travel);
    float ends = smoothstep(0.0, ENDS, u) * smoothstep(0.0, ENDS, 1.0 - u);
    return yBase + sway(u, amp, f1, lush, seed) + depth * ends * sin(theta);
}

/* One spring, returned premultiplied so the caller can just composite. `db` is
   that tank's Spring knob, `detune` and `seed` keep the three from moving in
   lockstep, the way the DSP gives each tank its own spread. */
vec4 spring(float u, float py, float yBase, float db, float detune, float seed){
    /* Tension: tighter means a higher shake rate, more and shallower coils and
       a faster travelling wave along them. Dwell: flatter modal spectrum. */
    float f1    = mix(0.55, 1.60, TENSION) * detune;
    float lush  = mix(2.20, 0.80, DWELL);
    float coils = mix(16.0, 30.0, TENSION);
    float depth = mix(0.026, 0.016, TENSION);

    /* Travel of the coil wave: a fixed drift plus the integrated level, so the
       coils run along the spring faster while the input is loud without the
       whole picture jumping when the level moves. */
    float travel = 0.06 * iTime + mix(0.10, 0.24, TENSION) * levelTravel() + seed;

    /* That tank's Spring knob sets both how far the spring travels and how
       bright it is drawn, so turning a tank down fades it out of the picture
       as well as stilling it. */
    float gain = springGain(db);
    float amp = SWAYMAX * mix(SWAYIDLE, 1.0, min(drive(), 1.0)) * gain;

    float th, thL, thR;
    float dtx = 1.0 / iResolution.x;
    float y  = coilY(u,       yBase, amp, f1, lush, seed, coils, depth, travel, th);
    float yL = coilY(u - dtx, yBase, amp, f1, lush, seed, coils, depth, travel, thL);
    float yR = coilY(u + dtx, yBase, amp, f1, lush, seed, coils, depth, travel, thR);

    /* Slope in pixels-of-y per pixel-of-x, by central difference. The coil runs
       near-vertical between its turns; without correcting for the slope a
       vertical-only distance test pinches the stroke to a hairline there and
       the spring reads as a row of dots. */
    float s = (yR - yL) * 0.5 * iResolution.y;
    float d = abs(py - y) * iResolution.y * inversesqrt(1.0 + s * s);

    /* front of the coil (coming towards the viewer) drawn bright, back dimmed */
    float front = 0.5 + 0.5 * cos(th);
    float shade = mix(BACKSHADE, 1.0, front);

    /* the wire is drawn slightly thinner on the far side of each turn, which is
       most of what makes a plain sine read as a coil */
    float hw = THICK * 0.5 * mix(0.72, 1.06, front);
    float cov = 1.0 - smoothstep(hw, hw + 1.5, d);
    float gw = max(GLOWW, 0.001);
    float glow = exp(-(d * d) / (gw * gw)) * GLOW * front;

    /* Faded on alpha rather than on colour: a dark line at full alpha would
       still blot the background out instead of letting it through. */
    float a = (cov + glow * (1.0 - cov)) * mix(DIMMIN, 1.0, gain);
    return vec4(rainbow(u) * shade * a, a);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 uv = fragCoord / iResolution.xy;
    float u  = uv.x;         // 0..1 left->right, along the springs
    float py = 1.0 - uv.y;   // 0 at top, 1 at bottom (matches the plugin)

    /* L on top, C in the middle, R at the bottom */
    vec4 sL = spring(u, py, YCENTER - YSPACE, GAINL, 1.00, 0.00);
    vec4 sC = spring(u, py, YCENTER,           GAINC, 0.86, 0.37);
    vec4 sR = spring(u, py, YCENTER + YSPACE,  GAINR, 1.13, 0.73);

    /* composite the three, premultiplied, top spring nearest the viewer */
    vec4 acc = sR;
    acc = sC + acc * (1.0 - sC.a);
    acc = sL + acc * (1.0 - sL.a);

    /* Straight (non-premultiplied) alpha: DPF draws with
       glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA), so premultiplying here
       would darken the colour a second time -- the glow and the antialiased
       edges would fringe towards black instead of fading to transparent. */
    fragColor = vec4(acc.a > 0.0001 ? acc.rgb / acc.a : vec3(0.0), acc.a);
}
