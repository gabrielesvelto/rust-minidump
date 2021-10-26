#!/bin/sh

# Ensure we have the right tools
rustup component add llvm-tools-preview
LLVM_PROFDATA="${HOME}/.rustup/toolchains/stable-x86_64-unknown-linux-gnu/lib/rustlib/x86_64-unknown-linux-gnu/bin/llvm-profdata"

# STEP 0: Make sure there is no left-over profiling data from previous runs
rm -rf /tmp/pgo-data
mkdir /tmp/pgo-data

# STEP 1: Build the instrumented binaries
RUSTFLAGS="-C target-cpu=native -C profile-generate=/tmp/pgo-data" \
    cargo build --release --target=x86_64-unknown-linux-gnu

# STEP 2: Run the instrumented binaries with some typical data
MINIDUMP_STACKWALK="target/x86_64-unknown-linux-gnu/release/minidump-stackwalk"
MINIDUMP_DUMP="target/x86_64-unknown-linux-gnu/release/minidump_dump"
find pgodata -type f -name "*.zst" -exec zstd -q -d --keep {} \;
PGO_SAMPLES="
android-aarch64
android-arm
linux-x86_64
linux-x86
macos-x86_64
windows-aarch64
windows-x86
windows-x86_64
"

for i in $PGO_SAMPLES; do
  echo "Running ${PROGRAM} --raw-json pgodata/minidumps/${i}.extra pgodata/minidumps/${i}.dmp"
  "${MINIDUMP_STACKWALK}" --raw-json "pgodata/minidumps/${i}.extra" \
    "pgodata/minidumps/${i}.dmp" pgodata/symbols 1>/dev/null 2>/dev/null
  "${MINIDUMP_DUMP}" "pgodata/minidumps/${i}.dmp" 1>/dev/null 2>/dev/null
done

# STEP 3: Merge the `.profraw` files into a `.profdata` file
"${LLVM_PROFDATA}" merge -o /tmp/pgo-data/merged.profdata /tmp/pgo-data

# STEP 4: Use the `.profdata` file for guiding optimizations
RUSTFLAGS="-C target-cpu=native -C profile-use=/tmp/pgo-data/merged.profdata" \
    cargo build --release --target=x86_64-unknown-linux-gnu
