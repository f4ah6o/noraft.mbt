#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${root_dir}/target/bench"
mkdir -p "${out_dir}"

args=("$@")

echo "Running Rust bench..."
cargo run --release --bin bench -- "${args[@]+"${args[@]}"}" > "${out_dir}/rust.json"

echo "Running MoonBit bench (native)..."
moon run --release --target native src/cmd/bench -- --target=native "${args[@]+"${args[@]}"}" > "${out_dir}/moonbit-native.json"

echo "Running MoonBit bench (wasm-gc)..."
moon run --release --target wasm-gc src/cmd/bench -- --target=wasm-gc "${args[@]+"${args[@]}"}" > "${out_dir}/moonbit-wasm-gc.json"

python3 "${root_dir}/tools/bench_compare.py" \
  "${out_dir}/rust.json" \
  "${out_dir}/moonbit-native.json" \
  "${out_dir}/moonbit-wasm-gc.json"
