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
   LAS Delay - tap-train SCOPE, Shadertoy port of the Delay_v1 prototype
   ---------------------------------------------------------------------------
   Time runs top to bottom: the top edge is the dry hit, the bottom edge is a
   little past the last audible repeat. The left half is the left line, the
   right half the right line, both growing outward from the centre.

   Each repeat is a bar at its own delay time. Length and opacity follow its
   level, so the train visibly decays with Feedback; Dry-Wet shrinks the wet
   bars and the dry row against each other, and Width pushes the two sides
   apart. Cross-feedback repeats -- the ones a line hands to the other side --
   are drawn as outlines on the side they land on, so they read as borrowed.
   In Ping-Pong there is one train at the average of the two times, bouncing
   side to side, starting on the side the mode names.

   Every LOOP seconds a sweep runs down the display: each bar flashes in the
   scope palette as it passes, and a faint waveform of the tap train scrolls
   down at the same speed, so its peaks travel with the flash.

   The waveform is dummy data for now -- a deterministic function of the taps
   -- and waveWidth() is the only place it is read. Swap that for the real
   wet signal when the host can provide it.

   Text (grid times, L / R) cannot be drawn here; DelayP2 in delay-ui.cpp
   draws it over this shader from the same model. If the times, the zoom
   levels or the grid change below, change DelayScopeModel to match.

   Curve only: the background stays black and fully transparent (alpha 0), so
   it drops onto the starfield like the other curve shaders.
   =========================================================================== */

#define LOOP   13.0    /* seconds per sweep down the display */
#define TMAX   4000.0  /* longest delay time, ms - maxDelayMs in delay.dsp */
/* The zoom level fits the repeats down to AMPMIN, at most NTAPS of them. That
   only sets the scale: every repeat that fits on the display is drawn, however
   quiet, so a train never stops short of the bottom edge. */
#define AMPMIN 0.006   /* quietest repeat the zoom level makes room for */
#define NTAPS  32.0    /* most repeats the zoom level makes room for */
#define NALL   1.0e4   /* "all of them" for the waveform's train sums */
#define NB     3.0     /* neighbouring repeats each pixel checks either side */
#define WAVEN  260.0   /* points down one waveform period */

/* The prototype is laid out in CSS px at a smaller scale than the plugin:
   its 8 px well labels are the plugin's 12 px ones. Every length below is in
   prototype px and multiplied by PX. Matches kScopeRefPx in delay-ui.cpp. */
#define REFPX  1.5

/* scope inset inside the well, prototype px: top, sides, bottom */
#define INSET_T 20.0
#define INSET_X 14.0
#define INSET_B 16.0

/* grid label, for leaving a gap in its dashed line: 8 px mono with 0.1 em
   letter spacing, 4 px padding after it */
#define LABEL_FONT 8.0
#define LABEL_ADV  0.7
#define LABEL_PAD  4.0

/* standalone defaults (Shadertoy editor has no custom uniforms) */
#ifndef LIBREAUDIO_HOSTED
#define SCALE    1.0
#define SYNC     0.0   /* 0 Free, 1 Tempo */
#define LINK     0.0   /* 0 Free, 1 Linked - as in delay.dsp */
#define TIMEL    375.0
#define TIMER    500.0
#define BPM      120.0
#define DIVL     6.0
#define DIVR     5.0
#define OFFL     0.0
#define OFFR     5.9
#define FEEDBACK 45.0
#define CROSS    0.0
#define PINGPONG 0.0   /* 0 Normal, 1 Ping (L first), 2 Pong (R first) */
#define DRYWET   -14.0
#define WIDTH    100.0
#define BYPASS   0.0
#else
uniform float u_bpm;
uniform float u_cross;
uniform float u_div_l;
uniform float u_div_r;
uniform float u_dpf_bypass;
uniform float u_drywet;
uniform float u_feedback;
uniform float u_link;
uniform float u_offset_l;
uniform float u_offset_r;
uniform float u_pingpong;
uniform float u_sync;
uniform float u_time_l;
uniform float u_time_r;
uniform float u_width;
/* The span actually shown, ms, handed over by the host while it animates a
   flip between zoom levels (DelayScopeZoom in delay-ui.cpp). A fragment
   program keeps nothing between frames, so it cannot tween on its own. */
uniform float iSpan;
#define SCALE    _dpf_scale_factor
#define SYNC     u_sync
#define LINK     u_link
#define TIMEL    u_time_l
#define TIMER    u_time_r
#define BPM      u_bpm
#define DIVL     u_div_l
#define DIVR     u_div_r
#define OFFL     u_offset_l
#define OFFR     u_offset_r
#define FEEDBACK u_feedback
#define CROSS    u_cross
#define PINGPONG u_pingpong
#define DRYWET   u_drywet
#define WIDTH    u_width
#define BYPASS   u_dpf_bypass
#endif

#define PX (REFPX * SCALE)

const vec3 ACC = vec3(0.765, 0.851, 1.000); /* #c3d9ff */

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

/* ---------------------------------------------------------------------------
   The tap model, evaluated once per pixel into these globals by setupModel().
   --------------------------------------------------------------------------- */

float gMsL, gMsR;  /* effective delay times, ms */
float gG;          /* feedback, 0 .. 0.985 */
float gC;          /* cross-feedback, 0 .. 1 */
float gPP;         /* 0 Normal, 1 Ping, 2 Pong */
float gK;          /* repeats per train above AMPMIN - for the zoom level only */
float gSpan;       /* ms shown top to bottom */
float gTau;        /* waveform decay constant, ms */
float gWet;        /* wet bar scale from Dry-Wet */
float gSp;         /* Width, 0 .. 2 */

/* divTable in delay.dsp, relative to a quarter note */
float divMult(float i){
    if (i < 0.5) return 4.0;
    if (i < 1.5) return 2.0;
    if (i < 2.5) return 1.5;
    if (i < 3.5) return 1.0;
    if (i < 4.5) return 2.0 / 3.0;
    if (i < 5.5) return 0.75;
    if (i < 6.5) return 0.5;
    if (i < 7.5) return 1.0 / 3.0;
    if (i < 8.5) return 0.375;
    if (i < 9.5) return 0.25;
    return 1.0 / 6.0;
}

/* The prototype's grid: the first step that fits the span in seven lines,
   extended to 16 s and 32 s for the longest zoom levels. */
float gridStep(float span){
    if (span / 50.0   <= 7.0) return 50.0;
    if (span / 100.0  <= 7.0) return 100.0;
    if (span / 125.0  <= 7.0) return 125.0;
    if (span / 250.0  <= 7.0) return 250.0;
    if (span / 500.0  <= 7.0) return 500.0;
    if (span / 1000.0 <= 7.0) return 1000.0;
    if (span / 2000.0 <= 7.0) return 2000.0;
    if (span / 4000.0 <= 7.0) return 4000.0;
    if (span / 8000.0 <= 7.0) return 8000.0;
    if (span / 16000.0 <= 7.0) return 16000.0;
    return 32000.0;
}

void setupModel(){
    /* The times as delay.dsp resolves them: Sync picks the source, Link hands
       the right line the left line's raw time, and the offsets trim each side
       after that, then one clamp. */
    float beat = 60000.0 / max(BPM, 1.0);
    float rawL = SYNC > 0.5 ? divMult(DIVL) * beat : TIMEL;
    float rawR = LINK > 0.5 ? rawL : (SYNC > 0.5 ? divMult(DIVR) * beat : TIMER);
    gMsL = clamp(rawL * (1.0 + OFFL / 100.0), 1.0, TMAX);
    gMsR = clamp(rawR * (1.0 + OFFR / 100.0), 1.0, TMAX);

    gG  = clamp(FEEDBACK / 100.0, 0.0, 0.985);
    gC  = clamp(CROSS / 100.0, 0.0, 1.0);
    gPP = floor(PINGPONG + 0.5);

    /* how many k >= 1 have g^k >= AMPMIN */
    gK = gG > AMPMIN ? min(NTAPS, floor(log(AMPMIN) / log(gG))) : 0.0;

    float last = gPP < 0.5 ? max(gMsL, gMsR) : 0.5 * (gMsL + gMsR);
    last = gK > 0.0 ? gK * last : max(gMsL, gMsR);

    /* Fixed zoom levels rather than a continuous fit: the smallest of 0.6 s,
       1.2 s, 2.4 s ... 153.6 s that holds the last repeat with 6% to spare, so
       the display flips between scales instead of drifting as a knob moves.
       153.6 s covers the longest train, NTAPS repeats of TMAX. Matches
       DelayScopeModel. */
    gSpan = 600.0;
    for (float i = 0.0; i < 8.0; i += 1.0)
        if (gSpan < last * 1.06) gSpan *= 2.0;
#ifdef LIBREAUDIO_HOSTED
    /* the host's animated span, once it has sent one */
    if (iSpan > 0.0) gSpan = iSpan;
#endif
    gTau  = gSpan / 26.0;
    gWet  = clamp(DRYWET >= 0.0 ? 1.0 : (100.0 + DRYWET) / 100.0, 0.0, 1.0);
    gSp   = clamp(WIDTH / 100.0, 0.0, 2.0);
}

/* 0 .. 1: how lit the bar at normalised height yn is. The sweep reaches it
   once per LOOP, holds for 3% of the loop and fades back over the next 13%. */
float flashAt(float yn){
    float ph = fract(iTime / LOOP - yn);
    return ph < 0.03 ? 1.0 : clamp(1.0 - (ph - 0.03) / 0.13, 0.0, 1.0);
}

/* How much of the pixel centred on a lies within [lo, hi], along one axis. */
float cover(float a, float lo, float hi){
    return clamp(min(a + 0.5, hi) - max(a - 0.5, lo), 0.0, 1.0);
}

/* Straight-alpha colour `c` with coverage `a`, composited over premultiplied `o`. */
vec4 over(vec4 o, vec3 c, float a){
    return vec4(c * a, a) + o * (1.0 - a);
}

/* ---------------------------------------------------------------------------
   Waveform (dummy data)
   --------------------------------------------------------------------------- */

/* Sum over one geometric train of decaying hits: hit j lands at t0 + j*d with
   level a0*r^j, j = 0 .. n-1, each decaying with gTau. Closed form rather than
   a loop, since every pixel evaluates it several times and a short delay puts
   hundreds of hits on screen. The terms form a geometric series; it is summed
   from whichever end makes the ratio at most 1, so a long train cannot
   overflow -- from the latest hit backwards when the older hits are the
   quieter ones, from the first hit forwards otherwise. */
float trainEnv(float t, float t0, float d, float a0, float r, float n){
    if (n < 0.5 || t < t0 || a0 <= 0.0 || r <= 0.0) return 0.0;
    float m   = min(n, floor((t - t0) / d) + 1.0);
    float l   = m - 1.0;
    float rho = r * exp(d / gTau);       // ratio from one hit's term to the next
    float first, ratio;
    if (rho <= 1.0) {
        first = a0 * exp(-(t - t0) / gTau);
        ratio = rho;
    } else {
        first = a0 * pow(r, l) * exp(-(t - t0 - l * d) / gTau);
        ratio = 1.0 / rho;
    }
    if (1.0 - ratio < 1e-4) return first * m;
    return first * (1.0 - pow(ratio, m)) / (1.0 - ratio);
}

/* Envelope of one side's tap train at time t: the dry hit plus every repeat
   that has landed on this side by then. */
float env(float ch, float t){
    float s = exp(-t / (gTau * 0.8));

    if (gPP < 0.5) {
        float ms = ch < 0.0 ? gMsL : gMsR;
        float mo = ch < 0.0 ? gMsR : gMsL;
        s += trainEnv(t, ms,       ms, 1.0,                     1.0, 1.0);
        s += trainEnv(t, 2.0 * ms, ms, gG * (1.0 - gC * 0.5), gG,  NALL);
        if (gC > 0.001)
            s += trainEnv(t, mo, mo, gG * gC * 0.5, gG, NALL);
    } else {
        float avg = 0.5 * (gMsL + gMsR);
        /* Ping lands odd repeats on the left, Pong on the right */
        bool odd = (gPP < 1.5) == (ch < 0.0);
        if (odd) {
            s += trainEnv(t, avg,       2.0 * avg, 1.0,     1.0,     1.0);
            s += trainEnv(t, 3.0 * avg, 2.0 * avg, gG * gG, gG * gG, NALL);
        } else {
            s += trainEnv(t, 2.0 * avg, 2.0 * avg, gG,      gG * gG, NALL);
        }
    }
    return s;
}

float wob(float i, float k){
    return sin(i * k) * 0.5 + sin(i * k * 2.7 + 1.3) * 0.3 + sin(i * k * 6.1 + 0.7) * 0.2;
}

/* Half-width of the waveform at point i (0 .. WAVEN, top to bottom of one
   period), as a fraction of the scope width. DUMMY DATA: the envelope of the
   tap train, roughened by a fixed wobble per point. This is the seam for the
   real signal. */
float waveWidth(float ch, float i){
    i = clamp(i, 0.0, WAVEN);
    float e = clamp(env(ch, i / WAVEN * gSpan), 0.0, 1.6) / 1.6;
    return pow(e, 0.6) * abs(wob(i, ch < 0.0 ? 0.41 : 0.53)) * 0.46;
}

float segDist(vec2 p, vec2 a, vec2 b){
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

/* One side of the waveform, filled from the centre out and stroked along its
   edge. p is in scope pixels, y down; the waveform scrolls down one scope
   height per LOOP, two periods stacked so it never runs out. */
vec4 drawWave(vec4 o, vec2 p, vec2 size, float ch){
    float cx = size.x * 0.5;
    float w  = fract(p.y / size.y - iTime / LOOP);
    float fi = w * WAVEN;
    float j  = floor(fi);
    vec2  q  = vec2(p.x, w * size.y);

    float w0 = waveWidth(ch, j - 1.0);
    float w1 = waveWidth(ch, j);
    float w2 = waveWidth(ch, j + 1.0);
    float w3 = waveWidth(ch, j + 2.0);

    float dy = size.y / WAVEN;
    vec2 P0 = vec2(cx + ch * w0 * size.x, (j - 1.0) * dy);
    vec2 P1 = vec2(cx + ch * w1 * size.x, j * dy);
    vec2 P2 = vec2(cx + ch * w2 * size.x, (j + 1.0) * dy);
    vec2 P3 = vec2(cx + ch * w3 * size.x, (j + 2.0) * dy);

    /* fill: between the centre and the edge on this side */
    float dx   = (p.x - cx) * ch;
    float edge = mix(w1, w2, fract(fi)) * size.x;
    float fill = clamp(edge - dx + 0.5, 0.0, 1.0) * step(0.0, dx);
    o = over(o, ACC, 0.13 * fill);

    /* stroke: a hairline, 0.3 prototype px, along the edge and the centre */
    float d = min(min(segDist(q, P0, P1), segDist(q, P1, P2)), segDist(q, P2, P3));
    d = min(d, abs(p.x - cx));
    float stroke = clamp(1.0 - d, 0.0, 1.0) * min(0.3 * PX, 1.0);
    return over(o, ACC, 0.20 * stroke);
}

/* ---------------------------------------------------------------------------
   Grid
   --------------------------------------------------------------------------- */

float digits(float n){
    return n >= 1000.0 ? 4.0 : n >= 100.0 ? 3.0 : n >= 10.0 ? 2.0 : 1.0;
}

/* Characters in the grid label for ms, as DelayScopeModel formats it:
   "250 ms", "1 s", "1.5 s", "1.25 s". */
float labelChars(float ms){
    if (ms < 1000.0)
        return digits(floor(ms + 0.5)) + 3.0;
    float frac = mod(ms, 1000.0) < 0.5 ? 0.0 : (mod(ms, 100.0) < 0.5 ? 2.0 : 3.0);
    return digits(floor(ms / 1000.0)) + frac + 2.0;
}

vec4 drawGrid(vec4 o, vec2 p, vec2 size){
    float step_ = gridStep(gSpan);
    float t = p.y / size.y * gSpan;
    float k = floor(t / step_ + 0.5);
    float s = k * step_;
    if (k < 1.0 || s >= gSpan) return o;

    /* a 1 px dashed top border, starting after the label that sits on it */
    float y   = s / gSpan * size.y;
    float cov = cover(p.y, y, y + PX);
    float x0  = (labelChars(s) * LABEL_FONT * LABEL_ADV + LABEL_PAD) * PX;
    float dash = step(mod(p.x - x0, 6.0 * PX), 3.0 * PX) * step(x0, p.x);
    return over(o, vec3(1.0), 0.05 * cov * dash);
}

/* ---------------------------------------------------------------------------
   Bars
   --------------------------------------------------------------------------- */

float sdBox(vec2 p, vec2 c, vec2 hs, float r){
    vec2 q = abs(p - c) - hs + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

/* Length of a repeat's bar in scope pixels, following its level all the way
   down with no floor at all: a quiet enough repeat shrinks to nothing. Own and
   cross-feed repeats alike. */
float barLen(float amp, float ch, float halfW){
    float pct = 100.0 * sqrt(amp);
    pct *= gWet * (ch < 0.0 ? 1.0 - (gSp - 1.0) * 0.06 : 1.0 + (gSp - 1.0) * 0.06);
    return clamp(pct, 0.0, 96.0) / 100.0 * halfW;
}

/* One repeat's bar: t is its delay time in ms, growing outward from the centre
   on side ch. Solid for the line's own repeats, an outline for cross-feed. */
vec4 drawBar(vec4 o, vec2 p, vec2 size, float ch, float t, float amp, bool cross){
    float yn  = t / gSpan;
    float cx  = size.x * 0.5;
    float len = barLen(amp, ch, cx);
    if (len < 0.01) return o;

    /* Height and opacity keep a low floor, 1 px and 8%, so a short bar is still
       a bar -- the length is what takes a repeat away. */
    float hgt = (1.0 + 3.0 * pow(amp, 0.45)) * PX;
    float op  = cross ? (0.92 * pow(amp, 0.38) + 0.08 * min(1.0, gC * 4.0)) * min(1.0, gC * 6.0)
                      : 0.08 + 0.92 * pow(amp, 0.38);

    /* Under a pixel long, coverage alone would leave a half-lit sliver however
       short it got; fading it by its length lets it dissolve instead. The glow
       goes with it over the first couple of pixels. */
    float fade = clamp(len, 0.0, 1.0);
    float glowFade = clamp(len / (2.0 * PX), 0.0, 1.0);

    vec2  c = vec2(cx + ch * len * 0.5, yn * size.y);
    float r = min(2.0 * PX, min(hgt, len) * 0.5);
    float d = sdBox(p, c, vec2(len, hgt) * 0.5, r);

    /* nothing of it, not even the glow, reaches this pixel */
    if (d > 10.0 * PX) return o;

    float f   = flashAt(yn);
    vec3  hue = rainbow(yn);
    vec3  col = clamp(mix(ACC, hue, f) * (1.0 + (cross ? 0.6 : 0.55) * f), 0.0, 1.0);

    /* the glow: an outer shadow in the flash colour, 8 px (7 for cross) blur */
    float sigma = (cross ? 3.5 : 4.0) * PX;
    float glow  = (cross ? 0.45 : 0.6) * 0.5 * f * exp(-d * d / (2.0 * sigma * sigma)) * step(0.0, d);
    o = over(o, hue, glow * op * glowFade);

    float body = clamp(0.5 - d, 0.0, 1.0);
    if (cross)
        body -= clamp(0.5 - (d + PX), 0.0, 1.0); // inset 1 px outline
    return over(o, col, body * op * fade);
}

/* Level of a line's own repeat k: the first echo is the wet signal itself, at
   full level whatever the feedback, and each pass round the loop takes one
   more factor of it. Outside Ping-Pong a repeat after the first also loses
   what Cross hands to the other side. Ping-Pong has no Cross. */
float ownLevel(float k){
    if (k < 1.5) return 1.0;
    return pow(gG, k - 1.0) * (gPP < 0.5 ? 1.0 - gC * 0.5 : 1.0);
}

/* All repeats of one side near this pixel. Each train is checked at the NB
   repeats either side of the nearest, which is the most whose bars or glow can
   reach one pixel row. No limit at the bottom of the time scale: like the
   waveform, the bars carry on through the bottom inset to the edge of the
   well, and nothing past that is ever a pixel. */
vec4 drawTaps(vec4 o, vec2 p, vec2 size, float ch){
    float t = p.y / size.y * gSpan;

    if (gPP < 0.5) {
        float ms = ch < 0.0 ? gMsL : gMsR;
        float mo = ch < 0.0 ? gMsR : gMsL;

        float k0 = floor(t / ms + 0.5);
        for (float dk = -NB; dk <= NB; dk += 1.0) {
            float k = k0 + dk;
            if (k >= 1.0 && (k < 1.5 || gG > 0.0))
                o = drawBar(o, p, size, ch, k * ms, ownLevel(k), false);
        }

        if (gC > 0.001) {
            k0 = floor(t / mo + 0.5);
            for (float dk = -NB; dk <= NB; dk += 1.0) {
                float k = k0 + dk;
                if (k >= 1.0 && gG > 0.0)
                    o = drawBar(o, p, size, ch, k * mo, pow(gG, k) * gC * 0.5, true);
            }
        }
    } else {
        float avg = 0.5 * (gMsL + gMsR);
        /* Ping lands odd repeats on the left, Pong on the right */
        float parity = (gPP < 1.5) == (ch < 0.0) ? 1.0 : 0.0;
        float k0 = floor(t / avg + 0.5);
        for (float dk = -NB; dk <= NB; dk += 1.0) {
            float k = k0 + dk;
            if (k >= 1.0 && (k < 1.5 || gG > 0.0) && mod(k, 2.0) == parity)
                o = drawBar(o, p, size, ch, k * avg, ownLevel(k), false);
        }
    }
    return o;
}

/* The dry hit, at the very top: two solid bars either side of a 2 px gap,
   shorter the further Dry-Wet moves toward Wet. */
vec4 drawDry(vec4 o, vec2 p, vec2 size){
    float cx  = size.x * 0.5;
    float wd  = clamp(DRYWET <= 0.0 ? 1.0 : 1.0 - DRYWET / 100.0, 0.06, 1.0) * 0.48 * size.x;
    float hgt = 4.0 * PX;
    float gap = 1.0 * PX;
    float ch  = p.x < cx ? -1.0 : 1.0;

    vec2  c = vec2(cx + ch * (gap + wd * 0.5), 0.0);
    float d = sdBox(p, c, vec2(wd, hgt) * 0.5, min(2.0 * PX, hgt * 0.5));
    if (d > 10.0 * PX) return o;

    float f   = flashAt(0.0);
    vec3  hue = rainbow(0.0);

    float glow = 0.6 * 0.5 * f * exp(-d * d / (2.0 * 16.0 * PX * PX)) * step(0.0, d);
    o = over(o, hue, glow);

    vec3  col  = clamp(mix(ACC, hue, f) * (1.0 + 0.55 * f), 0.0, 1.0);
    float body = clamp(0.5 - d, 0.0, 1.0);
    return over(o, col, body);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord){
    setupModel();

    /* scope pixels: origin at the scope's top-left, y down */
    vec2 lo   = vec2(INSET_X, INSET_B) * PX;
    vec2 size = iResolution.xy - vec2(2.0 * INSET_X, INSET_T + INSET_B) * PX;
    vec2 p    = vec2(fragCoord.x - lo.x, iResolution.y - fragCoord.y - INSET_T * PX);
    bool inside = p.x >= 0.0 && p.y >= 0.0 && p.x < size.x && p.y < size.y;
    float cx = size.x * 0.5;

    vec4 o = vec4(0.0);

    /* The waveform runs on past the scope's bottom inset to the bottom edge of
       the well. Its scroll is periodic in the scope height, so below the scope
       it simply carries on into the next period. */
    if (p.x >= 0.0 && p.y >= 0.0 && p.x < size.x) {
        o = drawWave(o, p, size, -1.0);
        o = drawWave(o, p, size,  1.0);
    }

    if (inside) {
        o = drawGrid(o, p, size);

        /* centre line */
        o = over(o, vec3(1.0), 0.07 * cover(p.x, cx, cx + PX));

        /* the "now" line along the top, brightest in the middle */
        float now = 0.34 * (1.0 - abs(p.x / size.x * 2.0 - 1.0)) * cover(p.y, 0.0, PX);
        o = over(o, ACC, now);
    }

    /* bars and their glow may spill a little past the scope */
    o = drawDry(o, p, size);
    o = drawTaps(o, p, size, -1.0);
    o = drawTaps(o, p, size,  1.0);

    /* dimmed while bypassed */
    float a = o.a * (BYPASS > 0.5 ? 0.35 : 1.0);

    /* Straight (non-premultiplied) alpha: DPF draws with
       glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA). */
    fragColor = vec4(o.a > 0.0 ? o.rgb / o.a : vec3(0.0), a);
}
