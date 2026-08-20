// Colour clouds -- a slow aurora-like wash driven by 3D simplex noise.
//
// The effect is a single noise field used twice: once to modulate the vertical
// intensity ramp, once to warp the height fed into the colour gradient. There is
// no ray marching and no feedback buffer, so the whole thing costs one simplex
// noise evaluation per pixel.

// --------------------------------------------------------------------------------
// Tunables
// --------------------------------------------------------------------------------

// Colour the clouds are composited over. The original shader had no visible
// background -- the tint was multiplied by its own intensity and written straight
// out -- so black reproduces the original look exactly. Raise it for a lifted,
// hazier base.
const vec3 backgroundColor = vec3(0.0, 0.0, 0.0);

// Gradient endpoints. `colorLow` dominates near the bottom of the frame,
// `colorHigh` near the top. (These were `color1` / `color2`.)
const vec3 colorLow  = vec3(0.8549, 0.7569, 0.9529); // soft violet
const vec3 colorHigh = vec3(0.7647, 0.8510, 1.0000); // pale blue

const float timeScale     = 0.1; // animation speed
const float noiseScale    = 3.0; // spatial frequency of the cloud structure
const float intensityGain = 1.0; // overall strength of the lit band
const float warpAmount    = 0.1; // how far noise displaces the gradient height
const float gradientSpan  = 1.5; // how quickly the gradient runs low -> high

// Framing envelope. The clouds sit in a soft bump centred a little above the
// middle of the widget and fade out towards every edge, so the top no longer
// collects all the brightness. Coordinates are 0..1 across the widget, y up.
const float cloudCenterY = 0.55; // 0.5 is dead centre; higher sits above it
const float cloudSpreadY = 0.45; // distance from the centre at which it reaches zero
const float cloudSpreadX = 0.60; // same, horizontally, measured from the middle

// Overall output brightness, 0..1. In the plugin it tracks the input peak meters
// so the clouds brighten with the signal; standalone it is a flat 1.0, since the
// Shadertoy editor has no custom uniforms.
#ifndef LIBREAUDIO_HOSTED
#define brightness 1.0
#else
// Peak of the two input meters in dBFS, smoothed by the host over two different
// time constants: iLevelSlow settles in about 5 s, iLevelFast in about 0.5 s.
// The smoothing cannot live here -- a fragment shader keeps no state between
// frames -- so these arrive already integrated. See LibreAudioBackgroundShaderWidget.
uniform float iLevelSlow;
uniform float iLevelFast;

// The input window the picture responds to, in dBFS. Programme material peaks
// mostly between -40 and 0, so that is the span worth spending the whole
// brightness range on -- outside it the response just flattens off.
const float meterFloorDb = -40.0;
const float meterCeilDb  =   0.0;

// How far the picture is allowed to dim once the input reaches meterFloorDb.
// 0.5 keeps silence at half brightness rather than fully dark.
const float meterDimDepth = 0.5;

// How much of the fast envelope rides on top of the slow one. 0.0 leaves the
// brightness following the 5 s average alone; 1.0 makes it purely 0.5 s and
// twitchy. In between, the slow envelope sets the level the picture sits at and
// the fast one supplies the movement around it.
const float shortTermAmount = 0.5;

float levelSlow = clamp((iLevelSlow - meterFloorDb) / (meterCeilDb - meterFloorDb), 0.0, 1.0);
float levelFast = clamp((iLevelFast - meterFloorDb) / (meterCeilDb - meterFloorDb), 0.0, 1.0);

// Both are already 0..1, so the mix cannot leave that range.
float meterLevel = mix(levelSlow, levelFast, shortTermAmount);

// 1.0 at or above meterCeilDb, falling to 1.0 - meterDimDepth at or below the floor.
float brightness = 1.0 - meterDimDepth * (1.0 - meterLevel);
#endif

// --------------------------------------------------------------------------------
// 3D simplex noise -- based on code by Ian McEwan, Ashima Arts (MIT).
// Returns roughly [-1, 1]. Left as the canonical implementation; it is well
// tested and any "tidying" here risks changing the output.
// --------------------------------------------------------------------------------

vec3 mod289(vec3 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 mod289(vec4 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 permute(vec4 x) {
  return mod289(((x * 34.0) + 1.0) * x);
}

vec4 taylorInvSqrt(vec4 r) {
  return 1.79284291400159 - 0.85373472095314 * r;
}

float snoise(vec3 v) {
  const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
  const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

  // First corner
  vec3 i  = floor(v + dot(v, C.yyy));
  vec3 x0 = v - i + dot(i, C.xxx);

  // Other corners
  vec3 g  = step(x0.yzx, x0.xyz);
  vec3 l  = 1.0 - g;
  vec3 i1 = min(g.xyz, l.zxy);
  vec3 i2 = max(g.xyz, l.zxy);

  //  x0 = x0 - 0. + 0.0 * C
  vec3 x1 = x0 - i1 + 1.0 * C.xxx;
  vec3 x2 = x0 - i2 + 2.0 * C.xxx;
  vec3 x3 = x0 - 1.0 + 3.0 * C.xxx;

  // Permutations
  i = mod289(i);
  vec4 p = permute(permute(permute(
             i.z + vec4(0.0, i1.z, i2.z, 1.0))
           + i.y + vec4(0.0, i1.y, i2.y, 1.0))
           + i.x + vec4(0.0, i1.x, i2.x, 1.0));

  // Gradients: 7x7 points over a square, mapped onto an octahedron.
  float n_ = 1.0 / 7.0; // N=7
  vec3  ns = n_ * D.wyz - D.xzx;

  vec4 j = p - 49.0 * floor(p * ns.z * ns.z); // mod(p, N*N)

  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_); // mod(j, N)

  vec4 x = x_ * ns.x + ns.yyyy;
  vec4 y = y_ * ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);

  vec4 b0 = vec4(x.xy, y.xy);
  vec4 b1 = vec4(x.zw, y.zw);

  vec4 s0 = floor(b0) * 2.0 + 1.0;
  vec4 s1 = floor(b1) * 2.0 + 1.0;
  vec4 sh = -step(h, vec4(0.0));

  vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
  vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

  vec3 p0 = vec3(a0.xy, h.x);
  vec3 p1 = vec3(a0.zw, h.y);
  vec3 p2 = vec3(a1.xy, h.z);
  vec3 p3 = vec3(a1.zw, h.w);

  // Normalise gradients
  vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
  p0 *= norm.x;
  p1 *= norm.y;
  p2 *= norm.z;
  p3 *= norm.w;

  // Mix final noise value
  vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
  m = m * m;
  return 45.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// --------------------------------------------------------------------------------

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    // Aspect-corrected UV: both axes are normalised by the *width*, so the noise
    // stays square regardless of the widget's shape. This is the one-divide form
    // of the original `uv = coord / res; uv.y *= res.y / res.x;`.
    vec2 uv = fragCoord.xy / iResolution.xx;

    // Plain 0..1 screen position, used only for the framing envelope: that has to
    // be measured against the real edges, not the square noise space, or the band
    // would drift with the widget's aspect ratio.
    vec2 screen = fragCoord.xy / iResolution.xy;

    float time = iTime * timeScale;

    // The single noise field the whole effect is built from.
    float noise = snoise(vec3(uv * noiseScale, time));

    // Distance from the centre of the lit band, in units of its own spread, so
    // 0 is the centre and 1 is where it has faded out completely.
    float offY = abs(screen.y - cloudCenterY) / cloudSpreadY;
    float offX = abs(screen.x - 0.5)          / cloudSpreadX;

    // smoothstep(1, 0, d) runs 1 -> 0 as d goes 0 -> 1 and clamps beyond, giving a
    // symmetric bump: equal falloff above and below the centre, and towards both
    // side edges. Multiplying the two shapes it in both axes at once.
    float envelope  = smoothstep(1.0, 0.0, offY) * smoothstep(1.0, 0.0, offX);
    float intensity = envelope * intensityGain * (0.5 + 0.5 * noise);

    // Warp the height used for the gradient so the colour boundary undulates
    // instead of running dead level. This still uses the square-space height, so
    // the palette keeps its original vertical run independent of the envelope.
    float gradientHeight = uv.y + noise * warpAmount;

    vec3 tint = mix(colorLow, colorHigh, gradientHeight * gradientSpan + noise);

    // brightness scales only the clouds -- the background stays put, so raising
    // backgroundColor gives a fixed base the meters cannot pump.
    fragColor = vec4(backgroundColor + tint * intensity * brightness, 1.0);
}
