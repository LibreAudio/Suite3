// Libre Audio Suite
// Copyright (C) 2026 Filipe Coelho <falktx@falktx.com>
// SPDX-License-Identifier: GPL-3.0-or-later

// DPF variables
uniform float _dpf_border_radius;
uniform vec2 _dpf_position;

// ShaderToy variables
// uniform float iBeat;
// uniform vec4 iPeaks;
uniform sampler2D iChannel0;
uniform vec3 iMouse;
uniform vec3 iResolution;
uniform float iScaleFactor;
uniform float iTime;

// forward declaration of ShaderToy entry point
void mainImage(out vec4 fragColor, in vec2 fragCoord);

// based on https://www.shadertoy.com/view/MXVGDV
float drawRoundedRect(in float longSide, in float shortSide, in float differenceXY, float circleDistanceAlongShortSide) {
    if (longSide < 0.) {
        differenceXY = -differenceXY;
    }

    if (abs(longSide) < abs(differenceXY) + circleDistanceAlongShortSide) {
        // Space between the circle along the longSide.
        // Always use the longest distance possible to cover the space.
        longSide = 0. - circleDistanceAlongShortSide;
    } else {
        // Increase the circle distance along the longSide by differenceXY.
        longSide -= differenceXY;
    }

    if (abs(shortSide) < circleDistanceAlongShortSide) {
        // Space between the circle along the shortSide.
        // Same as above.
        shortSide = 0. - circleDistanceAlongShortSide;
    }

    float rawDistanceToCenter = length(abs(vec2(longSide, shortSide)) - circleDistanceAlongShortSide);
    return rawDistanceToCenter;
}

void main()
{
    mainImage(gl_FragColor, gl_FragCoord.xy - _dpf_position);

    if (_dpf_border_radius == 0.0)
        return;

    // Move the coordinate zero to the center.
    vec2 centeredCoordinate = gl_FragCoord.xy - _dpf_position - iResolution.xy / 2.;

    float circleDistanceAlongShortSide = min(iResolution.x, iResolution.y) / 2. - _dpf_border_radius - 0.5;
    float differenceXY = (iResolution.x - iResolution.y) / 2.;
    float relativeDistanceToCenter;

    if (differenceXY > 0.)
    {
        // The resolution is wider than it is tall.
        float distanceToCenter = drawRoundedRect(centeredCoordinate.x, centeredCoordinate.y, differenceXY, circleDistanceAlongShortSide);
        relativeDistanceToCenter = log(distanceToCenter / (iResolution.y / 2. - circleDistanceAlongShortSide));
    }
    else
    {
        // The resolution is taller than it is wide.
        differenceXY = abs(differenceXY);
        float distanceToCenter = drawRoundedRect(centeredCoordinate.y, centeredCoordinate.x, differenceXY, circleDistanceAlongShortSide);
        relativeDistanceToCenter = log(distanceToCenter / (iResolution.x / 2. - circleDistanceAlongShortSide));
    }

    float alpha = 1. - step(0., relativeDistanceToCenter);
    gl_FragColor = vec4(gl_FragColor.xyz, gl_FragColor.a * alpha);
}
