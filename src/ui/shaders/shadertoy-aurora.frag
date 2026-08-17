// Auroras by nimitz 2017 (twitter: @stormoid)
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License
// Contact the author for other licensing options

/*
	
	There are two main hurdles I encountered rendering this effect. 
	First, the nature of the texture that needs to be generated to get a believable effect
	needs to be very specific, with large scale band-like structures, small scale non-smooth variations
	to create the trail-like effect, a method for animating said texture smoothly and finally doing all
	of this cheaply enough to be able to evaluate it several times per fragment/pixel.

	The second obstacle is the need to render a large volume while keeping the computational cost low.
	Since the effect requires the trails to extend way up in the atmosphere to look good, this means
	that the evaluated volume cannot be as constrained as with cloud effects. My solution was to make
	the sample stride increase polynomially, which works very well as long as the trails are lower opcaity than
	the rest of the effect. Which is always the case for auroras.

	After that, there were some issues with getting the correct emission curves and removing banding at lowered
	sample densities, this was fixed by a combination of sample number influenced dithering and slight sample blending.

	N.B. the base setup is from an old shader and ideally the effect would take an arbitrary ray origin and
	direction. But this was not required for this demo and would be trivial to fix.
*/

// Camera pitch in radians. The bottom of the frame looks 21 degrees (0.37 rad) below
// the view axis, so anything past that keeps the horizon off screen; past ~1.4 the
// aurora ends up behind the camera.
const float pitch = 0.7;

// Ray-march sample count, the main cost knob. The original shader used 50; the march
// profile is normalised against that, so this is safe to lower. Below ~16 the trails
// start to show banding that the dither can no longer hide.
const float STEPS = 24.;

// Aurora palette. Each trail colour is its tint sunk into the near-black base by
// `darkening`: 0 leaves the tint untouched, 1 collapses it into the base. 0.6 is the
// "40% over #0a0a0d" mix. Raise it to pull the whole aurora down without shifting hue.
const vec3 baseTop = vec3(0.1, 0.1, 0.1); 
const vec3 baseBottom = vec3(0.0,0.0,0.0);

#ifndef LIBREAUDIO_HOSTED
const vec3 tintLow  = vec3(0.7647, 0.8510, 1.0000); // #c3d9ff, the prominent colour
const vec3 tintHigh = vec3(0.8549, 0.7569, 0.9529); // #dac1f3, the trail tops
#else
uniform float u_input_peak_L;
uniform float u_input_peak_R;
float input_peak = 1.0 - clamp((max(u_input_peak_L, u_input_peak_R) - 24.0) / -114.0, 0.0, 0.5);
vec3 tintLow  = vec3(0.7647, 0.8510, 1.0000) * input_peak; // #c3d9ff, the prominent colour
vec3 tintHigh = vec3(0.8549, 0.7569, 0.9529) * input_peak; // #dac1f3, the trail tops
#endif

const float darkening = 0.3;

mat2 mm2(in float a){float c = cos(a), s = sin(a);return mat2(c,s,-s,c);}
// the octave loop only ever uses -m2, so store it pre-negated
mat2 nm2 = mat2(-0.95534, -0.29552, 0.29552, -0.95534);
float tri(in float x){return clamp(abs(fract(x)-.5),0.01,0.49);}
// tri(p.x) feeds both components, so evaluate it once: 3 tri() per call instead of 4
vec2 tri2(in vec2 p){float tx = tri(p.x);return vec2(tx+tri(p.y),tri(p.y+tx));}

float triNoise2d(in vec2 p, in mat2 spdRot)
{
    float z=1.8;
    float z2=2.5;
	float rz = 0.;
    p *= mm2(p.x*0.06);
    vec2 bp = p;
	for (float i=0.; i<4.; i++ ) // 5th octave carried under 2% of the noise weight
	{
        vec2 dg = tri2(bp*1.85)*.75;
        dg *= spdRot;
        p -= dg/z2;

        bp *= 1.3;
        z2 *= .45;
        z *= .42;
		p *= 1.21 + (rz-1.0)*.02;
        
        rz += tri(p.x+tri(p.y))*z;
        p*= nm2;
	}
    return clamp(1./pow(rz*29., 1.3),0.,.55);
}

float hash21(in vec2 n){ return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453); }
vec4 aurora(vec3 ro, vec3 rd)
{
    vec4 col = vec4(0);
    vec4 avgCol = vec4(0);

    // The march profile is written against the original 50-sample index (ii), so STEPS
    // only controls how coarsely that same volume is sampled -- the extent, the falloff
    // and the colour ramp all stay put. Cost is linear in STEPS.
    float sstep = 50./STEPS;

    // Loop-invariant: the dither offset, the stride divisor and the scroll rotation do
    // not depend on i, and the exp2 falloff is geometric so it becomes a running
    // multiply. The dither scales with slice thickness, since thicker slices band more.
    // (the palette mix lives here rather than at file scope: GLSL will not take a
    // built-in call in a global initializer)
    vec3 colLow  = mix(tintLow,  baseTop, darkening);
    vec3 colHigh = mix(tintHigh, baseTop, darkening);

    float ofs = 0.006*sstep*hash21(gl_FragCoord.xy);
    float istride = 1./(rd.y*2.+0.4);
    mat2 spdRot = mm2(iTime*0.06);
    float w = exp2(-2.5);
    float wDecay = exp2(-0.065*sstep);

    for(float i=0.;i<STEPS;i++)
    {
        float ii = i*sstep;
        float pt = ((.8+pow(ii,1.4)*.002)-ro.y)*istride - ofs*smoothstep(0.,15., ii);
        vec2 p = ro.zx + pt*rd.zx;
        float rzt = triNoise2d(p, spdRot);
        vec4 col2 = vec4(0,0,0, rzt);
        col2.rgb = mix(colLow, colHigh, smoothstep(0.,40.,ii))*rzt;
        avgCol =  mix(avgCol, col2, .5);
        col += avgCol*w*smoothstep(0.,5., ii);
        w *= wDecay;
    }

    col *= (clamp(rd.y*15.,0.,1.));
    // fewer samples each stand for a thicker slice, so rescale to hold brightness
    return col*1.8*sstep;
}


//-------------------Background--------------------

vec3 bg(in vec3 rd)
{
    float sd = dot(normalize(vec3(-0.5, -0.6, 0.9)), rd)*0.5+0.5;
    sd = pow(sd, 5.);
    vec3 col = mix(baseTop, baseBottom, sd);
    return col*.60;
}
//-----------------------------------------------------------


void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec2 p = fragCoord.xy / iResolution.xy - 0.5;
	p.x*=iResolution.x/iResolution.y;

    vec3 ro = vec3(0,0,-6.7);
    vec3 rd = normalize(vec3(p,1.3));

    rd.yz *= mm2(pitch);
    rd.xz *= mm2(sin(iTime*0.05)*0.2);
    
    vec3 col = bg(rd);

    if (rd.y > 0.){
        vec4 aur = smoothstep(0.,1.5,aurora(ro,rd));
        col = col*(1.-aur.a) + aur.rgb;
    }

	fragColor = vec4(col, 1.);
}
