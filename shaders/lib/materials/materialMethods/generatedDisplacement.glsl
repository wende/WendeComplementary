// Generated Displacement: derives a heightfield from albedo luminance and ray-marches
// it for fake parallax. Quality is bound by the (false) assumption that darker albedo
// pixels lie deeper than brighter ones; works on stone/brick, looks wrong on textures
// with painted detail (text, baked AO, color-only variation).

#include "/lib/util/dFdxdFdy.glsl"

vec2 vTexCoord = signMidCoordPos * 0.5 + 0.5;

float ReadDispHeight(vec2 atlasCoord) {
    vec3 s = textureGrad(tex, atlasCoord, dcdx, dcdy).rgb;
    return dot(s, vec3(0.2125, 0.7154, 0.0721));
}

// Half-texel inset prevents bilinear/mipmap filtering from pulling pixels of the
// adjacent atlas sprite when the displaced coord lands at a sprite edge.
vec2 SpriteToAtlasClamped(vec2 lc) {
    vec2 inset = 0.5 / (vTexCoordAM.pq * vec2(atlasSize));
    return clamp(fract(lc), inset, 1.0 - inset) * vTexCoordAM.pq + vTexCoordAM.st;
}

vec2 GetGeneratedDisplacementCoord(float fade, float dither) {
    vec2 origAtlas = SpriteToAtlasClamped(vTexCoord.st);

    if (viewVector.z >= 0.0 || fade >= 1.0) return origAtlas;

    float quality = float(GENERATED_DISPLACEMENT_QUALITY);
    float invQ = 1.0 / quality;

    vec2 interval = viewVector.xy * 0.25 * (1.0 - fade) * GENERATED_DISPLACEMENT_DEPTH
                  / (-viewVector.z * quality);

    float i = dither;
    float h = ReadDispHeight(origAtlas);

    for (int step = 0; step < int(GENERATED_DISPLACEMENT_QUALITY); step++) {
        if (h > 1.0 - i * invQ) break;
        i += 1.0;
        if (i >= quality) break;
        h = ReadDispHeight(SpriteToAtlasClamped(vTexCoord.st + i * interval));
    }

    float pI = max(i - 1.0, 0.0);
    return SpriteToAtlasClamped(vTexCoord.st + pI * interval);
}
