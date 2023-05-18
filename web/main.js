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
  console.log(memory.buffer.byteLength / 1024, 'KB allocated');

  const canvas = document.getElementsByTagName('canvas')[0];
  const ctx = canvas.getContext('2d');
  const imageData = new ImageData(canvas.width, canvas.height);
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
