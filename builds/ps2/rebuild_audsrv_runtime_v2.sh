#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPS="$ROOT/.ps2deps"
PS2SDK_SRC="$DEPS/ps2sdk-src"
P2D="$DEPS/ps2_drivers"
PREFIX="$DEPS/prefix"
CUSTOM_BDM="$DEPS/bdmfs_fatfs_exfat_utf8.irx"
CUSTOM_AUDSRV="$DEPS/audsrv_underrun_safe.irx"
JOBS="${JOBS:-8}"

if [[ -z "${PS2DEV:-}" || ! -f "${PS2DEV:-}/share/ps2dev.cmake" ]]; then
    if [[ -f "$HOME/.local/ps2dev/share/ps2dev.cmake" ]]; then
        export PS2DEV="$HOME/.local/ps2dev"
    else
        echo "ERRO: PS2DEV não localizado." >&2
        exit 2
    fi
fi
export PS2SDK="${PS2SDK:-$PS2DEV/ps2sdk}"
export PATH="$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin:$PATH"

if [[ -f "$PS2DEV/share/ps2dev.cmake" ]]; then
    TOOLCHAIN="$PS2DEV/share/ps2dev.cmake"
elif [[ -f "$PS2SDK/samples/ps2dev.cmake" ]]; then
    TOOLCHAIN="$PS2SDK/samples/ps2dev.cmake"
else
    echo "ERRO: ps2dev.cmake não encontrado." >&2
    exit 2
fi

AUDSRV_C="$PS2SDK_SRC/iop/sound/audsrv/src/audsrv.c"
[[ -f "$AUDSRV_C" ]] || { echo "ERRO: PS2SDK privado ausente; rode build_ps2.sh completo." >&2; exit 2; }
[[ -f "$P2D/CMakeLists.txt" ]] || { echo "ERRO: ps2_drivers privado ausente." >&2; exit 2; }
[[ -f "$CUSTOM_BDM" ]] || { echo "ERRO: BDM/FatFs custom ausente: $CUSTOM_BDM" >&2; exit 2; }

python3 "$ROOT/builds/ps2/patch_audsrv_runtime_v2.py" "$AUDSRV_C"

echo "[EasyRPG-PS2 runtime v2] Rebuild audsrv IRX (-j${JOBS})"
make -C "$PS2SDK_SRC/iop/sound/audsrv" PS2SDKSRC="$PS2SDK_SRC" clean
make -C "$PS2SDK_SRC/iop/sound/audsrv" PS2SDKSRC="$PS2SDK_SRC" -j"$JOBS"
SOURCE_AUDSRV="$(find "$PS2SDK_SRC/iop/sound/audsrv" -maxdepth 3 -type f -name audsrv.irx -print -quit)"
[[ -n "$SOURCE_AUDSRV" && -f "$SOURCE_AUDSRV" ]] || { echo "ERRO: audsrv.irx não gerado." >&2; exit 2; }
cp "$SOURCE_AUDSRV" "$CUSTOM_AUDSRV"

grep -q 'EASYRPG_AUDSRV_IRX' "$P2D/CMakeLists.txt" || { echo "ERRO: override audsrv não aplicado em ps2_drivers." >&2; exit 2; }

cmake -S "$P2D" -B "$P2D/build-ps2" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SAMPLES=OFF \
    -DEASYRPG_BDMFS_FATFS_IRX="$CUSTOM_BDM" \
    -DEASYRPG_AUDSRV_IRX="$CUSTOM_AUDSRV"
cmake --build "$P2D/build-ps2" -j"$JOBS"

[[ -f "$P2D/build-ps2/libps2_drivers.a" ]] || { echo "ERRO: libps2_drivers.a não gerada." >&2; exit 2; }
mkdir -p "$PREFIX/lib"
cp "$P2D/build-ps2/libps2_drivers.a" "$PREFIX/lib/libps2_drivers.a"

echo "[EasyRPG-PS2 runtime v2] audsrv e libps2_drivers atualizados."
