/* Libre Audio Suite — https://libreaudio.org
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
   FFT spectrum analyser - overlay layer
   ---------------------------------------------------------------------------
   Sits between the background shader and the curve shaders: the spectrum is
   filled from the bottom of the widget up to the trace and is fully
   transparent above it, so whatever is behind shows through untouched and the
   response curves still draw on top.

   The fill runs through the Libre Audio rainbow horizontally -- the same
   7-stop palette the curve shaders use -- and darkens vertically towards the
   bottom of the widget. All of it is tunable below, including a paletteAmount
   that fades the colour back to plain grey.

   The bin magnitudes are made up here for now -- see fftBinDb() for the one
   function that has to change once the host sends a real spectrum.
   =========================================================================== */

// --------------------------------------------------------------------------------
// Axes
// --------------------------------------------------------------------------------

const float fMin = 20.0;      // left edge, Hz
const float fMax = 20000.0;   // right edge, Hz (log axis between the two)
const float dbTop   =   6.0;  // top of the widget, dBFS
const float dbFloor = -55.0;  // bottom of the widget, dBFS

const int fftBins = 64;       // number of analyser bins across the width

// --------------------------------------------------------------------------------
// Look
// --------------------------------------------------------------------------------

// Fill colour. Horizontally it runs through the 7-stop Libre Audio palette,
// the same sweep the curve shaders use, so the analyser and the response curve
// agree on what colour a frequency is. paletteAmount fades that back towards
// fillGrey -- 0.0 gives the plain grey fill.
const float paletteAmount = 1.0;
const vec3  fillGrey      = vec3(0.72);

// Vertical shading. Full brightness at fillGradientTop (0 .. 1 of the widget
// height) and above, darkening from there down to the bottom edge. Measured
// against the widget, not the bin, so neighbouring bins shade the same at the
// same height and the gradient does not restart per bar.
const float fillBrightnessTop    = 1.00;
const float fillBrightnessBottom = 0.10;
const float fillGradientTop      = 0.80;

// Fill opacity over the same span. Flat by default, so the vertical gradient
// reads as the fill going dark rather than as it fading out -- pull
// fillAlphaTop down instead if you want it to fade.
const float fillAlphaBottom = 0.75;
const float fillAlphaTop    = 0.75;

// How far below its top edge the fill starts fading out, as a fraction of the
// widget height. Softens the top end so the spectrum dissolves into whatever is
// behind it instead of ending on a hard line. 0.0 gives a crisp edge.
const float topSoftness = 0.06;

// Overall opacity of the whole layer.
const float analyserOpacity = 1.0;

// Bars or a continuous trace. barGap is the gap between bars as a fraction of
// the bin width -- 0.0 gives a smooth filled curve instead of discrete bars.
const float barGap = 0.0;

// --------------------------------------------------------------------------------
// Shape of the made-up spectrum (ignored once real bin data arrives)
// --------------------------------------------------------------------------------

const float spectrumHeadroomDb  =  -6.0;  // bin peak relative to the input meter
const float spectrumKneeHz      = 120.0;  // flat below the knee, tilted above it
const float spectrumTiltDbPerOct = 3.4;   // programme material falls off with frequency
const float subRolloffDbPerOct  =  9.0;   // below the knee
const float airHz               = 9000.0; // extra roll-off starts here
const float airRolloffDbPerOct  =  5.0;

const float binFlutterDb   = 8.0;   // how far a bin swings around its shape, +/- dB
const float binDriftRate   = 1.7;   // slow component, new target per second
const float binFlickerRate = 9.0;   // fast component

// --------------------------------------------------------------------------------
// Host-supplied values
//
// Everything the plugin provides and the Shadertoy editor does not, stubbed out
// on the standalone side so the file pastes straight into a new shader.
// --------------------------------------------------------------------------------

#ifndef LIBREAUDIO_HOSTED
// Sets the level the made-up spectrum sits at. In the plugin this follows the
// input meters, so the analyser already moves with the audio before real FFT
// data exists; standalone it is a flat, sensible programme level.
float inputLevelDb() { return -14.0; }
#else
// Peak of the two input meters in dBFS, smoothed by the host over two different
// time constants: iLevelSlow settles in about 5 s, iLevelFast in about 0.5 s.
// The smoothing cannot live here -- a fragment shader keeps no state between
// frames -- so these arrive already integrated. See LibreAudioBackgroundShaderWidget.
uniform float iLevelSlow;
uniform float iLevelFast;

// The slow envelope sets the level the picture sits at, the fast one supplies
// the movement around it.
const float shortTermAmount = 0.65;

float inputLevelDb() { return mix(iLevelSlow, iLevelFast, shortTermAmount); }
#endif

// --------------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------------

float log2_(float x) { return log(x) * 1.44269504088896341; }

/* The 7-stop Libre Audio scope palette, evenly spaced and lerped in sRGB --
   the same sweep curve-chorus.frag uses for its trace and inter-trace fill. */
vec3 rainbow(float x)
{
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

float hash11(float n) { return fract(sin(n * 43.7585453) * 43758.5453123); }

/* One bin's random level, 0 .. 1, taking a new target `rate` times per second
   and smoothstepping between them -- so bins rise and fall instead of strobing. */
float binNoise(float bin, float rate, float seed)
{
    float t = iTime * rate;
    float i = floor(t);
    float f = fract(t);
    f = f * f * (3.0 - 2.0 * f);
    return mix(hash11(bin * 1.7413 + i * 5.3271 + seed),
               hash11(bin * 1.7413 + (i + 1.0) * 5.3271 + seed), f);
}

/* Gaussian bell in log-frequency: `gain` dB at `fc`, `bwOct` octaves wide. */
float bellDb(float f, float fc, float bwOct, float gain)
{
    float x = log2_(f / fc) / bwOct;
    return gain * exp(-x * x);
}

// --------------------------------------------------------------------------------
// Bin magnitudes
//
// This is the seam for the host data. Once the plugin sends a spectrum, replace
// the body with a lookup and everything below keeps working unchanged. A single
// texture row is the usual route -- one texel per bin, uploaded per frame:
//
//     float fftBinDb(float bin) {
//         float mag = texture2D(iChannel0, vec2((bin + 0.5) / float(fftBins), 0.5)).r;
//         return mix(dbFloor, dbTop, mag);
//     }
//
// Until then the bins are invented from the input meter plus noise.
// --------------------------------------------------------------------------------

float fftBinDb(float bin)
{
    float freq = fMin * pow(fMax / fMin, (bin + 0.5) / float(fftBins));
    float oct  = log2_(freq / spectrumKneeHz);

    // broadband shape: flat to the knee, tilted above it, with the bottom and
    // top octaves falling away faster
    float db = inputLevelDb() + spectrumHeadroomDb;
    db -= spectrumTiltDbPerOct * max(oct, 0.0);
    db -= subRolloffDbPerOct * max(-oct, 0.0);
    db -= airRolloffDbPerOct * max(log2_(freq / airHz), 0.0);

    // two drifting bells, standing in for whatever the music is doing
    db += bellDb(freq, 180.0 * pow(2.0, 1.2 * sin(iTime * 0.23)), 0.55,
                 9.0 * (0.5 + 0.5 * sin(iTime * 0.70)));
    db += bellDb(freq, 2200.0 * pow(2.0, 1.5 * sin(iTime * 0.17 + 2.0)), 0.75,
                 7.0 * (0.5 + 0.5 * sin(iTime * 0.53 + 1.0)));

    // per-bin flutter: a fast flicker riding on a slower drift
    float flutter = mix(binNoise(bin, binDriftRate, 0.0),
                        binNoise(bin, binFlickerRate, 37.0), 0.5);
    db += (flutter - 0.5) * 2.0 * binFlutterDb;

    return db;
}

/* Bin magnitude as a height, 0 at the bottom edge of the widget, 1 at the top. */
float binHeight(float bin)
{
    bin = clamp(bin, 0.0, float(fftBins) - 1.0);
    return clamp((fftBinDb(bin) - dbFloor) / (dbTop - dbFloor), 0.0, 1.0);
}

/* Continuous-trace height at x (0 .. 1 across the widget): the bin heights
   smoothstepped into each other, jagged but without vertical steps. */
float traceHeight(float x)
{
    float bin = x * float(fftBins) - 0.5;
    float i = floor(bin);
    float f = fract(bin);
    f = f * f * (3.0 - 2.0 * f);
    return mix(binHeight(i), binHeight(i + 1.0), f);
}

// --------------------------------------------------------------------------------

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec2 uv = fragCoord / iResolution.xy;   // 0 .. 1, y up

    float height;    // top of the fill at this column, 0 .. 1
    float barMask = 1.0;

    if (barGap > 0.0)
    {
        // discrete bars: one flat-topped block per bin, with a gap between them
        float bin = floor(uv.x * float(fftBins));
        height = binHeight(bin);

        float within = fract(uv.x * float(fftBins));
        float edge   = barGap * 0.5;
        float aaX    = float(fftBins) / iResolution.x;   // one pixel, in bar units
        barMask = smoothstep(edge - aaX, edge + aaX, within)
                * smoothstep(edge - aaX, edge + aaX, 1.0 - within);
    }
    else
    {
        height = traceHeight(uv.x);
    }

    // Filled below the trace and transparent above it, fading out over the last
    // topSoftness of the way up. The band follows the contour, so the spectrum
    // still reads -- it just has no hard edge. Never narrower than a pixel, or
    // the edge would alias.
    float aaY = 1.0 / iResolution.y;
    float fill = 1.0 - smoothstep(height - max(topSoftness, aaY), height, uv.y);

    // Horizontal palette sweep, vertical shading on top of it: 0 at the bottom
    // edge, 1 at fillGradientTop and above.
    float g = clamp(uv.y / max(fillGradientTop, 0.001), 0.0, 1.0);
    vec3  fillColor = mix(fillGrey, rainbow(uv.x), paletteAmount)
                    * mix(fillBrightnessBottom, fillBrightnessTop, g);
    float fillAlpha = mix(fillAlphaBottom, fillAlphaTop, g) * fill * barMask;

    // Straight (non-premultiplied) alpha. DPF draws subwidgets with
    // glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA), so the colour must not
    // be premultiplied here -- the hardware would then multiply by alpha a
    // second time and the soft top edge would fade through black instead of
    // fading to transparent.
    fragColor = vec4(fillColor, fillAlpha * analyserOpacity);
}
