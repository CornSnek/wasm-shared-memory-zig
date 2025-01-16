let WasmObj = null;
let shared_memory = null;
const TD = new TextDecoder();
const TE = new TextEncoder();
onmessage = onmessage_f;
async function onmessage_f(e) {
  if (true) {
    shared_memory = e.data;
    await WebAssembly.instantiateStreaming(fetch("./todo.wasm"), {
      env: { memory: e.data }
    }).then(result => {
      WasmObj = result;
    });
    WasmObj.instance.exports.Hello();
  }
}
//Because memory is shared, memory.buffer (As a SharedArrayBuffer) requires more code to copy for TextDecoder to work.
function copy_shared(addr, len) {
  const buffer_view = new Uint8Array(shared_memory.buffer, addr, len);
  const copy_ab = new ArrayBuffer(len);
  const copy_ab_view = new Uint8Array(copy_ab);
  copy_ab_view.set(buffer_view, 0);
  return TD.decode(copy_ab_view);
}