smoothnessG = pow1_5(color.g) * 0.55; // pow1_5 already in commonFunctions: x - x*(1-x)^2 (~4 muls vs full pow)
smoothnessG = smoothnessG;
smoothnessD = smoothnessG;

materialMask = OSIEBCA; // Intense Fresnel