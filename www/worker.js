let WasmObj = null;
let shared_memory = null;
const TD = new TextDecoder();
const TE = new TextEncoder();
onmessage = onmessage_f;
async function onmessage_f(e) {
  if (true) {
    shared_memory = e.data;
    await WebAssembly.instantiateStreaming(fetch("./todo.wasm"), {
      env: {
        memory: e.data, JSPanic: (addr, len) => {
          const byte_view = new Uint8Array(shared_memory.buffer);
          let str = "";
          for (let i = 0; i < len; i++) str += String.fromCharCode(byte_view[addr + i]);
          console.error(str);
        }
      }
    }).then(result => {
      WasmObj = result;
    });
    WasmObj.instance.exports.Hello();
  }
}