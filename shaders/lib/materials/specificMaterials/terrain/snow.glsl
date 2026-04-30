// pow(x, 64) -> 6 muls
float sg2 = color.g * color.g; float sg4 = sg2 * sg2; float sg8 = sg4 * sg4; float sg16 = sg8 * sg8; float sg32 = sg16 * sg16;
smoothnessG = (1.0 - (sg32 * sg32) * 0.3) * 0.4;
highlightMult = 2.0;

smoothnessD = smoothnessG;

#ifdef GBUFFERS_TERRAIN
    DoBrightBlockTweaks(color.rgb, 0.5, shadowMult, highlightMult);
#endif

#if RAIN_PUDDLES >= 1
    noPuddles = 1.0;
#endif