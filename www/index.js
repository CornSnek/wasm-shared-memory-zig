//This must match inside the build.zig description.
const memory = new WebAssembly.Memory({ initial: 20, maximum: 100, shared: true });
let WasmObj = null;
let worker = null;
let printer_worker = null;
window.addEventListener("load", async () => {
  if ('serviceWorker' in navigator) {
    try {
      await navigator.serviceWorker.register('./coi-serviceworker.js', { scope: '/wasm-shared-memory-zig/' });
      console.log('COI service worker registered and active');
    } catch (err) {
      console.error('Failed to register COI service worker:', err);
    }
  }
  let number_of_tries = 0;
  function init_shared_buffer() { //Check crossOriginIsolated before running
    if (!window.crossOriginIsolated) {
      setTimeout(init_shared_buffer, 500);
      if (number_of_tries++ == 3) window.location.reload();
    }
  }
  init_shared_buffer();
  await WebAssembly.instantiateStreaming(fetch("./todo.wasm"), {
    env: { memory }
  }).then(result => {
    WasmObj = result;
  });
  printer_worker = new Worker("./printer_worker.js", { type: "module" });
  const pw_obj={
    lock: WasmObj.instance.exports.PrintBufferLock.value,
    status: WasmObj.instance.exports.PrintBufferStatus.value,
    buffer: WasmObj.instance.exports.PrintBuffer.value,
    len: WasmObj.instance.exports.PrintBufferLen.value,
    lenmax: WasmObj.instance.exports.PrintBufferMax(),
    memory
  };
  printer_worker.postMessage(pw_obj);
  worker = new Worker("./worker.js");
  worker.postMessage(memory);
});
//Because memory is shared, memory.buffer (As a SharedArrayBuffer) requires more code to copy for TextDecoder to work.
function copy_shared(addr, len) {
  const buffer_view = new Uint8Array(memory.buffer, addr, len);
  const copy_ab = new ArrayBuffer(len);
  const copy_ab_view = new Uint8Array(copy_ab);
  copy_ab_view.set(buffer_view, 0);
  return TD.decode(copy_ab_view);
}