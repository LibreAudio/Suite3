// Cloud starfield -- the colour clouds wash with a slow starfield behind it.
//
// Two layers. The clouds are a single simplex noise field used twice: once to
// modulate the lit band, once to warp the height fed into the colour gradient.
// Behind them the camera flies into a starfield: several depth slices of a
// hash-based star grid, each with its own perspective divide, so stars stream out
// of the centre of the widget and swell as they pass. No ray marching and no
// feedback buffer -- the depth is faked with one scale factor per slice.

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

// Starfield. Measured in centred, width-normalised space so the flight axis is the
// middle of the widget and stars stay round whatever shape it is. Deliberately
// independent of the input meters -- like backgroundColor, the sky does not pump.
const vec3  starColor      = vec3(0.86, 0.91, 1.0);
const int   starLayers     = 4;     // depth slices; more = denser stream, more cost
const float starSpeed      = 0.05;  // depth cycles per second -- how fast you fly
const float starNearZ      = 0.2;  // depth a slice reaches before recycling; lower = more zoom
const float starDensity    = 50.0;  // cells across the width at the far plane
const float starChance     = 0.2;  // fraction of cells that actually hold a star
const float starSize       = 0.045; // star radius as a fraction of a cell
const float starBrightness = 0.6;  // peak brightness of the brightest stars
const float starOcclusion  = 0.;  // how much the clouds hide the stars behind them

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
// Starfield
// --------------------------------------------------------------------------------

// Two decorrelated randoms per cell, from the usual fract/dot scramble. Cheap and
// stable: the same cell always returns the same pair, so stars stay put.
vec2 hash22(vec2 p)
{
    vec3 a = fract(p.xyx * vec3(123.34, 234.34, 345.65));
    a += dot(a, a + 34.45);
    return fract(vec2(a.x * a.y, a.y * a.z));
}

// One depth slice. `sp` is centred screen space, 0 at the middle and +-0.5 across
// the width. `z` runs 0 (far) to 1 (about to pass the camera). Returns 0..1.
float starSlice(vec2 sp, float z, float seed)
{
    // Perspective. A star sitting at a fixed (X, Y, Z) lands at (X, Y) / Z on
    // screen, so to find which star covers this pixel we go the other way and
    // sample the grid at sp * Z. As Z shrinks the patch of grid on screen shrinks
    // with it -- that magnification is the whole illusion of flying in.
    float Z = mix(1.0, starNearZ, z);

    vec2 gp   = sp * Z * starDensity + seed;
    vec2 cell = floor(gp);
    vec2 f    = fract(gp);

    vec2 rPos  = hash22(cell);
    vec2 rMisc = hash22(cell + 7.3);

    // Keep the star clear of the cell border so its falloff is never clipped by
    // the edge -- only this one cell is sampled, so a star straddling a boundary
    // would show a hard cut.
    vec2 pos = vec2(0.2, 0.2) + 0.6 * rPos;

    // The radius is fixed in grid space, so the same magnification that carries
    // the star outwards also swells it, exactly as perspective should.
    float core   = smoothstep(starSize, 0.0, length(f - pos));
    float exists = step(1.0 - starChance, rMisc.x);

    float magnitude = 0.35 + 0.65 * fract(rMisc.y * 7.13);

    // Fade up out of the distance and back down just before the slice recycles,
    // so nothing pops into or out of existence at the seam.
    float fade = smoothstep(0.0, 0.25, z) * smoothstep(1.0, 0.75, z);

    return core * exists * magnitude * fade;
}

// The slices are spread evenly through the cycle and all advance together, so
// what arrives is a steady stream rather than pulses.
float starfield(vec2 sp, float t)
{
    float total = 0.0;

    for (int i = 0; i < starLayers; ++i)
    {
        float z = fract(float(i) / float(starLayers) + t * starSpeed);
        total += starSlice(sp, z, float(i) * 37.3);
    }

    return clamp(total, 0.0, 1.0);
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

    // Stars sit behind the clouds, so thick cloud hides them. `intensity` doubles
    // as the cloud density here, which is why this reads the unclamped value back
    // through clamp rather than reusing the envelope on its own.
    float cloudCover = clamp(intensity, 0.0, 1.0);

    // Centred, width-normalised coords put the vanishing point in the middle of
    // the widget; the starfield does its own scaling per depth slice.
    vec2 flight = (fragCoord.xy - 0.5 * iResolution.xy) / iResolution.x;
    float stars = starfield(flight, iTime) * (1.0 - starOcclusion * cloudCover);

    // brightness scales only the clouds -- background and stars stay put, so
    // neither the base nor the sky pumps with the meters.
    vec3 sky = backgroundColor + starColor * (stars * starBrightness);

    fragColor = vec4(sky + tint * intensity * brightness, 1.0);
}
