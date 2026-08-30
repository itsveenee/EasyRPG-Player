#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPS="$ROOT/.ps2deps"
PREFIX="$DEPS/prefix"
PIX="$DEPS/pixman-0.46.4"
MESON_SRC="$DEPS/meson"
CROSS="$DEPS/meson-ps2.ini"
JOBS="${JOBS:-8}"

if [[ -z "${PS2DEV:-}" || ! -f "${PS2DEV:-}/share/ps2dev.cmake" ]]; then
    if [[ -f "$HOME/.local/ps2dev/share/ps2dev.cmake" ]]; then
        export PS2DEV="$HOME/.local/ps2dev"
    else
        echo "ERRO: PS2DEV não localizado." >&2
        exit 2
    fi
fi

if [[ -z "${PS2SDK:-}" || ! -f "${PS2SDK:-}/Defs.make" ]]; then
    export PS2SDK="$PS2DEV/ps2sdk"
fi

export PATH="$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin:$PATH"
PORTS="$PS2SDK/ports"

[[ -f "$MESON_SRC/meson.py" ]] || {
    echo "ERRO: Meson privado ausente em $MESON_SRC; rode um build completo uma vez." >&2
    exit 2
}
[[ -f "$PIX/meson.build" ]] || {
    echo "ERRO: fonte Pixman privada ausente em $PIX; rode um build completo uma vez." >&2
    exit 2
}
mkdir -p "$PREFIX"

MESON=(python3 "$MESON_SRC/meson.py")

cat > "$CROSS" <<CROSSFILE
[binaries]
c = 'mips64r5900el-ps2-elf-gcc'
cpp = 'mips64r5900el-ps2-elf-g++'
ar = 'mips64r5900el-ps2-elf-ar'
strip = 'mips64r5900el-ps2-elf-strip'
pkg-config = 'mips64r5900el-ps2-elf-pkg-config'

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'ps2'
cpu_family = 'mips'
cpu = 'r5900'
endian = 'little'

[built-in options]
default_library = 'static'
c_args = ['-D_EE', '-DPS2', '-D__PS2__', '-O2', '-G0', '-ffunction-sections', '-fdata-sections', '-I$PREFIX/include', '-I$PS2SDK/ee/include', '-I$PS2SDK/common/include', '-I$PS2DEV/gsKit/include', '-I$PORTS/include']
c_link_args = ['-L$PREFIX/lib', '-L$PS2SDK/ee/lib', '-L$PS2DEV/gsKit/lib', '-L$PORTS/lib', '-Wl,-zmax-page-size=128', '-T$PS2SDK/ee/startup/linkfile']
CROSSFILE

echo "[EasyRPG-PS2] Rebuild somente Pixman static non-PIC (-j${JOBS})"
rm -rf "$PIX/build-ps2"

"${MESON[@]}" setup "$PIX/build-ps2" "$PIX" --cross-file "$CROSS" \
    --prefix "$PREFIX" --buildtype release -Ddefault_library=static -Db_staticpic=false \
    -Dtests=disabled -Ddemos=disabled -Dlibpng=disabled \
    -Dtls=disabled -Dmips-dspr2=disabled

[[ -f "$PIX/build-ps2/compile_commands.json" ]] || {
    echo "ERRO: compile_commands.json do Pixman não foi gerado." >&2
    exit 2
}
if grep -Eq -- '(^|[[:space:]])-fPIC([[:space:]]|$)|(^|[[:space:]])-fpic([[:space:]]|$)' "$PIX/build-ps2/compile_commands.json"; then
    echo "ERRO: Pixman ainda está sendo compilado como PIC; b_staticpic=false não prevaleceu." >&2
    exit 2
fi
"${MESON[@]}" introspect "$PIX/build-ps2" --buildoptions > "$PIX/build-ps2/buildoptions.json"
python3 - "$PIX/build-ps2/buildoptions.json" <<'PY'
import json, sys
p = sys.argv[1]
opts = json.load(open(p, "r", encoding="utf-8"))
vals = {o.get("name"): o.get("value") for o in opts}
if vals.get("b_staticpic") is not False:
    raise SystemExit("ERRO: Meson b_staticpic não está false no build do Pixman.")
print("[EasyRPG-PS2] Verificado: Pixman b_staticpic=false; sem -fPIC/-fpic.")
PY

"${MESON[@]}" compile -C "$PIX/build-ps2" -j "$JOBS"
"${MESON[@]}" install -C "$PIX/build-ps2"

[[ -f "$PREFIX/lib/libpixman-1.a" ]] || {
    echo "ERRO: libpixman-1.a não foi instalada em $PREFIX/lib." >&2
    exit 2
}

echo "[EasyRPG-PS2] Pixman static non-PIC pronto."
