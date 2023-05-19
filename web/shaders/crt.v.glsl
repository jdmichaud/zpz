#version 300 es
in vec2 pos;
out mediump vec2 screencoord;
uniform mediump float width, height;
uniform mediump vec2 texsize;

void main() {
  gl_Position = vec4(pos, 0.0, 1.0);
  screencoord = pos;
}