#version 460 core
// Foyer's fireplace. Flutter fragment shader (listed under "shaders:" in pubspec.yaml by
// tools/patch_fonts.py). Drawn small and scaled up by the app, which keeps it smooth on TV boxes.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;   // size being drawn, in pixels
uniform float uTime;  // seconds

out vec4 fragColor;

// ── Foyer fireplace ── a close-up of a wood fire: turbulent flames, glowing logs, sparks,
// and light that flickers on the brick behind. Everything is maths; there is no video.

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    float a = 0.5;
    float s = 0.0;
    for (int i = 0; i < 5; i++) {
        s += a * noise(p);
        p = p * 2.03 + vec2(1.7, 9.2);
        a *= 0.5;
    }
    return s;
}

// distance to a log: a thick line from a to b
float logDist(vec2 p, vec2 a, vec2 b, float r) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// black -> deep red -> orange -> yellow -> near white, like a real flame's heat
vec3 heat(float f) {
    vec3 c = mix(vec3(0.0), vec3(0.55, 0.04, 0.0), smoothstep(0.0, 0.22, f));
    c = mix(c, vec3(1.0, 0.33, 0.02), smoothstep(0.18, 0.48, f));
    c = mix(c, vec3(1.0, 0.72, 0.18), smoothstep(0.42, 0.74, f));
    c = mix(c, vec3(1.0, 0.96, 0.78), smoothstep(0.72, 1.0, f));
    return c;
}

vec3 fireScene(vec2 uv, float aspect, float t) {
    // p: x centred and stretched by the screen shape, y from 0 (bottom) to 1 (top)
    vec2 p = vec2((uv.x - 0.5) * aspect, uv.y);

    // the whole fire breathes: brighter and dimmer a few times a second
    float flick = 0.80 + 0.20 * noise(vec2(t * 2.7, 3.0)) + 0.06 * sin(t * 11.0);

    // ── brick wall behind, lit by the fire ──
    vec2 bp = vec2(p.x * 5.2, p.y * 9.5);
    bp.x += step(1.0, mod(bp.y, 2.0)) * 0.5;
    vec2 bf = fract(bp);
    float mortar = smoothstep(0.0, 0.07, bf.x) * smoothstep(0.0, 0.14, bf.y)
                 * smoothstep(0.0, 0.07, 1.0 - bf.x) * smoothstep(0.0, 0.14, 1.0 - bf.y);
    float brickTone = 0.75 + 0.5 * hash(floor(bp));
    float grain = 0.8 + 0.4 * noise(p * 40.0);
    vec3 wall = vec3(0.30, 0.13, 0.07) * brickTone * grain * (0.35 + 0.65 * mortar);
    float lightDist = length(vec2(p.x * 0.75, p.y - 0.30));
    float wallLight = flick * 1.9 / (1.0 + 5.5 * lightDist * lightDist);
    vec3 col = wall * wallLight * vec3(1.0, 0.62, 0.36);

    // ── hearth floor ──
    float floorY = 0.105;
    if (p.y < floorY) {
        float d = floorY - p.y;
        vec3 stone = vec3(0.10, 0.07, 0.06) * (0.7 + 0.6 * noise(vec2(p.x * 30.0, d * 90.0)));
        float shine = flick * exp(-abs(p.x) * 1.8) * exp(-d * 9.0);
        col = stone * (0.25 + 1.6 * shine) * vec3(1.0, 0.6, 0.34) + vec3(0.9, 0.35, 0.08) * shine * 0.35;
    }

    // ── flames (worked out first, so logs can sit in front of them) ──
    vec2 q = vec2(p.x, p.y - 0.19);
    float yn = q.y / 0.66;                       // 0 at the logs, 1 at the tips
    float n1 = fbm(vec2(q.x * 2.6, q.y * 1.9 - t * 1.25));
    // sideways sway grows with height, so tongues lick left and right
    float x = q.x + (n1 - 0.5) * 0.42 * yn + sin(t * 1.3 + q.y * 6.0) * 0.015 * yn;
    float n2 = fbm(vec2(x * 5.2 + n1 * 1.4, q.y * 3.4 - t * 2.6));
    float n3 = noise(vec2(x * 11.0 + n2 * 2.5, q.y * 7.5 - t * 4.6));
    // slow, wide waves decide where the tall tongues are right now
    float lobes = 0.55 + 0.45 * noise(vec2(x * 2.6 + 20.0, t * 0.45));
    // turbulence has to "beat" the height: that is what tears the top into tongues
    float f = (n1 * 0.50 + n2 * 0.62 + n3 * 0.16) * 1.62 * (0.55 + 0.6 * lobes)
            - yn * (1.02 - 0.25 * lobes)
            - pow(abs(x) / 0.60, 2.2) * 0.95;
    f *= smoothstep(-0.03, 0.03, q.y);
    f = clamp(f * 1.35, 0.0, 1.0);
    // hottest and whitest low in the fire; the tips cool to orange and red
    float heatAmt = f * (0.90 - 0.36 * smoothstep(0.10, 0.95, yn));
    heatAmt = pow(heatAmt, 1.38);
    vec3 flame = heat(heatAmt) * (0.92 + 0.22 * flick);

    // ── logs ──
    float rBack = 0.060; float rA = 0.072; float rB = 0.066;
    float dBack = logDist(p, vec2(-0.46, 0.205), vec2(0.50, 0.215), rBack);
    float dA = logDist(p, vec2(-0.66, 0.150), vec2(0.30, 0.262), rA);
    float dB = logDist(p, vec2(-0.28, 0.272), vec2(0.68, 0.148), rB);
    // which log is nearest the viewer here (front ones win)
    float dLog = dBack; float rLog = rBack; float along = p.x; float id = 1.0;
    if (dA < 0.0) { dLog = dA; rLog = rA; along = p.x * 0.993 + p.y * 0.116; id = 2.0; }
    if (dB < 0.0) { dLog = dB; rLog = rB; along = p.x * 0.992 - p.y * 0.128; id = 3.0; }
    bool onLog = dLog < 0.0;
    vec3 logCol = vec3(0.0);
    if (onLog) {
        float depth = clamp(-dLog / rLog, 0.0, 1.0);          // 0 at the edge, 1 along the middle
        float round_ = sqrt(depth);                            // round like a cylinder
        // bark: long streaks along the log, broken up
        float bark = fbm(vec2(along * 7.0 + id * 7.0, (p.y - along * 0.12 * (id - 2.0)) * 95.0))
                   * 0.75 + fbm(vec2(along * 30.0, p.y * 30.0 + id * 3.0)) * 0.35;
        vec3 wood = mix(vec3(0.045, 0.024, 0.014), vec3(0.230, 0.120, 0.058), bark);
        // lit from above by the flames, dark underneath and at the edges
        float up = smoothstep(-0.9, 0.9, (p.y - (0.19 + (id - 2.0) * 0.0)) / rLog - 0.2);
        float lit = (0.18 + 0.82 * round_) * (0.30 + 1.0 * up);
        logCol = wood * lit * (1.1 + 1.6 * flick) * vec3(1.0, 0.68, 0.44);
        // charred, glowing cracks: only in a few hot patches, as thin lines
        float region = smoothstep(0.50, 0.66, fbm(vec2(along * 3.2 + id * 11.0, p.y * 9.0 + t * 0.02)));
        float crack = fbm(vec2(along * 18.0 + id * 5.0, p.y * 55.0));
        float veins = clamp(1.0 - abs(crack - 0.5) * 24.0, 0.0, 1.0);
        float pulse = 0.5 + 0.5 * noise(vec2(along * 5.0 + t * 0.8, id + t * 0.3));
        float ember = region * (veins * 0.95 + 0.22) * pulse;
        ember *= 0.35 + 0.85 * up;
        logCol += heat(clamp(ember, 0.0, 1.0)) * 1.2;
        // a darker line where one log meets another or the floor
        logCol *= 0.35 + 0.65 * smoothstep(0.0, 0.22, depth);
    }
    // bed of glowing coals under the logs
    float coalBed = exp(-(p.x * 2.0) * (p.x * 2.0)) * smoothstep(0.085, 0.125, p.y) * (1.0 - smoothstep(0.125, 0.20, p.y));
    float coalN = fbm(vec2(p.x * 24.0, p.y * 44.0 + t * 0.05));
    vec3 coals = heat(clamp(coalBed * (0.30 + 1.1 * coalN) * (0.75 + 0.25 * flick), 0.0, 1.0));

    // ── put it together: wall, then flames, then logs, then flames licking over the logs ──
    col = col * (1.0 - 0.9 * smoothstep(0.2, 0.75, f)) + flame;
    if (onLog) {
        float edge = smoothstep(0.0, -0.006, dLog);
        float lick = smoothstep(0.30, 0.75, f) * smoothstep(0.19, 0.30, p.y) * 0.78;
        col = mix(col, mix(logCol, logCol * 0.35 + flame, lick), edge);
    }
    col += coals * (onLog ? 0.15 : 0.85);

    // warm haze around the fire
    float haze = flick * 0.20 * exp(-6.0 * length(vec2(p.x * 0.8, (p.y - 0.36) * 1.1)));
    col += vec3(1.0, 0.45, 0.12) * haze;

    // ── sparks ──
    for (int i = 0; i < 16; i++) {
        float fi = float(i);
        float seed = hash(vec2(fi, 7.3));
        float speed = 0.16 + 0.22 * hash(vec2(fi, 1.9));
        float life = fract(t * speed + seed * 13.0);
        float lane = floor(t * speed + seed * 13.0);
        float sx = (hash(vec2(fi, lane)) - 0.5) * 0.7;
        float drift = (hash(vec2(lane, fi + 3.0)) - 0.5) * 0.5;
        vec2 sp = vec2(sx + drift * life + 0.03 * sin(t * 5.0 + fi * 2.0) * life,
                       0.24 + life * (0.55 + 0.35 * seed));
        float d = length(p - sp);
        float bright = (1.0 - life) * (1.0 - life) * smoothstep(0.0, 0.08, life);
        col += vec3(1.0, 0.62, 0.20) * bright * (0.0000085 / (d * d + 0.0000055));
    }

    // darker toward the corners, like a real room at night
    float vig = 1.0 - 0.55 * pow(length(vec2((uv.x - 0.5) * 1.25, uv.y - 0.42)), 2.2);
    col *= clamp(vig, 0.0, 1.0);
    // soft roll-off so the hottest parts glow instead of clipping
    col = col / (1.0 + col * 0.18);
    return col;
}

void main() {
    vec2 fc = FlutterFragCoord().xy;
    // Flutter counts y from the top; the scene counts from the hearth up
    vec2 uv = vec2(fc.x / uSize.x, 1.0 - fc.y / uSize.y);
    fragColor = vec4(fireScene(uv, uSize.x / uSize.y, uTime), 1.0);
}
