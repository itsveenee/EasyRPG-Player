#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SDL="$ROOT/.ps2deps/SDL-2.32.10-ps2"
PREFIX="$ROOT/.ps2deps/prefix"
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
export GSKIT="${GSKIT:-$PS2DEV/gsKit}"
export PATH="$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin:$PATH"
PORTS="$PS2SDK/ports"

if [[ -f "$PS2DEV/share/ps2dev.cmake" ]]; then
    TOOLCHAIN="$PS2DEV/share/ps2dev.cmake"
elif [[ -f "$PS2SDK/samples/ps2dev.cmake" ]]; then
    TOOLCHAIN="$PS2SDK/samples/ps2dev.cmake"
else
    echo "ERRO: ps2dev.cmake não encontrado." >&2
    exit 2
fi

[[ -f "$SDL/src/render/ps2/SDL_render_ps2.c" ]] || {
    echo "ERRO: SDL privado ausente. Rode build_ps2.sh completo uma vez." >&2
    exit 2
}
grep -q 'CRT-safe 320-column timing' "$SDL/src/render/ps2/SDL_render_ps2.c" || {
    echo "ERRO: patch CRT runtime v1 ausente no SDL privado." >&2
    exit 2
}
grep -q 'pre-clear the next DMA buffer' "$SDL/src/audio/ps2/SDL_ps2audio.c" || {
    echo "ERRO: patch áudio runtime v1 ausente no SDL privado." >&2
    exit 2
}

if [[ ! -f "$SDL/build-ps2/CMakeCache.txt" ]]; then
    echo "[EasyRPG-PS2 runtime v1] Configurando SDL privado"
    cmake -S "$SDL" -B "$SDL/build-ps2" \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_PREFIX_PATH="$PREFIX;$PORTS" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS_RELEASE="-O2 -DNDEBUG -ffunction-sections -fdata-sections -I$PREFIX/include" \
        -DCMAKE_POSITION_INDEPENDENT_CODE=OFF \
        -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF
fi

echo "[EasyRPG-PS2 runtime v1] Rebuild incremental SDL (-j${JOBS})"
cmake --build "$SDL/build-ps2" -j"$JOBS"
cmake --install "$SDL/build-ps2"
[[ -f "$PREFIX/lib/libSDL2.a" ]] || {
    echo "ERRO: libSDL2.a não instalada." >&2
    exit 2
}
echo "[EasyRPG-PS2 runtime v1] SDL atualizado."
