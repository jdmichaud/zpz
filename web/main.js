// https://github.com/daneelsan/zig-wasm-logger
// https://github.com/hexops/mach/blob/main/src/platform/wasm.zig
// https://discord.com/channels/605571803288698900/605572581046747136/1009710089508245567 <- discussion on zig-help about WASM/libc/WASI

const textDecoder = new TextDecoder();

// From a position in a buffer, assume a null terminated c-string and return
// a javascript string.
function toStr(charArray, ptr, limit=255) {
  let end = ptr;
  while (charArray[end++] && (end - ptr) < limit);
  return textDecoder.decode(new Uint8Array(charArray.buffer, ptr, end - ptr - 1));
}

async function setProgram(canvas, vertexShaderPath, fragmentShaderPath) {
  // Retrieve the shader code
  const vertexShaderSource = await (await fetch(vertexShaderPath)).text();
  const fragmentShaderSource = await (await fetch(fragmentShaderPath)).text();
  // Get the WebGL context from the canvas
  const gl = canvas.getContext('webgl2');
  if (gl === null) throw new Error('null gl');
  // Set clear color to black, fully opaque
  gl.clearColor(0.0, 0.0, 0.0, 1.0);
  gl.clear(gl.COLOR_BUFFER_BIT);
  // Load the shaders and compile them
  const vertexShader = gl.createShader(gl.VERTEX_SHADER);
  if (vertexShader === null) throw new Error('null vertexShader');
  gl.shaderSource(vertexShader, vertexShaderSource);
  gl.compileShader(vertexShader);
  const fragmentShader = gl.createShader(gl.FRAGMENT_SHADER);
  if (fragmentShader === null) throw new Error('null fragmentShader');
  gl.shaderSource(fragmentShader, fragmentShaderSource);
  gl.compileShader(fragmentShader);
  // Create the shader program
  const shaderProgram = gl.createProgram();
  if (shaderProgram === null) throw new Error('null shaderProgram');
  gl.attachShader(shaderProgram, vertexShader);
  gl.attachShader(shaderProgram, fragmentShader);
  gl.linkProgram(shaderProgram);
  gl.useProgram(shaderProgram);
  // Create the image plane
  const positionBuffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, positionBuffer);
  const positions = [ -1, -1, 1, -1, -1,  1, -1,  1, 1, -1, 1,  1 ];
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(positions), gl.STATIC_DRAW);
  // Create bindings
  const vertexPosition = gl.getAttribLocation(shaderProgram, 'pos');
  // Prepare the vertex position to be loaded into the GPU
  gl.vertexAttribPointer(vertexPosition, 2, gl.FLOAT, false, 0, 0);
  gl.enableVertexAttribArray(vertexPosition);
  // Create a texture to load the image to
  const texture = gl.createTexture();
  if (texture === null) throw new Error('null texture');

  // Set the size
  const uWidth = gl.getUniformLocation(shaderProgram, "width");
  const uHeight = gl.getUniformLocation(shaderProgram, "height");
  gl.uniform1f(uWidth, canvas.width);
  gl.uniform1f(uHeight, canvas.height);

  return { canvas, gl, texture, shaderProgram };
}

function loadImage(gl, shaderProgram, texture, textureCoordinatesName, samplerName,
  textureId, image) {
  gl.activeTexture(textureId);
  gl.bindTexture(gl.TEXTURE_2D, texture);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, image.width, image.height, 0, gl.RGBA,
    gl.UNSIGNED_BYTE, image);
  const sampler = gl.getUniformLocation(shaderProgram, samplerName);
  gl.uniform1i(sampler, textureId - gl.TEXTURE0);

  const textureCoordBuffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, textureCoordBuffer);
  // // The texture coordinates must match the order of the vertex coordinates.
  // // Texture coordinates origin [0, 0] is the bottom right and goes up and right to [1, 1]
  // const textureCoordinates = [ 0.0, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0.0 ];
  // gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(textureCoordinates), gl.STATIC_DRAW);
  // const textureCoord = gl.getAttribLocation(shaderProgram, textureCoordinatesName);
  // gl.vertexAttribPointer(textureCoord, 2, gl.FLOAT, false, 0, 0);
  // gl.enableVertexAttribArray(textureCoord);

  const uTexsize = gl.getUniformLocation(shaderProgram, "texsize");
  gl.uniform2f(uTexsize, image.width, image.height);
}

async function main() {
  // By default, memory is 1 page (64K). We'll need a little more
  const memory = new WebAssembly.Memory({ initial: 1000 });
  console.log(memory.buffer.byteLength / 1024, 'KB allocated');

  const canvas = document.getElementsByTagName('canvas')[0];
  const { gl, texture, shaderProgram } = await setProgram(canvas, 'shaders/crt.v.glsl', 'shaders/crt.f.glsl');
  // const gl = canvas.getContext('2d');
  // The canvas we are going to dump the pixel from the emulator to
  const temporaryCanvas = document.createElement('canvas');
  // chips emulator work with a 768x544 screen
  temporaryCanvas.width = 768; temporaryCanvas.height = 544;
  const temporaryCtx = temporaryCanvas.getContext('2d');
  const imageData = new ImageData(temporaryCanvas.width, temporaryCanvas.height);
  // Position in memory of the next available free byte.
  // malloc will move that position.
  let heapPos = 1; // 0 is the NULL pointer. Not a proper malloc return value...
  // log string buffer
  let str = '';
  // These are the functions for the WASM environment available for the zig code
  // to communicate with the JS environment.
  const env = {
    memory,
    // Display the pixelBuffer in the canvas
    display: (pixelBuffer) => {
      const pixelArray = new Uint32Array(memory.buffer, pixelBuffer);
      const { data, width, height } = imageData;
      const canvasPixel = new Uint32Array(data.buffer);
      // CPC pixel sizes differ from PC pixel sizes. We apply a correction factor in height.
      let j = 0;
      while (j < height) {
        let i = 0;
        while (i < width) {
          // j >> 1 because we print two lines on the PC screen for one CPC line.
          canvasPixel[i + j * width] = pixelArray[i + (j >> 1) * width];
          i += 1;
        }
        j += 1;
      }
      temporaryCtx.putImageData(imageData, 0, 0);
      // gl.drawImage(temporaryCanvas, 0, 0, canvas.width, canvas.height);
      // Load the image from the emulator into a texture
      loadImage(gl, shaderProgram, texture, 'aTextureCoord', 'uImageSampler', gl.TEXTURE1, temporaryCanvas);
      // Draw the scene
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
    },
    // Add a log string to the buffer
    addString: (offset, size) => {
      str = str + textDecoder.decode(new Uint8Array(memory.buffer, offset, size));
    },
    // Flush the log string buffer with console.log
    printString: () => {
      console.log(str);
      str = '';
    },
    // libc memset reimplementation
    memset: (ptr, value, size) => {
      const mem = new Uint8Array(memory.buffer);
      mem.fill(value, ptr, ptr + size);
      return ptr;
    },
    // libc memcpy reimplementation
    memcpy: (dest, source, n) => {
      const mem = new Uint8Array(memory.buffer);
      mem.copyWithin(dest, source, source + n);
      return dest;
    },
    // libc memcmp reimplmentation
    memcmp: (s1, s2, n) => {
      const charArray = new Uint8Array(memory.buffer);
      for (let i = 0; i < n; i++) {
        if (charArray[s1] !== charArray[s2]) {
          return charArray[s1] - charArray[s2];
        }
      }
      return 0;
    },
    // libc malloc reimplementation
    // This dumb allocator just churn through the memory and does not keep
    // track of freed memory. Will work for a while...
    malloc: size => {
      const ptr = heapPos;
      heapPos += size;
      return ptr;
    },
    // libc free reimplementation
    free: ptr => {
      // Nothing gets freed
    },
    __assert_fail_js: (assertion, file, line, fun) => {
      const charArray = new Uint8Array(memory.buffer);
      console.log(`${toStr(charArray, file)}(${line}): ${toStr(charArray, assertion)} in ${toStr(charArray, fun)}`);
    },
  }
  // Load the wasm code
  const wasm = await WebAssembly.instantiateStreaming(fetch("zpz6128.wasm"), { env });
  // Extract the API
  const { new_emulator, input_char, keydown, keyup, tick, insert_disk } = wasm.instance.exports;
  // Create the emulator
  const emulator = new_emulator();
  // Register some key event to pass down to the emulator
  document.addEventListener('keydown', event => {
    if (event.key.length === 1) {
      input_char(event.key.charCodeAt(0));
    } else {
      keydown(event.keyCode);
    }
  });
  document.addEventListener('keyup', event => {
    if (event.key.length !== 1) {
      keyup(event.keyCode); // Only notify keyup of special keys
    }
  });
  // Open a file dialog, load the file in memory and insert it into the CPC.
  function selectDisk(drive, span) {
    const input = document.createElement('input');
    input.type = 'file';
    input.onchange = async () => {
      const dsk = Array.from(input.files).filter(f => f.name.toLowerCase().endsWith('.dsk'))[0];
      if (dsk !== undefined) {
        const content = await dsk.arrayBuffer();
        const charArray = new Uint8Array(memory.buffer);
        const ptr = env.malloc(content.byteLength);
        charArray.set(new Uint8Array(content), ptr);
        insert_disk(emulator, drive, ptr, content.byteLength);
        span.innerText = dsk.name;
        console.log(`disk ${dsk.name} inserted`);
      }
    };
    input.click();
  }
  // Register clicks on the diskette buttons
  document.getElementById('A').addEventListener('click', event => {
    selectDisk(0, document.getElementById('A').getElementsByTagName('span')[0]);
  });
  document.getElementById('B').addEventListener('click', event => {
    selectDisk(1, document.getElementById('B').getElementsByTagName('span')[0]);
  });
  // 16ms of CPC time must be executed in the loop hopefully in less than 16ms.
  const frame_time = 16;
  window.stopped = false; // for debugging purposes.
  function mainLoop() {
    const now = Date.now();
    tick(emulator, frame_time); // execute 16ms worth of CPC time.
    if (!window.stopped) {
      window.requestAnimationFrame(mainLoop);
    }
  }
  // Start the pump.
  window.requestAnimationFrame(mainLoop);
}

window.onload = main;
