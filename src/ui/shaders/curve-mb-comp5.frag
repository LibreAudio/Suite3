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
   LAS 5-Band Compressor - gain-reduction CURVE, Shadertoy port
   ---------------------------------------------------------------------------
   Two traces showing what the compressor is doing to the audio right now:

     solid  - the mid channel
     dashed - the side channel, fainter, drawn underneath

   With Channel Link at 100% the two sit exactly on top of each other and only
   the solid line is visible; the dashed one appearing from under it is the
   image starting to move, which is the thing worth seeing in a mid/side
   compressor.

   The traces are not a stair of five band gains. They are the response of the
   shelf cascade in mbComp5.dsp evaluated section by section --

     y = x : lowShelf(f1, g0-g1) : lowShelf(f2, g1-g2)
           : lowShelf(f3, g2-g3) : lowShelf(f4, g3-g4) : *(g4)

   -- so the corner frequencies are the crossovers (after the DSP's ascending
   clamp) and the steepness of each step is the Slope setting. At 6 dB/oct the
   steps smear into one another and the curve reads as a tilt; at 24 dB/oct the
   bands stand apart. That difference is real, it is what the audio gets, and a
   five-step bar chart would hide it.

   Each band's gain is its metered gain reduction plus whatever bandStatic()
   makes of Makeup, Bypass and Listen, exactly as the DSP folds them:

     audible, not bypassed   ->  gr + Makeup
     bypassed                ->  0 dB          (the meter already reads 0)
     muted by another Listen ->  Listen Floor

   so the curve doubles as the plugin's EQ display when Ratio sits at 1, and
   Listen shows as the steep tilt it actually is rather than as silence.

   Curve only: the background stays black and fully transparent (alpha 0), so
   it drops onto the analyser. The faint shading hangs off the mid trace and
   fades to nothing at the 0 dB line, so the depth of the reduction reads at a
   glance without a slab of tint sitting over the spectrum.

   The dB window is +12 to -24, the bottom matching the per-band GR meters. A
   trace that runs past either edge is not held there: it leaves the frame and
   the shading alone carries the band until it comes back. Nothing in this
   plugin draws a flat line unless a band really is flat.

   Two things the curve does not know about. Everything is evaluated as the
   analog prototype, because the shader is never told the sample rate and so
   cannot prewarp. Measured against the compiled sections, a crossover at
   1 kHz carrying 12 dB tracks to within 0.04 dB everywhere below 20 kHz at
   48 kHz; the error only matters for the top crossover pushed high with a big
   step across it - 8 kHz carrying 24 dB is 2.6 dB out around 13 kHz at
   44.1 kHz - and it shrinks fourfold per doubling of the sample rate. If a
   sample-rate uniform ever reaches this widget, replacing every `f / fc` ratio
   below with tan(PI*f/SR) / tan(PI*fc/SR) makes the curve exact.

   And Dry / Wet is ignored: a parallel blend is a complex sum, so drawing it
   honestly would mean drawing the cascade's phase too, and at anything but
   100% the trace reads as the compressor's own gain rather than the mix's.

   Every parameter that shapes the curve is a `uniform float` below, named
   u_ + the Faust [symbol:] of the control or meter it comes from. For
   standalone testing in the Shadertoy editor (which can't set custom
   uniforms), the defaults under the #ifndef take over and animate.
   =========================================================================== */

#define DBMAX 12.0    /* top of the dB window - a trace past it leaves the frame */
#define DBMIN -24.0   /* bottom - the per-band GR meters floor here too */
#define GLOW 0.60     /* glow strength (0 .. 1) */
#define FILL 0.40     /* shading at the mid trace, ramped to 0 at the 0 dB line */
#define FMIN 20.0     /* frequency axis min, Hz (left edge) */
#define FMAX 20000.0  /* frequency axis max, Hz (right edge), matches the analyser */

#define SIDEA   0.55  /* side trace opacity, relative to the mid trace */
#define DASHON  3.0   /* side trace dash length, px at scale factor 1 */
#define DASHOFF 3.5   /* ... and the gap after it */

/* --- constants mirrored from mbComp5.dsp --------------------------------- */
#define QB12   0.70710678   /* single svf section, 12 dB/oct */
#define QB24   0.54119610   /* 4th-order Butterworth pair, 24 dB/oct */
#define QC24   1.30656296
#define XOMIN  20.0         /* the DSP's clamp(f) floor */
#define XOMAX  20000.0      /* stands in for its 0.45*ma.SR ceiling, see below */
#define XOGAP  1.02         /* minimum ratio between neighbouring crossovers */

/* standalone defaults (Shadertoy editor has no custom uniforms) */
#ifndef LIBREAUDIO_HOSTED
#define SLOPE  (floor(mod(iTime / 5.0, 3.0)))   /* cycle the three slopes */
#define XO1    100.0
#define XO2    500.0
#define XO3    2000.0
#define XO4    8000.0
/* a pumping mid, a side that lags behind it, so the two traces separate */
#define GRM1   (-11.0 * (0.5 + 0.5 * sin(iTime * 1.7)))
#define GRM2   (-8.0  * (0.5 + 0.5 * sin(iTime * 1.7 - 0.4)))
#define GRM3   (-5.0  * (0.5 + 0.5 * sin(iTime * 1.1 - 0.8)))
#define GRM4   (-3.0  * (0.5 + 0.5 * sin(iTime * 0.9 - 1.2)))
#define GRM5   (-6.0  * (0.5 + 0.5 * sin(iTime * 2.3 - 1.6)))
#define GRS1   (-6.0  * (0.5 + 0.5 * sin(iTime * 1.7 - 1.0)))
#define GRS2   (-4.0  * (0.5 + 0.5 * sin(iTime * 1.7 - 1.4)))
#define GRS3   (-3.0  * (0.5 + 0.5 * sin(iTime * 1.1 - 1.8)))
#define GRS4   (-2.0  * (0.5 + 0.5 * sin(iTime * 0.9 - 2.2)))
#define GRS5   (-9.0  * (0.5 + 0.5 * sin(iTime * 2.3 - 2.6)))
#define MK1    0.0
#define MK2    0.0
#define MK3    0.0
#define MK4    0.0
#define MK5    0.0
#define BYP1   0.0
#define BYP2   0.0
#define BYP3   0.0
#define BYP4   0.0
#define BYP5   0.0
#define LSN1   0.0
#define LSN2   0.0
#define LSN3   0.0
#define LSN4   0.0
#define LSN5   0.0
#define FLOORDB (-18.0)
#define GLOWW  2.0    /* glow radius, pixels */
#define THICK  1.5    /* line thickness, pixels */
#define DPX    1.0    /* dash pattern scale */
#else
/* adjustable plugin parameters and meters (u_ + the Faust [symbol:] of each) */
uniform float u_slope;
uniform float u_xover1;
uniform float u_xover2;
uniform float u_xover3;
uniform float u_xover4;
uniform float u_gr_band1_mid;
uniform float u_gr_band2_mid;
uniform float u_gr_band3_mid;
uniform float u_gr_band4_mid;
uniform float u_gr_band5_mid;
uniform float u_gr_band1_side;
uniform float u_gr_band2_side;
uniform float u_gr_band3_side;
uniform float u_gr_band4_side;
uniform float u_gr_band5_side;
uniform float u_band1_makeup;
uniform float u_band2_makeup;
uniform float u_band3_makeup;
uniform float u_band4_makeup;
uniform float u_band5_makeup;
uniform float u_band1_bypass;
uniform float u_band2_bypass;
uniform float u_band3_bypass;
uniform float u_band4_bypass;
uniform float u_band5_bypass;
uniform float u_band1_listen;
uniform float u_band2_listen;
uniform float u_band3_listen;
uniform float u_band4_listen;
uniform float u_band5_listen;
uniform float u_listen_floor;
#define SLOPE  u_slope
#define XO1    u_xover1
#define XO2    u_xover2
#define XO3    u_xover3
#define XO4    u_xover4
#define GRM1   u_gr_band1_mid
#define GRM2   u_gr_band2_mid
#define GRM3   u_gr_band3_mid
#define GRM4   u_gr_band4_mid
#define GRM5   u_gr_band5_mid
#define GRS1   u_gr_band1_side
#define GRS2   u_gr_band2_side
#define GRS3   u_gr_band3_side
#define GRS4   u_gr_band4_side
#define GRS5   u_gr_band5_side
#define MK1    u_band1_makeup
#define MK2    u_band2_makeup
#define MK3    u_band3_makeup
#define MK4    u_band4_makeup
#define MK5    u_band5_makeup
#define BYP1   u_band1_bypass
#define BYP2   u_band2_bypass
#define BYP3   u_band3_bypass
#define BYP4   u_band4_bypass
#define BYP5   u_band5_bypass
#define LSN1   u_band1_listen
#define LSN2   u_band2_listen
#define LSN3   u_band3_listen
#define LSN4   u_band4_listen
#define LSN5   u_band5_listen
#define FLOORDB u_listen_floor
#define GLOWW  (2.0 * _dpf_scale_factor)
#define THICK  (1.5 * _dpf_scale_factor)
#define DPX    _dpf_scale_factor
#endif

float log10_(float x){ return log(x) * 0.43429448190325176; }
float db2lin(float db){ return pow(10.0, db / 20.0); }

/* --- Simper state-variable filter (fi.svf) -------------------------------
   One stage is H(s) = m0 + m1*BP(s) + m2*LP(s) with s = j*f/fg and
   LP = 1/(s^2 + k*s + 1), BP = s/(s^2 + k*s + 1). Putting that over the
   common denominator D = (1 - x^2) + j*k*x leaves

        H = (m0*D + m2 + j*m1*x) / D,   x = f/fg

   so the magnitude is two vec2 lengths -- no complex division needed. The
   mix vector and the fg / k warping below are copied straight out of the
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

/* --- first-order low shelf (ls1 in the DSP) ------------------------------
   fi.lowpass(1,fc) and fi.highpass(1,fc) share a denominator and their
   numerators sum to it, so scaling the low half by G and adding gives
   H = (G + j*w)/(1 + j*w) with w = f/fc: G at DC, unity at SR/2, and the
   exact identity at 0 dB. */
float lowShelf1Db(float f, float fc, float g){
    float G = db2lin(g);
    float w = f / fc;
    return 10.0 * log10_((G * G + w * w) / (1.0 + w * w));
}

/* --- one shelf of the cascade, at the current Slope ----------------------
   The DSP builds every shelf from all three sections at once and weights
   their gains with smoothed indicators of the Slope setting, so a slope
   change morphs instead of jumping. An unselected section sits at 0 dB,
   where svf.ls collapses to the identity, so away from that morph exactly
   one of the three branches below is what the audio sees -- and the shader,
   which has no state to smooth with, simply picks it.

   6 dB/oct is the first-order shelf on its own, 12 dB/oct one svf at
   Q .707, 24 dB/oct the 4th-order Butterworth Q pair sharing the gain. */
float lowShelfDb(float f, float fc, float g){
    float s = floor(SLOPE + 0.5);
    if (s < 0.5) return lowShelf1Db(f, fc, g);
    if (s < 1.5) return svfLsDb(f, fc, QB12, g);
    return svfLsDb(f, fc, QB24, g * 0.5) + svfLsDb(f, fc, QC24, g * 0.5);
}

/* --- crossover frequencies -----------------------------------------------
   The DSP's ascending clamp, verbatim: each corner is held a hair above the
   one below it, so dragging one past another never drags its neighbour's
   control with it. The upper clamp is 0.45*ma.SR there and a fixed 20 kHz
   here, the shader having no sample rate to ask -- at 44.1 kHz that is
   19845 Hz, so a crossover parked at the very top of its range draws under
   1% high, which is a fraction of a pixel on a log axis. */
vec4 xoverFreqs(){
    float f1 = clamp(XO1, XOMIN, XOMAX);
    float f2 = clamp(max(f1 * XOGAP, XO2), XOMIN, XOMAX);
    float f3 = clamp(max(f2 * XOGAP, XO3), XOMIN, XOMAX);
    float f4 = clamp(max(f3 * XOGAP, XO4), XOMIN, XOMAX);
    return vec4(f1, f2, f3, f4);
}

/* --- static part of a band's gain (bandStatic in the DSP) ----------------
   Bypass needs no term of its own on the reduction: the meters read what is
   applied, after the bypass scale, so a bypassed band already reports 0. */
float bandOffset(float makeup, float byp, float listen){
    float anyListen = LSN1 + LSN2 + LSN3 + LSN4 + LSN5;
    float audible = anyListen > 0.0 ? listen : 1.0;
    float scale   = audible * (1.0 - byp);   // `active` in the DSP, a GLSL ES reserved word here
    return audible > 0.5 ? makeup * scale : FLOORDB;
}

/* one band's dB gain; ch = 0 mid, 1 side */
float bandGain(float grM, float grS, float ch, float makeup, float byp, float listen){
    return mix(grM, grS, ch) + bandOffset(makeup, byp, listen);
}

/* --- the shelf cascade ---------------------------------------------------
   Each shelf carries the difference between the bands on either side of its
   crossover, and the top band's gain is a broadband multiply. Shelf gains
   add in dB, so the sum telescopes: below f1 it is (g0-g1)+(g1-g2)+...+g4 =
   g0, between f1 and f2 it is g1, and so on. Which is why the plateaus land
   on the band gains without anything here having to say so. */
float cascadeDb(float f, float g0, float g1, float g2, float g3, float g4){
    vec4 x = xoverFreqs();
    return lowShelfDb(f, x.x, g0 - g1)
         + lowShelfDb(f, x.y, g1 - g2)
         + lowShelfDb(f, x.z, g2 - g3)
         + lowShelfDb(f, x.w, g3 - g4)
         + g4;
}

/* applied response of one channel, dB. ch = 0 mid, 1 side */
float responseDb(float f, float ch){
    return cascadeDb(f,
        bandGain(GRM1, GRS1, ch, MK1, BYP1, LSN1),
        bandGain(GRM2, GRS2, ch, MK2, BYP2, LSN2),
        bandGain(GRM3, GRS3, ch, MK3, BYP3, LSN3),
        bandGain(GRM4, GRS4, ch, MK4, BYP4, LSN4),
        bandGain(GRM5, GRS5, ch, MK5, BYP5, LSN5));
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

/* Curve height in height fractions, 0 = top, 1 = bottom -- deliberately NOT
   clamped to that range. A response past DBMAX or DBMIN puts the trace off
   the widget, the distance test below then matches nothing, and the line
   simply runs off the top or bottom edge and is gone, the way a plot line
   leaves a frame. Clamping instead would pin it flat along the edge, and a
   flat line already means something else on a compressor's curve -- a band
   doing nothing -- and the two must not be confusable. The stroke still dives off at the true angle, because the
   slope below is taken from these same unclamped values. */
float curveY(float t, float ch){
    /* x -> frequency, log axis */
    float freq = FMIN * pow(FMAX / FMIN, t);
    return (DBMAX - responseDb(freq, ch)) / (DBMAX - DBMIN);
}

/* Dash pattern for the side trace, measured along x rather than along the
   trace. Where the curve runs steep the dashes bunch up, which is the cheap
   half of the trade and reads as the line simply getting denser through the
   crossover. Both ends of every dash are antialiased by measuring distance
   from its centre, so the pattern never crawls. */
float dashCov(float px){
    float on = DASHON * DPX;
    float period = on + DASHOFF * DPX;
    float u = mod(px, period);
    float d = abs(u - on * 0.5);
    return 1.0 - smoothstep(on * 0.5 - 0.5, on * 0.5 + 0.5, d);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    vec2 uv = fragCoord / iResolution.xy;
    float t  = uv.x;               // 0..1 left->right (frequency axis)
    float py = 1.0 - uv.y;         // 0 at top, 1 at bottom (matches the plugin)

    float yM = curveY(t, 0.0);
    float yS = curveY(t, 1.0);

    /* Curve slope in pixels-of-y per pixel-of-x, by central difference one
       pixel either side. A 24 dB/oct step of 20 dB crosses the whole window
       inside a few pixels: without this a vertical-only distance test pinches
       the stroke to a hairline and the line reads as broken. Central (not
       forward) difference so the stroke stays centred on the trace rather
       than leaning half a pixel downhill. */
    float dtx = 1.0 / iResolution.x;
    float sM = (curveY(t + dtx, 0.0) - curveY(t - dtx, 0.0)) * 0.5 * iResolution.y;
    float sS = (curveY(t + dtx, 1.0) - curveY(t - dtx, 1.0)) * 0.5 * iResolution.y;

    /* perpendicular distance to each trace, in pixels */
    float dM = abs(py - yM) * iResolution.y * inversesqrt(1.0 + sM * sM);
    float dS = abs(py - yS) * iResolution.y * inversesqrt(1.0 + sS * sS);

    /* antialiased line coverage (constant width whatever the slope). The side
       trace is a touch thinner as well as dashed and fainter - three ways of
       saying "this is the second one" is not one too many at 1.5 px. */
    float hw = THICK * 0.5;
    float covM = 1.0 - smoothstep(hw, hw + 1.5, dM);
    float covS = (1.0 - smoothstep(hw * 0.8, hw * 0.8 + 1.5, dS))
               * dashCov(fragCoord.x) * SIDEA;

    /* soft glow bloom around the traces (a wide gaussian falloff). The side
       contributes half, so the pair glows as one object rather than twice. */
    float gw = max(GLOWW, 0.001);
    float glow = max(exp(-(dM * dM) / (gw * gw)),
                     exp(-(dS * dS) / (gw * gw)) * 0.5) * GLOW;

    vec3 col = rainbow(t);

    /* Shade between the mid trace and the 0 dB line, so how far each band is
       pulled down reads without measuring against the scale. Kept faint so
       the spectrum behind it still shows through, and ramped to nothing at
       0 dB: the shading hangs off the trace rather than sitting in a slab
       with a hard edge along the rest line, and a band doing nothing fades
       out instead of drawing a seam where its gain crosses zero.

       The ramp is measured from the 0 dB line towards the trace, so it works
       the same way up (Makeup) and down (reduction) without a branch. The
       denominator keeps its sign and never reaches zero, so a trace sitting
       exactly on 0 dB gives 0/1e-5 rather than 0/0.

       This half does use the clamped height: once the trace has left the
       widget the shading is all that is left to say the band is still going
       down, and anchoring the ramp to the edge keeps it at full strength
       there instead of dividing it away against an off-screen number. */
    float zero = DBMAX / (DBMAX - DBMIN);
    float aa = 1.5 / iResolution.y;
    float yF = clamp(yM, 0.0, 1.0);
    float lo = min(yF, zero);
    float hi = max(yF, zero);
    float span = yF - zero;
    float denom = (span >= 0.0 ? 1.0 : -1.0) * max(abs(span), 1e-5);
    float ramp = clamp((py - zero) / denom, 0.0, 1.0);
    float fill = smoothstep(-aa, aa, py - lo) * (1.0 - smoothstep(-aa, aa, py - hi)) * ramp * FILL;

    /* composite: fill, then glow, then the side trace, then the mid on top */
    float a = fill;
    a = glow + a * (1.0 - glow);
    a = covS + a * (1.0 - covS);
    a = covM + a * (1.0 - covM);
    /* Straight (non-premultiplied) alpha: DPF draws with
       glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA), so premultiplying here
       would darken the colour a second time -- the glow and the antialiased
       edges would fringe towards black instead of fading to transparent. */
    fragColor = vec4(col, a);
}
