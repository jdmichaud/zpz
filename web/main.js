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

async function main() {
  // By default, memory is 1 page (64K). We'll need a little more
  const memory = new WebAssembly.Memory({ initial: 1000 });
  const arrayBuffer = memory.buffer;
  console.log(memory.buffer.byteLength / 1024, 'KB allocated');
  const charArray = new Uint8Array(arrayBuffer);

  const canvas = document.getElementsByTagName('canvas')[0];
  const ctx = canvas.getContext('2d');
  const imageData = new ImageData(canvas.width, canvas.height);

  let heapPos = 1; // position in memory of the next available free byte
  let str = ''; // log string buffer

  const wasm = await WebAssembly.instantiateStreaming(fetch("zpz6128.wasm"), {
    env: {
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
            // j >> 1 because we print to line on the PC screen for one CPC line.
            canvasPixel[i + j * width] = pixelArray[i + (j >> 1) * width];
            i += 1;
          }
          j += 1;
        }
        ctx.putImageData(imageData, 0, 0);
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
      __assert_fail: (assertion, file, line, fun) => {
        console.log(`${toStr(charArray, file)}(${line}): ${toStr(charArray, assertion)} in ${toStr(charArray, fun)}`);
      },
      __stack_chk_fail: () => {
        console.log('panic: stack overflow');
      },
    },
  });

  const { new_emulator, input_char, keydown, keyup, tick } = wasm.instance.exports;

  const emulator = new_emulator();

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
  // 16ms of CPC time must be executed in the loop hopefully in less than 16ms.
  const frame_time = 16;
  window.stopped = false; // for debugging purposes.
  function mainLoop() {
    const now = Date.now();
    tick(frame_time);
    if (!window.stopped) {
      window.requestAnimationFrame(mainLoop);
    }
  }

  window.requestAnimationFrame(mainLoop);
}

window.onload = main;
