import { PBLock, PBStatus, PrintType } from "./wasm_enums.js"
onmessage = onmessage_f
let obj = null;
function do_print(str, print_type) {
  if (print_type === PrintType.log) {
    console.log(str);
  } else if (print_type === PrintType.warn) {
    console.warn(str);
  } else {
    console.error(str);
  }
}
function JSPrint(buffer_addr, expected_len) {
  const byte_view = new Int8Array(obj.memory.buffer);
  const num_messages = byte_view[buffer_addr];
  let byte_now = buffer_addr + 1;
  let last_print_type = null;
  let combined_str = "";
  for (let i = 0; i < num_messages; i++) {
    const print_type = byte_view[byte_now];
    byte_now += 1;
    if (byte_now - buffer_addr === expected_len) {
      console.error("Corrupted string: Reading byte outside of expected length");
    }
    if (print_type >= PrintType.$$length) {
      console.error("Corrupted string: Invalid PrintType");
    }
    let str = "";
    let ch = null;
    while ((ch = byte_view[byte_now++]) != 0) {
      str += String.fromCharCode(ch);
      if (byte_now - buffer_addr === expected_len) {
        console.error("Corrupted string: Reading byte outside of expected length");
      }
    }
    if (print_type === last_print_type) {
      combined_str += str;
    } else {
      if (last_print_type != null) do_print(combined_str, last_print_type);
      combined_str = str;
      last_print_type = print_type;
    }
  }
  if (last_print_type != null) do_print(combined_str, last_print_type);
}
async function check_print_data() {
  const lockto32i = obj.lock / 4;
  const statusto32i = obj.status / 4;
  const lento32i = obj.len / 4;
  const I32Buffer = new Int32Array(obj.memory.buffer);
  while (true) {
    while (Atomics.exchange(I32Buffer, lockto32i, PBLock.locked) === PBLock.locked)
      Atomics.wait(I32Buffer, lockto32i, PBLock.locked);
    const status = Atomics.load(I32Buffer, statusto32i, PBStatus.filled);
    if (status !== PBStatus.empty) {
      const len_ptr = Atomics.load(I32Buffer, lento32i);
      const buffer_ptr = Atomics.load(I32Buffer, obj.buffer / 4);
      JSPrint(buffer_ptr, Atomics.load(I32Buffer, len_ptr / 4));
      if (status === PBStatus.full) console.error(`A log message may have been truncated due to filling ${obj.lenmax} maximum bytes too quickly`);
      Atomics.store(I32Buffer, statusto32i, PBStatus.empty);
      Atomics.notify(I32Buffer, statusto32i);
      Atomics.store(I32Buffer, lockto32i, PBLock.unlocked);
    } else {
      Atomics.store(I32Buffer, lockto32i, PBLock.unlocked);
      Atomics.wait(I32Buffer, statusto32i, PBStatus.empty);
    }
  }
}
async function onmessage_f(e) {
  obj = e.data;
  check_print_data();
}