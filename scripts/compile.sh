#!/usr/bin/env bash
set -euo pipefail

CIRCUITS_DIR="$(cd "$(dirname "$0")/../circuits" && pwd)"
BUILD_DIR="$(cd "$(dirname "$0")/.." && pwd)/build/circuits"
PTAU="$BUILD_DIR/powersOfTau28_hez_final_18.ptau"
PTAU_URL="https://hermez.s3-eu-west-1.amazonaws.com/powersOfTau28_hez_final_18.ptau"

mkdir -p "$BUILD_DIR"
cd "$CIRCUITS_DIR"

# Install npm dependencies if not present
if [ ! -d node_modules ]; then
    echo "[compile] Installing npm dependencies..."
    npm install
fi

# Download Powers of Tau if not present (Hermez ceremony, no per-circuit trusted setup)
if [ ! -f "$PTAU" ]; then
    echo "[compile] Downloading Powers of Tau..."
    curl -Lo "$PTAU" "$PTAU_URL"
fi

compile_circuit() {
    local name="$1"
    local src="$CIRCUITS_DIR/${name}.circom"
    local out="$BUILD_DIR/${name}"
    mkdir -p "$out"

    echo "[compile] Compiling ${name}.circom..."
    circom "$src" \
        --r1cs \
        --wasm \
        --sym \
        --output "$out" \
        -l "$CIRCUITS_DIR/../node_modules"

    local constraints
    constraints=$(grep "^constraints:" "$out/${name}.r1cs.stats" 2>/dev/null || \
                  circom "$src" --inspect -l "$CIRCUITS_DIR/../node_modules" 2>&1 | grep -i "constraint" || true)
    echo "[compile] ${name}: constraint info → ${constraints:-run inspect manually}"

    echo "[compile] Generating PLONK zkey for ${name}..."
    npx snarkjs plonk setup "$out/${name}.r1cs" "$PTAU" "$out/${name}.zkey"

    echo "[compile] Exporting verification key for ${name}..."
    npx snarkjs zkey export verificationkey "$out/${name}.zkey" "$out/${name}_vkey.json"

    echo "[compile] ${name} done."
}

compile_circuit "withdraw"

# Record constraint counts
echo "[compile] Counting constraints..."
npx snarkjs r1cs info "$BUILD_DIR/withdraw/withdraw.r1cs" | tee -a "$(dirname "$0")/../docs/circuit-constraints.md"

echo "[compile] All circuits compiled. Artifacts in $BUILD_DIR"
