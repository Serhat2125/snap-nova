#version 460 core
// ═══════════════════════════════════════════════════════════════════════════
//  Dünya küresi — eşdikdörtgen (equirectangular) NASA dokusunu ortografik
//  projeksiyonla küreye sarar.
//
//  Uniform'lar:
//    uLat0/uLon0 : bakış merkezi (radyan). Dünya kartı: uLat0=0,
//                  uLon0=dönüş açısı (tam tur). Ülke kartı: ülkenin merkezi.
//    uZoom       : 1 = tam küre; >1 = ülkeye yakınlaşmış görünüm.
//  Dart tarafı bayrak/sınır çizimlerini AYNI projeksiyonla üstüne yapar.
// ═══════════════════════════════════════════════════════════════════════════
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;   // çizim alanı (px)
uniform float uLat0;  // merkez enlem (radyan)
uniform float uLon0;  // merkez boylam / dönüş (radyan)
uniform float uZoom;  // yakınlaşma
uniform sampler2D uTex;

out vec4 fragColor;

const float PI = 3.14159265358979;

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 c = uSize * 0.5;
  float R = min(uSize.x, uSize.y) * 0.5 - 2.0;
  vec2 p = (frag - c) / (R * uZoom);
  float rr = dot(p, p);
  if (rr > 1.08) { fragColor = vec4(0.0); return; }
  if (rr > 1.0) {
    // İnce atmosfer halesi — kürenin hemen dışında maviye kaybolur.
    float glow = 1.0 - smoothstep(1.0, 1.08, sqrt(rr));
    fragColor = vec4(vec3(0.30, 0.58, 0.95) * glow * 0.55, glow * 0.55);
    return;
  }
  float z = sqrt(1.0 - rr);
  float x = p.x;
  float y = -p.y; // ekran y aşağı → kuzey yukarı
  // Ters ortografik projeksiyon (merkez uLat0/uLon0):
  float sinLat = clamp(z * sin(uLat0) + y * cos(uLat0), -1.0, 1.0);
  float lat = asin(sinLat);
  float lon = uLon0 + atan(x, z * cos(uLat0) - y * sin(uLat0));
  float u = fract(lon / (2.0 * PI) + 0.5);
  float v = 0.5 - lat / PI;
  vec3 col = texture(uTex, vec2(u, v)).rgb;
  // Küresel aydınlatma: merkez parlak, kenarlara doğru koyulaşır (limb).
  float shade = 0.42 + 0.58 * z;
  // Kenarda hafif atmosfer mavisi.
  float rim = smoothstep(0.72, 1.0, sqrt(rr));
  col = col * shade + vec3(0.25, 0.55, 0.95) * rim * 0.30;
  fragColor = vec4(col, 1.0);
}
