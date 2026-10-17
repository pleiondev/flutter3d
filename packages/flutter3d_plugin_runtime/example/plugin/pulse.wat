;; A render module of Wasm plugin ABI 3: it drives the `pulse` render step
;; of `acme_pulse.f3dplugin` frame by frame.
;;
;; Built with wabt's wat2wasm, the outside toolchain the committed
;; `pulse.wasm` comes from:
;;
;;     wat2wasm plugin/pulse.wat -o plugin/pulse.wasm
;;
;; `test/acme_pulse_test.dart` holds the committed bytes to this source's
;; behaviour, so a change here without a rebuild is caught.
;;
;; What it may use, as a render module: `i32` and `f32`, one memory, the
;; render imports below and nothing else. Its parameters are named by their
;; index in the declaration's "parameters": 0 is `tint`, 1 is `strength`.
(module
  (import "f3d" "param" (func $param (param i32 i32 f32)))
  (import "f3d" "param_floats" (func $param_floats (param i32 i32 i32)))
  (import "f3d" "draw" (func $draw))
  (import "f3d" "time" (func $time (result f32)))

  ;; Exported, so the browser's own WebAssembly can hand param_floats its
  ;; floats as the interpreter does.
  (memory (export "memory") 1 1)

  ;; The tint, three floats at byte 0: 1.0, 0.6 and 0.2, a warm orange.
  (data (i32.const 0) "\00\00\80\3f\9a\99\19\3f\cd\cc\4c\3e")

  (func (export "f3d_abi") (result i32)
    i32.const 3)

  (func (export "f3d_render_node") (param $frame i32) (param $view i32)
    (local $t f32)
    ;; A triangle wave over each second: |2 fract(t) - 1|.
    call $time
    local.tee $t
    local.get $t
    f32.floor
    f32.sub
    f32.const 2
    f32.mul
    f32.const 1
    f32.sub
    f32.abs
    local.set $t
    ;; strength, then the tint from memory, then the draw.
    i32.const 1
    i32.const 0
    local.get $t
    call $param
    i32.const 0
    i32.const 0
    i32.const 12
    call $param_floats
    call $draw))
