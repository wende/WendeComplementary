// Generated Displacement: derives a heightfield from albedo luminance and ray-marches
// it for fake parallax. Quality is bound by the (false) assumption that darker albedo
// pixels lie deeper than brighter ones; works on stone/brick, looks wrong on textures
// with painted detail (text, baked AO, color-only variation).

#include "/lib/util/dFdxdFdy.glsl"

const float generatedDisplacementThreshold = 0.08;
const float generatedDisplacementGradientStrength = 0.0;
const float generatedDisplacementGradientMin = 0.04;
const float generatedDisplacementGradientMax = 0.18;

vec4 dispCornerLuma = vec4(0.0);
float dispCornerAvg = 0.0;
float dispBorderAvg = 0.0;
float dispGradientAmount = 0.0;

vec2 GetDispSpriteSize() {
    return max(absMidCoordPos * 2.0, 1.0 / vec2(atlasSize));
}

vec2 GetDispSpriteOrigin() {
    return midCoord - GetDispSpriteSize() * 0.5;
}

vec2 AtlasToSpriteLocal(vec2 atlasCoord) {
    return (atlasCoord - GetDispSpriteOrigin()) / GetDispSpriteSize();
}

vec2 GetDispLocalInset() {
    return 0.5 / (GetDispSpriteSize() * vec2(atlasSize));
}

vec2 SpriteToAtlasNoWrap(vec2 lc) {
    return clamp(lc, GetDispLocalInset(), 1.0 - GetDispLocalInset()) * GetDispSpriteSize()
         + GetDispSpriteOrigin();
}

vec2 SpriteToAtlasHeight(vec2 lc) {
    vec2 spriteSize = GetDispSpriteSize();
    vec2 inset = GetDispLocalInset();
    return clamp(lc, inset, 1.0 - inset) * spriteSize + GetDispSpriteOrigin();
}

// Half-texel inset prevents bilinear/mipmap filtering from pulling pixels of the
// adjacent atlas sprite when the displaced coord lands at a sprite edge.
vec2 SpriteToAtlasClamped(vec2 lc) {
    vec2 spriteSize = GetDispSpriteSize();
    vec2 inset = GetDispLocalInset();
    return clamp(lc, inset, 1.0 - inset) * spriteSize + GetDispSpriteOrigin();
}

float ReadDispLuminance(vec2 atlasCoord) {
    vec3 s = textureGrad(tex, atlasCoord, dcdx, dcdy).rgb;
    return dot(s, vec3(0.2125, 0.7154, 0.0721));
}

void InitDispReference() {
    dispCornerLuma.x = ReadDispLuminance(SpriteToAtlasNoWrap(vec2(0.0, 0.0)));
    dispCornerLuma.y = ReadDispLuminance(SpriteToAtlasNoWrap(vec2(1.0, 0.0)));
    dispCornerLuma.z = ReadDispLuminance(SpriteToAtlasNoWrap(vec2(0.0, 1.0)));
    dispCornerLuma.w = ReadDispLuminance(SpriteToAtlasNoWrap(vec2(1.0, 1.0)));
    dispCornerAvg = dot(dispCornerLuma, vec4(0.25));

    float edgeMidAvg = 0.25 * (
        ReadDispLuminance(SpriteToAtlasNoWrap(vec2(0.0, 0.5))) +
        ReadDispLuminance(SpriteToAtlasNoWrap(vec2(1.0, 0.5))) +
        ReadDispLuminance(SpriteToAtlasNoWrap(vec2(0.5, 0.0))) +
        ReadDispLuminance(SpriteToAtlasNoWrap(vec2(0.5, 1.0)))
    );
    dispBorderAvg = mix(dispCornerAvg, edgeMidAvg, 0.5);

    float minCorner = min(min(dispCornerLuma.x, dispCornerLuma.y), min(dispCornerLuma.z, dispCornerLuma.w));
    float maxCorner = max(max(dispCornerLuma.x, dispCornerLuma.y), max(dispCornerLuma.z, dispCornerLuma.w));
    dispGradientAmount = generatedDisplacementGradientStrength
                       * smoothstep(generatedDisplacementGradientMin,
                                    generatedDisplacementGradientMax,
                                    maxCorner - minCorner);
}

float CompensateDispLuminance(float luminance, vec2 localCoord) {
    localCoord = clamp(localCoord, GetDispLocalInset(), 1.0 - GetDispLocalInset());
    float cornerPlane = mix(mix(dispCornerLuma.x, dispCornerLuma.y, localCoord.x),
                            mix(dispCornerLuma.z, dispCornerLuma.w, localCoord.x),
                            localCoord.y);
    return clamp(luminance - (cornerPlane - dispCornerAvg) * dispGradientAmount, 0.0, 1.0);
}

float ReadDispCompensatedLocalLuminance(vec2 localCoord) {
    localCoord = clamp(localCoord, GetDispLocalInset(), 1.0 - GetDispLocalInset());
    return CompensateDispLuminance(ReadDispLuminance(SpriteToAtlasHeight(localCoord)), localCoord);
}

float ReadDispCompensatedLuminance(vec2 lc) {
    return ReadDispCompensatedLocalLuminance(lc);
}

float ReadDispCompensatedEdgeLuminance(vec2 lc) {
    return dispBorderAvg;
}

float GetDispEdgeMask(vec2 lc) {
    vec2 inset = GetDispLocalInset();
    vec2 localCoord = clamp(lc, inset, 1.0 - inset);
    vec2 spriteTexels = GetDispSpriteSize() * vec2(atlasSize);
    vec2 edgeDistance = min(localCoord - inset, 1.0 - inset - localCoord) * spriteTexels;
    return smoothstep(0.0, 1.5, min(edgeDistance.x, edgeDistance.y));
}

float CurveDispSignal(float displacement) {
    float curve = float(GENERATED_DISPLACEMENT_CURVE) * 0.01;
    if (curve > 0.0) {
        displacement = log2(1.0 + curve * displacement) / log2(1.0 + curve);
    }
    return max(displacement - generatedDisplacementThreshold, 0.0)
         / max(1.0 - generatedDisplacementThreshold, 0.0001);
}

float ReadDispHeight(vec2 lc) {
    float luminance = ReadDispCompensatedLuminance(lc);
    float baseline = ReadDispCompensatedEdgeLuminance(lc);
    float displacement = max(baseline - luminance, 0.0) / max(baseline, 0.0001);
    displacement = CurveDispSignal(displacement);
    displacement *= GetDispEdgeMask(lc);
    return 1.0 - displacement;
}

vec2 GetGeneratedDisplacementCoord(float fade, float dither, vec3 dispViewVector) {
    vec2 localCoord = AtlasToSpriteLocal(texCoord);
    vec2 origAtlas = SpriteToAtlasClamped(localCoord);

    if (dispViewVector.z >= 0.0 || fade >= 1.0) return origAtlas;
    InitDispReference();

    float quality = float(GENERATED_DISPLACEMENT_QUALITY);
    float invQ = 1.0 / quality;
    float viewZ = max(-dispViewVector.z, 0.12);
    float grazingFade = 1.0 - smoothstep(0.12, 0.35, viewZ);
    fade = max(fade, grazingFade);
    if (fade >= 1.0) return origAtlas;

    vec2 interval = dispViewVector.xy * 0.25 * (1.0 - fade) * GENERATED_DISPLACEMENT_DEPTH
                  / (viewZ * quality);

    float i = dither;
    float h = ReadDispHeight(localCoord);

    for (int step = 0; step < int(GENERATED_DISPLACEMENT_QUALITY); step++) {
        if (h > 1.0 - i * invQ) break;
        i += 1.0;
        if (i >= quality) break;
        h = ReadDispHeight(localCoord + i * interval);
    }

    float pI = max(i - 1.0, 0.0);
    return SpriteToAtlasClamped(localCoord + pI * interval);
}
