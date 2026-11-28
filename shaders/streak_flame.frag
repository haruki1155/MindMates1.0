#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform float uLit;
uniform float uIntensity;
uniform vec3 uOuter;
uniform vec3 uMid;
uniform vec3 uCore;

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
    mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
    u.y
  );
}

float fbm(vec2 p) {
  float value = 0.0;
  float amplitude = 0.5;
  mat2 rot = mat2(0.8, 0.6, -0.6, 0.8);
  for (int i = 0; i < 4; i++) {
    value += amplitude * noise(p);
    p = rot * p * 2.04 + vec2(1.7, 9.2);
    amplitude *= 0.5;
  }
  return value;
}

void main() {
  vec2 safeSize = max(uSize, vec2(1.0));
  vec2 uv = FlutterFragCoord().xy / safeSize;
  // FlutterFragCoord y increases downward; flip so 0 is the base of the flame.
  float vy = 1.0 - uv.y;
  vec2 p = vec2((uv.x - 0.5) * 2.1, vy);
  float y = clamp((vy - 0.08) / 0.86, 0.0, 1.0);
  float safeY = max(y, 0.0001);

  if (uLit < 0.5) {
    float width = mix(0.42, 0.0, pow(safeY, 0.72)) * smoothstep(0.0, 0.16, y);
    float baseRound = 1.0 - smoothstep(0.0, 0.18, y);
    float d = width - abs(p.x) - baseRound * 0.12 * p.x * p.x;
    float a = smoothstep(0.0, 0.06, d) *
        smoothstep(0.0, 0.08, y) *
        (1.0 - smoothstep(0.92, 1.0, y));
    vec3 col = mix(uOuter, uCore, smoothstep(0.05, 0.35, d) * (1.0 - y * 0.6));
    float alpha = clamp(a * 0.78, 0.0, 1.0);
    fragColor = vec4(col * alpha, alpha);
    return;
  }

  float t = uTime;
  float energy = clamp(uIntensity, 0.5, 1.4);

  // Smooth upward-scrolling turbulent fire physics.
  float sway = (fbm(vec2(y * 2.0 - t * 1.9, t * 0.3)) - 0.5) *
      (0.46 * y + 0.06);
  float curl = sin(y * 6.5 - t * 4.4) * 0.082 * y;
  float px = p.x + sway + curl;

  float n1 = fbm(vec2(px * 2.9, y * 2.5 - t * 2.6));
  float n2 = fbm(vec2(px * 5.8 + 3.1, y * 4.6 - t * 4.2));
  float turb = (n1 * 0.68 + n2 * 0.32) - 0.44;

  float env = mix(0.49, 0.01, pow(safeY, 0.68)) * smoothstep(0.0, 0.15, y);
  float sideL = exp(-pow((px + 0.24 - 0.06 * sin(t * 3.1 + y * 5.0)) * 4.8, 2.0)) *
      smoothstep(0.58, 0.16, y) *
      smoothstep(0.06, 0.22, y) *
      0.14;
  float sideR = exp(-pow((px - 0.22 + 0.05 * cos(t * 3.6 + y * 4.0)) * 5.0, 2.0)) *
      smoothstep(0.52, 0.16, y) *
      smoothstep(0.06, 0.22, y) *
      0.12;

  float shape = env + sideL + sideR - abs(px) +
      turb * (0.24 + 0.36 * y) * smoothstep(0.02, 0.24, y);
  float verticalFade = smoothstep(0.0, 0.06, y) * (1.0 - smoothstep(0.84, 1.0, y));
  float heat = clamp(shape * (2.65 + 0.35 * energy), 0.0, 1.0) * verticalFade;

  // Volumetric 3-stop flame gradient (outer -> mid -> hot inner core).
  vec3 col = mix(uOuter, uMid, smoothstep(0.10, 0.52, heat));
  float coreHeat = smoothstep(0.36, 0.86, heat) * smoothstep(0.76, 0.12, y);
  col = mix(col, uCore, clamp(coreHeat * (0.85 + 0.15 * energy), 0.0, 1.0));

  float flameAlpha = smoothstep(0.02, 0.14, shape) * verticalFade;

  // Soft pulsing ambient radial glow behind the flame.
  float glowDist = length(vec2(p.x * 0.9, (y - 0.36) * 1.15));
  float glow = exp(-glowDist * glowDist * 4.2) *
      (0.24 + 0.06 * sin(t * 5.0)) *
      energy;

  // Rising glowing ember sparks (4th spark activates on milestones).
  float sparkA = 0.0;
  float milestoneBoost = smoothstep(1.05, 1.22, energy);
  for (int i = 0; i < 4; i++) {
    float fi = float(i);
    float weight = i == 3 ? milestoneBoost : smoothstep(0.55, 0.95, energy);
    float prog = fract(t * (0.46 + fi * 0.12) + fi * 0.29);
    float sx = sin(prog * 7.5 + fi * 2.4 + t) * (0.20 + fi * 0.07);
    float sy = 0.28 + prog * 0.68;
    float sd = length(vec2(p.x - sx, y - sy));
    float radius = mix(0.042, 0.014, prog);
    sparkA += smoothstep(radius, 0.0, sd) * sin(prog * 3.14159) * weight;
  }

  vec3 finalCol = mix(uMid, col, clamp(flameAlpha * 1.3, 0.0, 1.0));
  finalCol = mix(finalCol, uCore, clamp(sparkA, 0.0, 1.0));
  float alpha = clamp(max(max(flameAlpha, glow), sparkA), 0.0, 1.0);
  // Flutter RuntimeEffect expects premultiplied alpha output.
  fragColor = vec4(finalCol * alpha, alpha);
}
