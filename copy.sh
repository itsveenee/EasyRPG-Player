#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
JOBS=8

if [[ -z "${PS2DEV:-}" || ! -f "${PS2DEV:-}/share/ps2dev.cmake" ]]; then
    if [[ -f "$HOME/.local/ps2dev/share/ps2dev.cmake" ]]; then
        export PS2DEV="$HOME/.local/ps2dev"
    else
        echo "ERRO: PS2DEV não localizado." >&2
        exit 1
    fi
fi

if [[ -z "${PS2SDK:-}" || ! -f "${PS2SDK:-}/Defs.make" ]]; then
    export PS2SDK="$PS2DEV/ps2sdk"
fi

export GSKIT="${GSKIT:-$PS2DEV/gsKit}"
export PATH="$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin:$PATH"

case "${1:-}" in
    "")
        if [[ ! -d build-ps2 ]]; then
            echo "[EasyRPG-PS2] Build inicial completo (-j${JOBS})"
            JOBS="$JOBS" ./builds/ps2/build_ps2.sh
        else
            echo "[EasyRPG-PS2] PS2DEV=$PS2DEV"
            echo "[EasyRPG-PS2] PS2SDK=$PS2SDK"
            echo "[EasyRPG-PS2] Build incremental (-j${JOBS})"
            cmake --build build-ps2 -j"$JOBS"
        fi
        ;;
    clean)
        echo "[EasyRPG-PS2] Clean/rebuild completo (-j${JOBS})"
        JOBS="$JOBS" ./builds/ps2/build_ps2.sh
        ;;
    *)
        echo "Uso: ./copy.sh [clean]" >&2
        exit 2
        ;;
esac

cp "/home/marcos/git/EasyRPG-Player/build-ps2/EasyRPG-PS2.elf" "/media/marcos/PS2/APPS" &&   "$HOME/Scripts/ps2eject"
