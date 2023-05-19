#version 300 es

#define M_PI 3.14159265358979323846

precision mediump sampler2D;

uniform sampler2D uImageSampler;

uniform mediump float width, height;
uniform mediump vec2 texsize;
in mediump vec2 screencoord;

out mediump vec4 fragColor;

void main() {
  mediump float fishbowl_factor = length(screencoord);
  mediump vec2 monitorcoord = (screencoord + screencoord * fishbowl_factor * 0.025);

  // Screen space to texture space.
  // TODO:
  // If we wanted to apply the fishbowl effect on the entire screen and not only
  // on the border (vignetting) we would use monitorcoord to compute the texturecoord.
  // mediump vec2 texturecoord = monitorcoord *
  // However, the fishbowl would be applied to a low resolution texture which generate artefacts.
  // We should apply that effect at the screen space level to get a better resolution.
  mediump vec2 texturecoord = screencoord *
    vec2(0.5 * width / texsize.x, -0.5 * height / texsize.y) +
    vec2(0.5 * width / texsize.x,  0.5 * height / texsize.y);

  // We give a nice blurry gradient effect to the border here
  // pow(abs(monitorcoord.x), 100.0) will be 0.0 except very close to 1 (the border)
  // then mask will be 0.0 unless very close to the border.
  mediump float maskx = 1.0 - pow(abs(monitorcoord.x), 200.0);
  mediump float masky = 1.0 - pow(abs(monitorcoord.y), 200.0);
  // The multiplication will give the nice vignetting effect.
  mediump float mask = clamp(maskx * masky, 0.0, 1.0) * sign(maskx);

  mediump vec4 src = texture(uImageSampler, texturecoord);
  fragColor = mask * src;
}