#version 460 core

// One piece of the misbaha, lit per pixel (the «ثلاثي الأبعاد حقيقي»
// rendering). The piece is a bead or the metal joint (an ellipsoid whose
// surface is found by a ray through the pixel) or one of the imam's turned
// pieces (a body of revolution between two screen points). Its material
// draws its own surface: wood rings round the string, amber clouds,
// pearl's faint bands, turquoise veins, yusr's silver dots. The light is a
// key light with a clear-coat highlight, the reflection of a small studio
// (a sky and three soft panels), a rim, a glow through amber, and
// darkening toward the two neighbours and the surface it lies on.
//
// View space: x right, y up, z toward the eye.

#include <flutter/runtime_effect.glsl>

uniform vec2 uA;          // the centre; a turned piece's base
uniform vec2 uB;          // a turned piece's tip
uniform float uRadius;    // the bead's radius on screen
uniform float uShape;     // 0 ellipsoid, 1 the imam's drop, 2 its cap, 3 the joint (a short cylinder)
uniform float uRatio;     // the length along the axis, in radii
uniform vec3 uAxis;       // the string's direction through the piece
uniform float uKind;      // 0 amber 1 wood 2 pearl 3 rosewood 4 turquoise 5 yusr 6 metal
uniform float uSeed;
uniform vec3 uC0;         // the colour round the middle
uniform vec3 uC1;         // the colour at the two holes
uniform float uRough;
uniform float uCoat;
uniform float uCoatRough;
uniform float uEnv;
uniform vec3 uEmit;
uniform float uScatter;
uniform vec3 uLight;
uniform vec2 uCam;        // the camera pitch's sine and cosine
uniform vec3 uN1;         // toward each neighbour, scaled by its closeness
uniform vec3 uN2;
uniform float uGround;

out vec4 fragColor;

vec3 toLinear(vec3 c) {
  return pow(c, vec3(2.2));
}

float hash1(float n) {
  return fract(sin(n * 12.9898 + uSeed) * 43758.5453);
}

float noise1(float x) {
  float i = floor(x);
  float f = fract(x);
  f = f * f * (3.0 - 2.0 * f);
  return mix(hash1(i), hash1(i + 1.0), f);
}

// A smooth wandering value, -1..1.
float waves(vec3 p) {
  return (sin(p.x * 1.7 + 1.3 * sin(p.y * 1.1 + uSeed)) +
          sin(p.y * 2.3 + 1.7 * sin(p.z * 1.3 + uSeed * 1.7)) +
          sin(p.z * 1.9 + 1.5 * sin(p.x * 1.6 + uSeed * 2.3))) / 3.0;
}

// The material's own surface at q (x along the string, |q| about 1):
// its colour, and how far the point is metal (yusr's silver dots).
vec4 surface(vec3 q) {
  float ax = clamp(q.x, -1.0, 1.0);
  float lat = asin(ax);
  vec3 c = mix(toLinear(uC0), toLinear(uC1), abs(lat) / 1.5708);
  float silver = 0.0;
  if (uKind < 0.5) {
    // Amber: clouds, lighter and darker.
    float n = waves(q * 2.6 + uSeed);
    float m = waves(q.zxy * 4.3 - uSeed);
    c = mix(c, toLinear(vec3(1.0, 0.84, 0.47)), 0.34 * smoothstep(0.1, 0.8, n));
    c = mix(c, toLinear(vec3(0.43, 0.18, 0.02)), 0.36 * smoothstep(0.1, 0.8, m));
  } else if (uKind < 1.5 || (uKind > 2.5 && uKind < 3.5)) {
    // Wood: rings round the string, a little wavy.
    float lon = atan(q.z, q.y);
    float w = ax + 0.035 * sin(lon * 2.0 + uSeed) + 0.02 * sin(lon * 5.0 + uSeed * 3.0);
    float g = noise1(w * 44.0) * 0.6 + noise1(w * 15.0 + 40.0) * 0.4 - 0.5;
    c = mix(c, c * 0.5, 0.5 * smoothstep(0.02, 0.3, -g));
    c = mix(c, c * 1.4 + 0.01, 0.3 * smoothstep(0.08, 0.36, g));
  } else if (uKind < 2.5) {
    // Pearl: faint rose and blue bands.
    float b = sin(ax * 9.0 + uSeed * 5.0) * 0.7 + 0.3 * waves(q * 3.0);
    c = mix(c, toLinear(vec3(1.0, 0.72, 0.76)), 0.16 * smoothstep(0.15, 0.9, b));
    c = mix(c, toLinear(vec3(0.62, 0.76, 1.0)), 0.18 * smoothstep(0.15, 0.9, -b));
  } else if (uKind < 4.5) {
    // Turquoise: dark veins that come and go.
    float f = waves(q * 3.1 + uSeed * 2.0) + 0.35 * waves(q.yzx * 7.0 + uSeed);
    float keep = smoothstep(-0.25, 0.45, waves(q.zxy * 1.9 - uSeed * 3.0));
    float line = (1.0 - smoothstep(0.015, 0.075, abs(f))) * keep;
    c *= 1.0 + 0.14 * waves(q.yzx * 2.2 + uSeed * 4.0);
    c = mix(c, toLinear(vec3(0.18, 0.125, 0.08)), 0.6 * line);
  } else if (uKind < 5.5) {
    // Yusr: small silver dots in a band round the middle.
    float lon = atan(q.z, q.y);
    float cols = 15.0;
    float rowH = 0.3;
    vec2 uv = vec2((lon / 6.28318 + 0.5) * cols, lat / rowH + 2.0);
    vec2 cell = floor(uv);
    float h1 = hash1(cell.x * 7.0 + cell.y * 31.0);
    float h2 = hash1(cell.x * 13.0 + cell.y * 5.0 + 9.0);
    vec2 d = (fract(uv) - 0.5 - (vec2(h1, h2) - 0.5) * 0.5) *
        vec2(6.28318 / cols * cos(lat), rowH);
    silver = (1.0 - smoothstep(0.026, 0.05, length(d))) *
        step(0.45, fract(h1 * 7.3)) * step(abs(lat), 0.75);
    c = mix(c, toLinear(vec3(0.84, 0.86, 0.88)), silver);
  }
  return vec4(c, silver);
}

float panel(vec3 r, vec3 c, vec3 ax, vec3 ay, vec2 ext, float soft) {
  float d = dot(r, c);
  vec2 uv = abs(vec2(dot(r, ax), dot(r, ay)) / max(d, 0.001));
  vec2 m = vec2(1.0) - smoothstep(ext - soft, ext + soft, uv);
  return m.x * m.y * step(0.0, d);
}

// The studio the pieces reflect (world space): a sky and three panels.
vec3 env(vec3 r, float rough) {
  float k = r.y * 0.5 + 0.5;
  vec3 c = vec3(0.1 + 0.42 * k, 0.09 + 0.4 * k, 0.08 + 0.38 * k);
  float soft = 0.03 + rough * 0.55;
  c += vec3(7.0, 7.0, 6.6) * panel(r, vec3(-0.5121, 0.7682, 0.3841),
      vec3(0.6, 0.0, 0.8), vec3(0.6146, 0.6402, -0.4609), vec2(0.256, 0.192), soft);
  c += vec3(3.5, 3.5, 3.3) * panel(r, vec3(0.8571, 0.4286, -0.2857),
      vec3(-0.3162, 0.0, -0.9487), vec3(-0.4066, 0.9035, 0.1355), vec2(0.143, 0.357), soft);
  c += vec3(2.2, 2.2, 2.07) * panel(r, vec3(0.0, 0.2651, 0.9642),
      vec3(1.0, 0.0, 0.0), vec3(0.0, 0.9642, -0.2651), vec2(0.3616, 0.0844), soft);
  return c;
}

float lobe(float ndh, float rough) {
  float e = 8.0 / (rough * rough + 0.006);
  return pow(ndh, e) * (e + 8.0) / 25.13;
}

vec3 shade(vec3 n, vec3 q) {
  vec4 s = surface(q);
  vec3 alb = s.rgb;
  float metal = max(step(5.5, uKind), s.a);
  vec3 l = normalize(uLight);
  vec3 up = vec3(0.0, uCam.y, uCam.x);
  vec3 v = vec3(0.0, 0.0, 1.0);
  float ndl = max(dot(n, l), 0.0);

  // Darker where it faces its neighbours and the surface.
  float nb = (1.0 - 0.7 * pow(max(dot(n, uN1), 0.0), 3.0)) *
      (1.0 - 0.7 * pow(max(dot(n, uN2), 0.0), 3.0));
  float down = max(dot(n, -up), 0.0);
  float occ = nb * (1.0 - 0.6 * uGround * down * down);

  float hemi = dot(n, up) * 0.5 + 0.5;
  vec3 amb = mix(vec3(0.24, 0.22, 0.2), vec3(0.62, 0.6, 0.58), hemi);
  vec3 sun = vec3(1.0, 0.945, 0.86) * 1.35;
  vec3 c = alb * (amb * occ + sun * ndl * nb) * (1.0 - metal);

  // Light through the bead, leaving on the side away from the light.
  float through = pow(max(dot(-n, l), 0.0), 1.5) * 0.6 + 0.35 * (1.0 - ndl) * n.z;
  c += alb * uScatter * through * 0.9 * (1.0 - metal);
  c += toLinear(uEmit) * (0.35 + alb) * (1.0 - metal);

  vec3 r = 2.0 * n.z * n - v;
  vec3 rw = vec3(r.x, r.y * uCam.y + r.z * uCam.x, -r.y * uCam.x + r.z * uCam.y);
  float fres = pow(1.0 - max(n.z, 0.0), 5.0);
  float ndh = max(dot(n, normalize(l + v)), 0.0);
  float lit = smoothstep(0.0, 0.2, ndl) * nb;

  // The clear coat: the key light's highlight and the studio.
  vec3 coat = env(rw, uCoatRough) * (0.04 + 0.96 * fres) * uEnv * occ +
      sun * 0.04 * lobe(ndh, uCoatRough) * lit;
  // Under it, the material's own broader shine; brushed metal mirrors the
  // studio and scatters the rest.
  vec3 base = sun * 0.04 * lobe(ndh, uRough) * lit * (1.0 - 0.6 * uCoat) +
      env(rw, uRough + 0.25) * (0.04 + 0.5 * fres) * uEnv * occ;
  vec3 mirror = alb * (env(rw, uRough) * uEnv * 0.55 * occ +
      (amb * occ + sun * ndl * nb) * 0.6 + sun * lobe(ndh, uRough) * lit * 0.25);
  c += coat * uCoat * (1.0 - metal) + mix(base, mirror, metal);
  c += alb * pow(1.0 - max(n.z, 0.0), 3.0) * 0.1 * hemi * (1.0 - metal);

  // Filmic tone curve, then to display space.
  c = clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), 0.0, 1.0);
  return pow(c, vec3(0.4545));
}

// A turned piece's radius (in bead radii) y along its axis.
float profile(float y) {
  float r;
  if (uShape < 1.5) {
    float a = (y - 1.2) / 1.2;
    float b = clamp((y - 1.2) / 1.8, 0.0, 1.0);
    r = y < 1.2 ? 1.06 * sqrt(max(1.0 - a * a, 0.0))
                : 1.06 * (1.0 - 0.66 * pow(b, 1.6));
  } else {
    r = (0.2 + 0.42 * pow(clamp(y / 1.3, 0.0, 1.0), 1.8)) *
        sqrt(clamp((1.3 - y) / 0.14, 0.0, 1.0));
  }
  return r;
}

void main() {
  vec2 fc = FlutterFragCoord().xy;
  vec3 A = normalize(uAxis);
  vec3 n;
  vec3 q;
  float alpha;
  if (uShape < 0.5) {
    vec2 p = (fc - uA) / uRadius;
    p.y = -p.y;
    // Stretch space along the axis until the ellipsoid is a unit sphere.
    float k = 1.0 / uRatio - 1.0;
    vec3 o = vec3(p, 0.0);
    vec3 os = o + k * dot(o, A) * A;
    vec3 ds = vec3(0.0, 0.0, 1.0) + k * A.z * A;
    float a2 = dot(ds, ds);
    float b = dot(os, ds);
    float disc = b * b - a2 * (dot(os, os) - 1.0);
    alpha = clamp(disc / a2 * 0.6 * uRadius, 0.0, 1.0);
    vec3 x = os + (sqrt(max(disc, 0.0)) - b) / a2 * ds;
    n = normalize(x + k * dot(x, A) * A);
    vec3 U = normalize(cross(A, vec3(0.0, 0.0, 1.0)));
    q = vec3(dot(x, A), dot(x, U), dot(x, cross(A, U)));
  } else if (uShape > 2.5) {
    // A short cylinder: its side, or the end that faces the eye.
    vec2 p = (fc - uA) / uRadius;
    p.y = -p.y;
    vec3 o = vec3(p, 0.0);
    float oa = dot(o, A);
    float da = abs(A.z) < 0.001 ? 0.001 : A.z;
    vec3 op = o - oa * A;
    vec3 dp = vec3(0.0, 0.0, 1.0) - da * A;
    float a2 = max(dot(dp, dp), 0.0001);
    float b = dot(op, dp);
    float disc = b * b - a2 * (dot(op, op) - 1.0);
    float tS = (sqrt(max(disc, 0.0)) - b) / a2;
    float alongS = oa + tS * da;
    float aS = clamp(disc / a2 * 0.6 * uRadius, 0.0, 1.0) *
        clamp((uRatio - abs(alongS)) * uRadius + 0.5, 0.0, 1.0);
    float side = sign(da);
    float tC = (side * uRatio - oa) / da;
    vec3 xc = op + tC * dp;
    float aC = clamp((1.0 - length(xc)) * uRadius + 0.5, 0.0, 1.0);
    bool cap = aC > 0.0 && (tC > tS || aS <= 0.0);
    alpha = cap ? aC : aS;
    n = cap ? side * A : normalize(op + tS * dp);
    q = cap ? vec3(1.0, 0.0, 0.0) : vec3(0.0, n.x, n.z);
  } else {
    vec2 ab = uB - uA;
    float len = max(length(ab), 0.001);
    vec2 dir = ab / len;
    vec2 perp = vec2(-dir.y, dir.x);
    float s = dot(fc - uA, dir) / len;
    float w = dot(fc - uA, perp) / uRadius;
    float span = uShape < 1.5 ? 3.0 : 1.3;
    float y = clamp(s, 0.0, 1.0) * span;
    float R = profile(y);
    float slope = (profile(y + 0.02) - profile(y - 0.02)) / 0.04;
    alpha = clamp((R - abs(w)) * uRadius, 0.0, 1.0) *
        clamp(s * len + 0.5, 0.0, 1.0) * clamp((1.0 - s) * len + 0.5, 0.0, 1.0);
    float cs = clamp(w / max(R, 0.001), -1.0, 1.0);
    float sn = sqrt(1.0 - cs * cs);
    vec3 u = vec3(perp.x, -perp.y, 0.0);
    vec3 wv = cross(u, A);
    wv = wv.z < 0.0 ? -wv : wv;
    n = normalize(cs * u + sn * wv - slope * A);
    q = normalize(vec3(s * 2.0 - 1.0, cs, sn));
  }
  if (alpha <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  fragColor = vec4(shade(n, q) * alpha, alpha);
}
