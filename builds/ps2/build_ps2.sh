#!/usr/bin/env bash
set -euo pipefail

echo "[EasyRPG-PS2] build_ps2.sh v4.19"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPS="$ROOT/.ps2deps"
PREFIX="$DEPS/prefix"
BUILD="$ROOT/build-ps2"
INFO="$BUILD/BUILD-INFO.txt"
PORTS_REF="57089e8c978111a5dd5bda51335e07b03f1d255e"
SDL_REF="5d249570393f7a37e037abf22cd6012a4cc56a71"
P2D_REF="d40ec5f5dca0c15cc2deacd5f6239fdd626d58fb"
PS2SDK_SRC_REF="a13b5971ec0e39c7ba8b8559b80a4e81c8425352"
FATFS_REF="18cc3d9e07473a6aa3d783a66224b243a7b4974c"
INIH_REF="26254ee9de7681f8825433415443e7116ff24b98"
FMT_REF="407c905e45ad75fc29bf0f9bb7c5c2fd3475976f"
MESON_REF="614d436232d3a86518164cbe2b8af12db3bde009"
PIXVER="0.46.4"
PIX_SHA512="10ddb88b51f5456c440d77a7b4230600b099e818378a9b55f715bbe5ec3d9f1e9da2124d28a2bd3377f1ab20af87e0ec4fa9dadaa20a2f1f880dd2dc7f27ca6c"

# Resolve PS2DEV robustly. Do not trust a guessed/exported path blindly: many
# users already have the R5900 toolchain in PATH while PS2DEV points elsewhere.
PS2DEV_HINT="${PS2DEV:-}"
PS2SDK_HINT="${PS2SDK:-}"

valid_ps2_root() {
    local r="$1"
    [[ -n "$r" ]] || return 1
    [[ -f "$r/share/ps2dev.cmake" || -f "$r/ps2sdk/samples/ps2dev.cmake" || -f "$r/ps2sdk/ps2dev.cmake" ]]
}

resolve_ps2dev() {
    local c cc inferred
    local -a candidates=()

    [[ -n "$PS2DEV_HINT" ]] && candidates+=("$PS2DEV_HINT")
    [[ -n "$PS2SDK_HINT" ]] && candidates+=("$(dirname "$PS2SDK_HINT")")

    cc="$(command -v mips64r5900el-ps2-elf-gcc 2>/dev/null || true)"
    if [[ -n "$cc" ]]; then
        cc="$(readlink -f "$cc" 2>/dev/null || printf '%s' "$cc")"
        inferred="$(cd "$(dirname "$cc")/../.." 2>/dev/null && pwd -P || true)"
        [[ -n "$inferred" ]] && candidates+=("$inferred")
    fi

    candidates+=("$HOME/.local/ps2dev" "$HOME/ps2dev" "/usr/local/ps2dev" "/opt/ps2dev")

    for c in "${candidates[@]}"; do
        [[ -n "$c" ]] || continue
        c="$(cd "$c" 2>/dev/null && pwd -P || true)"
        [[ -n "$c" ]] || continue
        if valid_ps2_root "$c"; then
            printf '%s\n' "$c"
            return 0
        fi
    done
    return 1
}

RESOLVED_PS2DEV="$(resolve_ps2dev || true)"
if [[ -z "$RESOLVED_PS2DEV" ]]; then
    echo "ERRO: não consegui localizar uma instalação PS2DEV válida." >&2
    echo "Procure o toolchain com:" >&2
    echo "  command -v mips64r5900el-ps2-elf-gcc" >&2
    echo "  find /usr/local "$HOME" -maxdepth 5 -name ps2dev.cmake -type f 2>/dev/null" >&2
    echo "Depois exporte PS2DEV para a raiz real da instalação (não para um caminho de exemplo)." >&2
    exit 2
fi

if [[ -n "$PS2DEV_HINT" && "$PS2DEV_HINT" != "$RESOLVED_PS2DEV" ]]; then
    echo "AVISO: PS2DEV='$PS2DEV_HINT' não contém um toolchain CMake válido; usando '$RESOLVED_PS2DEV'." >&2
fi
export PS2DEV="$RESOLVED_PS2DEV"

if [[ -n "$PS2SDK_HINT" && -f "$PS2SDK_HINT/Defs.make" ]]; then
    export PS2SDK="$PS2SDK_HINT"
else
    export PS2SDK="$PS2DEV/ps2sdk"
fi
export GSKIT="${GSKIT:-$PS2DEV/gsKit}"

# PS2SDK is the installed SDK prefix. A separate, pinned source checkout is
# used later only to build our private bdmfs_fatfs IRX; never require the
# installed PS2SDK prefix itself to contain the SDK source tree.
export PATH="$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin:$PATH"
PORTS="$PS2SDK/ports"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"

if [[ -f "$PS2DEV/share/ps2dev.cmake" ]]; then
    TOOLCHAIN="$PS2DEV/share/ps2dev.cmake"
elif [[ -f "$PS2SDK/samples/ps2dev.cmake" ]]; then
    TOOLCHAIN="$PS2SDK/samples/ps2dev.cmake"
elif [[ -f "$PS2SDK/ps2dev.cmake" ]]; then
    TOOLCHAIN="$PS2SDK/ps2dev.cmake"
else
    echo "ERRO: ps2dev.cmake não encontrado após resolver PS2DEV='$PS2DEV' e PS2SDK='$PS2SDK'." >&2
    exit 2
fi

echo "[EasyRPG-PS2] PS2DEV=$PS2DEV"
echo "[EasyRPG-PS2] PS2SDK=$PS2SDK"
echo "[EasyRPG-PS2] TOOLCHAIN=$TOOLCHAIN"

need_host() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERRO: ferramenta obrigatória ausente: $1" >&2
        exit 2
    }
}
for x in git cmake make python3 ninja curl tar; do need_host "$x"; done
for x in mips64r5900el-ps2-elf-gcc mips64r5900el-ps2-elf-g++ \
         mips64r5900el-ps2-elf-ar mips64r5900el-ps2-elf-strip \
         mips64r5900el-ps2-elf-size mips64r5900el-ps2-elf-readelf \
         mips64r5900el-ps2-elf-pkg-config \
         mipsel-none-elf-gcc mipsel-none-elf-ld mipsel-none-elf-ar \
         mipsel-none-elf-objcopy mipsel-none-elf-strip; do
    need_host "$x"
done

# The installed SDK is a release/prefix layout. It does not need Defs.make,
# iop/fs sources, or download_dependencies.sh. Require only the installed
# headers, libraries, IRXs and host helper actually consumed by this build.
for d in "$PS2SDK/ee/include" "$PS2SDK/common/include" "$PS2SDK/ee/lib" "$PS2SDK/iop/irx"; do
    [[ -d "$d" ]] || {
        echo "ERRO: PS2SDK instalado incompleto: falta $d" >&2
        exit 2
    }
done
[[ -x "$PS2SDK/bin/bin2c" ]] || {
    echo "ERRO: PS2SDK instalado incompleto: falta $PS2SDK/bin/bin2c" >&2
    exit 2
}

mkdir -p "$DEPS" "$PORTS"

# ps2_drivers 1.8.0 converts all of these SDK IRXs/libraries while building its
# static archive, even though the final ELF only pulls the objects it uses. Fail
# here with a useful list instead of halfway through CMake/bin2c.
missing_sdk=()
for irx in sio2man iomanX fileXio mcman mcserv bdm usbd usbmass_bd mx4sio_bd \
           cdfs ps2dev9 ps2atad ps2hdd ps2fs mtapman padman libsd audsrv \
           poweroff ps2mouse ps2kbd ps2cam netman smap ps2ip-nm ps2ips; do
    [[ -f "$PS2SDK/iop/irx/$irx.irx" ]] || missing_sdk+=("iop/irx/$irx.irx")
done
for lib in libfileXio.a libmtap.a libpadx.a libaudsrv.a libpoweroff.a \
           libmouse.a libkbd.a libps2cam.a libnetman.a libps2ip.a libps2ips.a; do
    [[ -f "$PS2SDK/ee/lib/$lib" ]] || missing_sdk+=("ee/lib/$lib")
done
if (( ${#missing_sdk[@]} )); then
    printf 'ERRO: PS2SDK incompleto para ps2_drivers 1.8.0. Faltam:\n' >&2
    printf '  %s\n' "${missing_sdk[@]}" >&2
    echo "Atualize/recompile o PS2SDK antes de continuar." >&2
    exit 2
fi

# Cheap C++17 header sanity before downloading/building dependencies.
cat > "$DEPS/.toolchain_probe.cpp" <<'CPP'
#include <optional>
#include <string>
#include <vector>
int f() { std::optional<int> x = 1; std::vector<std::string> v = {"ps2"}; return *x + (int)v.size(); }
CPP
mips64r5900el-ps2-elf-g++ -std=gnu++17 -D_EE -DPS2 -D__PS2__ -G0 \
    -I"$PS2SDK/ee/include" -I"$PS2SDK/common/include" -c \
    "$DEPS/.toolchain_probe.cpp" -o "$DEPS/.toolchain_probe.o"
rm -f "$DEPS/.toolchain_probe.cpp" "$DEPS/.toolchain_probe.o"

# Everything specific to this port lives here. Never overwrite the user's
# standard SDL2/fmt/Pixman/ps2_drivers installation in $PS2SDK/ports.
rm -rf "$PREFIX"
mkdir -p "$PREFIX/include" "$PREFIX/lib/pkgconfig"

# Known-good standard PS2 libraries. These are ordinary ps2sdk-ports packages,
# not EasyRPG-specific forks, so install globally only when they are missing.
BASE_SOURCE="pre-existing PS2SDK ports"
need_base=0
for lib in libz.a libogg.a libvorbis.a libvorbisfile.a; do
    [[ -f "$PORTS/lib/$lib" ]] || need_base=1
done
if [[ ! -f "$PORTS/lib/libpng.a" && ! -f "$PORTS/lib/libpng16.a" ]]; then
    need_base=1
fi
if [[ ! -f "$PORTS/lib/libgskit.a" && ! -f "$PS2DEV/gsKit/lib/libgskit.a" ]]; then
    need_base=1
fi

if (( need_base )); then
    P2PORTS="$DEPS/ps2sdk-ports"
    if [[ ! -d "$P2PORTS/.git" ]]; then
        git clone https://github.com/ps2dev/ps2sdk-ports.git "$P2PORTS"
    fi
    git -C "$P2PORTS" fetch --force origin "$PORTS_REF"
    git -C "$P2PORTS" checkout --detach "$PORTS_REF"
    [[ "$(git -C "$P2PORTS" rev-parse HEAD)" == "$PORTS_REF" ]] || {
        echo "ERRO: ps2sdk-ports não ficou no commit auditado $PORTS_REF" >&2
        exit 2
    }
    BASE_SOURCE="ps2sdk-ports $PORTS_REF"
    # The helper builds more than this port needs. An unrelated later package
    # may fail; revalidate only our exact requirements afterwards.
    set +e
    ( cd "$P2PORTS" && ./build-cmakelibs.sh )
    ports_rc=$?
    set -e
    if (( ports_rc != 0 )); then
        echo "AVISO: build-cmakelibs.sh retornou $ports_rc; validando somente dependências EasyRPG..." >&2
    fi
fi

for lib in libz.a libogg.a libvorbis.a libvorbisfile.a; do
    [[ -f "$PORTS/lib/$lib" ]] || {
        echo "ERRO: dependência PS2 ausente: $PORTS/lib/$lib" >&2
        exit 2
    }
done
if [[ ! -f "$PORTS/lib/libpng.a" && ! -f "$PORTS/lib/libpng16.a" ]]; then
    echo "ERRO: libpng estática não encontrada em $PORTS/lib." >&2
    exit 2
fi
if [[ ! -f "$PORTS/lib/libgskit.a" && ! -f "$PS2DEV/gsKit/lib/libgskit.a" ]]; then
    echo "ERRO: gsKit não encontrado após bootstrap." >&2
    exit 2
fi

# liblcf requires INI. Keep the port copy private.
INIH="$DEPS/inih"
if [[ ! -d "$INIH/.git" ]]; then
    git clone --depth=1 --branch r62 https://github.com/benhoyt/inih.git "$INIH"
else
    git -C "$INIH" fetch --force origin tag r62
    git -C "$INIH" reset --hard r62
fi
[[ "$(git -C "$INIH" rev-parse HEAD)" == "$INIH_REF" ]] || {
    echo "ERRO: inih r62 não resolve para o commit auditado $INIH_REF" >&2
    exit 2
}
mips64r5900el-ps2-elf-gcc -D_EE -DPS2 -D__PS2__ -O2 -G0 \
    -ffunction-sections -fdata-sections \
    -I"$PS2SDK/ee/include" -I"$PS2SDK/common/include" \
    -c "$INIH/ini.c" -o "$DEPS/inih.o"
mips64r5900el-ps2-elf-ar rcs "$PREFIX/lib/libinih.a" "$DEPS/inih.o"
cp "$INIH/ini.h" "$PREFIX/include/ini.h"
cat > "$PREFIX/lib/pkgconfig/libinih.pc" <<PC
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: inih
Description: simple INI parser
Version: 62
Libs: -L\${libdir} -linih
Cflags: -I\${includedir}
PC

# fmt is mandatory and private so no host/global fmt can leak into this build.
FMT="$DEPS/fmt"
if [[ ! -d "$FMT/.git" ]]; then
    git clone --depth=1 --branch 12.1.0 https://github.com/fmtlib/fmt.git "$FMT"
else
    git -C "$FMT" fetch --force origin tag 12.1.0
    git -C "$FMT" reset --hard 12.1.0
fi
[[ "$(git -C "$FMT" rev-parse HEAD)" == "$FMT_REF" ]] || {
    echo "ERRO: fmt 12.1.0 não resolve para o commit auditado $FMT_REF" >&2
    exit 2
}
rm -rf "$FMT/build-ps2"
cmake -S "$FMT" -B "$FMT/build-ps2" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_CXX_FLAGS_RELEASE="-O2 -DNDEBUG -ffunction-sections -fdata-sections" \
    -DFMT_DOC=OFF -DFMT_TEST=OFF
cmake --build "$FMT/build-ps2" -j"$JOBS"
cmake --install "$FMT/build-ps2"
[[ -f "$PREFIX/lib/libfmt.a" ]] || { echo "ERRO: fmt privado não foi instalado." >&2; exit 2; }

# Pixman 0.46.4 requires Meson >= 1.3.0. Do not use or modify the host
# Meson: keep a pinned private Meson 1.3.2 checkout for reproducibility.
MESON_SRC="$DEPS/meson"
if [[ ! -d "$MESON_SRC/.git" ]]; then
    git clone --depth=1 --branch 1.3.2 https://github.com/mesonbuild/meson.git "$MESON_SRC"
else
    git -C "$MESON_SRC" fetch --force origin tag 1.3.2
    git -C "$MESON_SRC" reset --hard 1.3.2
fi
[[ "$(git -C "$MESON_SRC" rev-parse HEAD)" == "$MESON_REF" ]] || {
    echo "ERRO: Meson 1.3.2 não resolve para o commit auditado $MESON_REF" >&2
    exit 2
}
MESON=(python3 "$MESON_SRC/meson.py")
MESON_VERSION="$("${MESON[@]}" --version)"
[[ "$MESON_VERSION" == "1.3.2" ]] || {
    echo "ERRO: Meson privado inesperado: $MESON_VERSION (esperado 1.3.2)" >&2
    exit 2
}
echo "[EasyRPG-PS2] Meson privado=$MESON_VERSION ($MESON_REF)"

# Pixman 0.46.4: checksum the official source, completely disable pthread/TLS,
# and force the generic MIPS path (R5900 is not MIPS32 DSPr2).
PIX="$DEPS/pixman-$PIXVER"
ARC="$DEPS/pixman-$PIXVER.tar.gz"
[[ -f "$ARC" ]] || curl -fL "https://cairographics.org/releases/pixman-$PIXVER.tar.gz" -o "$ARC"
python3 - "$ARC" "$PIX_SHA512" <<'PY'
from pathlib import Path
import hashlib, sys
p = Path(sys.argv[1])
expected = sys.argv[2].lower()
h = hashlib.sha512()
with p.open('rb') as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b''):
        h.update(chunk)
got = h.hexdigest().lower()
if got != expected:
    raise SystemExit(f"Pixman SHA512 mismatch: expected {expected}, got {got}; remove {p} and retry")
print(f"Pixman SHA512 OK: {got}")
PY
rm -rf "$PIX"
tar -xzf "$ARC" -C "$DEPS"
python3 - "$PIX/meson.build" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
old = "dep_threads = dependency('threads')"
new = "dep_threads = null_dep\nconfig.set('PIXMAN_NO_TLS', 1)"
if s.count(old) != 1:
    raise SystemExit(f"Pixman: expected one threads dependency anchor, found {s.count(old)}")
p.write_text(s.replace(old, new, 1), encoding="utf-8", newline="\n")
PY

# R5900/newlib portability: on this ABI int32_t is typedef'd as long int even
# though plain int is also 32-bit. Pixman declares pad_repeat_get_scanline_bounds()
# with int32_t* outputs but historically used plain-int temporaries in the
# bilinear helper. GCC 15 correctly rejects passing int* as int32_t*. Do not
# suppress the diagnostic or cast around it: make the temporaries match the API.
python3 - "$PIX/pixman/pixman-inlines.h" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
marker1 = "int32_t width1 = *width, left_pad1, right_pad1;"
marker2 = "int32_t width2 = *width, left_pad2, right_pad2;"
if marker1 in s and marker2 in s:
    print("Pixman R5900 int32_t portability fix: already present")
else:
    pat = re.compile(
        r"(?m)^([ \t]*)int width1 = \*width, left_pad1, right_pad1;\n"
        r"([ \t]*)int width2 = \*width, left_pad2, right_pad2;$"
    )
    matches = list(pat.finditer(s))
    if len(matches) != 1:
        raise SystemExit(
            f"Pixman: expected exactly one bilinear int/int32_t portability anchor, found {len(matches)}"
        )
    m = matches[0]
    repl = (
        f"{m.group(1)}int32_t width1 = *width, left_pad1, right_pad1;\n"
        f"{m.group(2)}int32_t width2 = *width, left_pad2, right_pad2;"
    )
    s = s[:m.start()] + repl + s[m.end():]
    p.write_text(s, encoding="utf-8", newline="\n")
    print("Pixman R5900 int32_t portability fix: applied")
PY

# R5900/newlib portability, part 2: pixman_fixed_t is int32_t and therefore
# long int on this ABI. The generic repeat() helper intentionally also has
# plain-int callers (y/y1/y2), so changing its parameter type would merely
# move the mismatch. Add a typed sibling and route only fixed-point vx/vy
# call sites through it. No casts and no warning suppression.
python3 - "$PIX/pixman/pixman-inlines.h" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

helper_sig = "repeat_fixed (pixman_repeat_t repeat, pixman_fixed_t *c, pixman_fixed_t size)"
if helper_sig not in s:
    marker = "static force_inline int\npixman_fixed_to_bilinear_weight (pixman_fixed_t x)"
    if s.count(marker) != 1:
        raise SystemExit(
            f"Pixman: expected exactly one repeat_fixed insertion anchor, found {s.count(marker)}"
        )
    helper = (
        "static force_inline pixman_bool_t\n"
        "repeat_fixed (pixman_repeat_t repeat, pixman_fixed_t *c, pixman_fixed_t size)\n"
        "{\n"
        "    if (repeat == PIXMAN_REPEAT_NONE)\n"
        "    {\n"
        "        if (*c < 0 || *c >= size)\n"
        "            return FALSE;\n"
        "    }\n"
        "    else if (repeat == PIXMAN_REPEAT_NORMAL)\n"
        "    {\n"
        "        while (*c >= size)\n"
        "            *c -= size;\n"
        "        while (*c < 0)\n"
        "            *c += size;\n"
        "    }\n"
        "    else if (repeat == PIXMAN_REPEAT_PAD)\n"
        "    {\n"
        "        *c = CLIP (*c, 0, size - 1);\n"
        "    }\n"
        "    else /* REFLECT */\n"
        "    {\n"
        "        *c = MOD (*c, size * 2);\n"
        "        if (*c >= size)\n"
        "            *c = size * 2 - *c - 1;\n"
        "    }\n"
        "    return TRUE;\n"
        "}\n\n"
    )
    s = s.replace(marker, helper + marker, 1)

fixed_calls = (
    ("repeat (PIXMAN_REPEAT_NORMAL, &vx, src_width_fixed);",
     "repeat_fixed (PIXMAN_REPEAT_NORMAL, &vx, src_width_fixed);", 3),
    ("repeat (PIXMAN_REPEAT_NORMAL, &vy, max_vy);",
     "repeat_fixed (PIXMAN_REPEAT_NORMAL, &vy, max_vy);", 2),
    ("repeat (PIXMAN_REPEAT_NORMAL, &vx, pixman_int_to_fixed(src_image->bits.width));",
     "repeat_fixed (PIXMAN_REPEAT_NORMAL, &vx, pixman_int_to_fixed(src_image->bits.width));", 1),
)

for old, new, expected in fixed_calls:
    # Fresh source has expected old calls. A future idempotent invocation may
    # already contain the new calls; accept exactly the known final count.
    old_count = s.count(old)
    new_count = s.count(new)
    if old_count == expected and new_count == 0:
        s = s.replace(old, new)
    elif old_count == 0 and new_count == expected:
        pass
    else:
        raise SystemExit(
            f"Pixman: unexpected repeat_fixed call-site counts for {old!r}: "
            f"old={old_count}, new={new_count}, expected={expected}"
        )

# Guard the plain-int callers: they are deliberately NOT changed.
for int_call in (
    "repeat (PIXMAN_REPEAT_PAD, &y, src_image->bits.height);",
    "repeat (PIXMAN_REPEAT_PAD, &y1, src_image->bits.height);",
    "repeat (PIXMAN_REPEAT_PAD, &y2, src_image->bits.height);",
    "repeat (PIXMAN_REPEAT_NORMAL, &y1, src_image->bits.height);",
    "repeat (PIXMAN_REPEAT_NORMAL, &y2, src_image->bits.height);",
):
    if int_call not in s:
        raise SystemExit(f"Pixman: expected plain-int repeat() caller missing: {int_call}")

p.write_text(s, encoding="utf-8", newline="\n")
print("Pixman R5900 fixed-point repeat portability fix: applied")
PY
CROSS="$DEPS/meson-ps2.ini"
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
rm -rf "$PIX/build-ps2"
"${MESON[@]}" setup "$PIX/build-ps2" "$PIX" --cross-file "$CROSS" \
    --prefix "$PREFIX" --buildtype release -Ddefault_library=static -Db_staticpic=false \
    -Dtests=disabled -Ddemos=disabled -Dlibpng=disabled \
    -Dtls=disabled -Dmips-dspr2=disabled
"${MESON[@]}" compile -C "$PIX/build-ps2" -j "$JOBS"
"${MESON[@]}" install -C "$PIX/build-ps2"
[[ -f "$PREFIX/lib/libpixman-1.a" ]] || { echo "ERRO: Pixman privado não foi instalado." >&2; exit 2; }

# FAT32 + exFAT + UTF-8 LFN. Keep the installed PS2SDK completely untouched:
# build bdmfs_fatfs from a pinned private PS2SDK source checkout and a separately
# pinned FatFs checkout, then teach our private ps2_drivers build to embed that
# one IRX instead of ${PS2SDK}/iop/irx/bdmfs_fatfs.irx.
PS2SDK_SRC="$DEPS/ps2sdk-src"
if [[ ! -d "$PS2SDK_SRC/.git" ]]; then
    git clone https://github.com/ps2dev/ps2sdk.git "$PS2SDK_SRC"
fi
git -C "$PS2SDK_SRC" fetch --force origin "$PS2SDK_SRC_REF"
git -C "$PS2SDK_SRC" reset --hard "$PS2SDK_SRC_REF"
git -C "$PS2SDK_SRC" clean -fdx
[[ "$(git -C "$PS2SDK_SRC" rev-parse HEAD)" == "$PS2SDK_SRC_REF" ]] || {
    echo "ERRO: PS2SDK fonte não ficou no commit auditado $PS2SDK_SRC_REF" >&2
    exit 2
}
[[ -f "$PS2SDK_SRC/Defs.make" && -d "$PS2SDK_SRC/iop/fs/bdmfs_fatfs" ]] || {
    echo "ERRO: checkout privado do PS2SDK não contém bdmfs_fatfs/Defs.make." >&2
    exit 2
}

FATFS="$DEPS/fatfs-iop-r0.16"
if [[ ! -d "$FATFS/.git" ]]; then
    git clone https://github.com/fjtrujy/FatFs.git "$FATFS"
fi
git -C "$FATFS" fetch --force origin "$FATFS_REF"
git -C "$FATFS" reset --hard "$FATFS_REF"
git -C "$FATFS" clean -fdx
[[ "$(git -C "$FATFS" rev-parse HEAD)" == "$FATFS_REF" ]] || {
    echo "ERRO: FatFs iop-r0.16 não ficou no commit auditado $FATFS_REF" >&2
    exit 2
}

mkdir -p "$PS2SDK_SRC/common/external_deps"
ln -sfn "$FATFS" "$PS2SDK_SRC/common/external_deps/fatfs"
FFCONF="$FATFS/source/include/ffconf.h"
[[ -f "$FFCONF" ]] || { echo "ERRO: ffconf.h do FatFs privado não encontrado: $FFCONF" >&2; exit 2; }

python3 - "$FFCONF" <<'PYFATCONF'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
def val(name):
    m = re.search(rf"(?m)^\s*#define\s+{re.escape(name)}\s+(\d+)\b", s)
    if not m:
        raise SystemExit(f"FatFs: missing {name}")
    return int(m.group(1))
if val("FF_USE_LFN") < 1:
    raise SystemExit("FatFs: upstream disabled LFN; refusing blind patch")
if val("FF_FS_EXFAT") != 1:
    raise SystemExit("FatFs: upstream disabled exFAT; refusing blind patch")
pat = r"(?m)^(\s*#define\s+FF_LFN_UNICODE\s+)\d+(\s*(?:/\*.*)?$)"
s, n = re.subn(pat, r"\g<1>2\g<2>", s)
if n != 1:
    raise SystemExit(f"FatFs: expected one FF_LFN_UNICODE define, found {n}")
p.write_text(s, encoding="utf-8", newline="\n")
PYFATCONF
grep -Eq '^#define[[:space:]]+FF_FS_EXFAT[[:space:]]+1\b' "$FFCONF"
grep -Eq '^#define[[:space:]]+FF_LFN_UNICODE[[:space:]]+2\b' "$FFCONF"

make -C "$PS2SDK_SRC/iop/fs/bdmfs_fatfs" PS2SDKSRC="$PS2SDK_SRC" clean
make -C "$PS2SDK_SRC/iop/fs/bdmfs_fatfs" PS2SDKSRC="$PS2SDK_SRC" -j"$JOBS"
SOURCE_IRX="$PS2SDK_SRC/iop/fs/bdmfs_fatfs/irx/bdmfs_fatfs.irx"
CUSTOM_IRX="$DEPS/bdmfs_fatfs_exfat_utf8.irx"
[[ -f "$SOURCE_IRX" ]] || { echo "ERRO: bdmfs_fatfs.irx privado não foi gerado: $SOURCE_IRX" >&2; exit 2; }
cp "$SOURCE_IRX" "$CUSTOM_IRX"

P2D="$DEPS/ps2_drivers"
if [[ ! -d "$P2D/.git" ]]; then
    git clone https://github.com/fjtrujy/ps2_drivers.git "$P2D"
fi
git -C "$P2D" fetch --force origin tag 1.8.0
git -C "$P2D" reset --hard 1.8.0
git -C "$P2D" clean -fdx
[[ "$(git -C "$P2D" rev-parse HEAD)" == "$P2D_REF" ]] || {
    echo "ERRO: ps2_drivers 1.8.0 não resolve para o commit auditado $P2D_REF" >&2
    exit 2
}

# ps2_drivers 1.8.0 normally hardcodes every IRX under ${PS2SDK}/iop/irx.
# Add a narrow override for bdmfs_fatfs only; all other IRXs/libs still come
# from the user's installed SDK.
python3 - "$P2D/CMakeLists.txt" <<'PYP2D'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
old = 'function(add_irx_source irx_name output_var)\n    set(irx_path "${PS2SDK}/iop/irx/${irx_name}.irx")\n'
new = ('function(add_irx_source irx_name output_var)\n'
       '    if(irx_name STREQUAL "bdmfs_fatfs" AND DEFINED EASYRPG_BDMFS_FATFS_IRX)\n'
       '        set(irx_path "${EASYRPG_BDMFS_FATFS_IRX}")\n'
       '    else()\n'
       '        set(irx_path "${PS2SDK}/iop/irx/${irx_name}.irx")\n'
       '    endif()\n')
if s.count(old) != 1:
    raise SystemExit(f"ps2_drivers: expected one add_irx_source anchor, found {s.count(old)}")
p.write_text(s.replace(old, new, 1), encoding="utf-8", newline="\n")
PYP2D

rm -rf "$P2D/build-ps2"
cmake -S "$P2D" -B "$P2D/build-ps2" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SAMPLES=OFF \
    -DEASYRPG_BDMFS_FATFS_IRX="$CUSTOM_IRX"
cmake --build "$P2D/build-ps2" -j"$JOBS"
[[ -f "$P2D/build-ps2/libps2_drivers.a" ]] || { echo "ERRO: libps2_drivers.a não foi gerada." >&2; exit 2; }
cp "$P2D/build-ps2/libps2_drivers.a" "$PREFIX/lib/libps2_drivers.a"
cp -a "$P2D/include/." "$PREFIX/include/"

# Private SDL2 PS2, pinned to the exact audited release commit. Force actual
# NTSC 320x240 non-interlaced output and keep upstream PS2 audio/joystick.
SDL="$DEPS/SDL-2.32.10-ps2"
if [[ ! -d "$SDL/.git" ]]; then
    git clone https://github.com/libsdl-org/SDL.git "$SDL"
fi
git -C "$SDL" fetch --force origin tag release-2.32.10
git -C "$SDL" reset --hard release-2.32.10
git -C "$SDL" clean -fdx
[[ "$(git -C "$SDL" rev-parse HEAD)" == "$SDL_REF" ]] || {
    echo "ERRO: SDL2 release-2.32.10 não resolve para o commit auditado $SDL_REF" >&2
    exit 2
}
python3 - "$SDL" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
def replace_once(path, old, new, label):
    p = root / path
    s = p.read_text(encoding="utf-8")
    n = s.count(old)
    if n != 1:
        raise SystemExit(f"SDL2 patch {label}: expected 1 anchor, found {n} in {path}")
    p.write_text(s.replace(old, new, 1), encoding="utf-8", newline="\n")

replace_once(
    "src/main/ps2/SDL_ps2_main.c",
    "#include <ps2_filesystem_driver.h>",
    "#include <ps2_filesystem_driver.h>\n#include <ps2_fileXio_driver.h>\n#include <ps2_usb_driver.h>",
    "USB-only driver includes")
replace_once(
    "src/main/ps2/SDL_ps2_main.c",
    "static void init_drivers(void)\n{\n\tinit_ps2_filesystem_driver();\n}\n\n"
    "static void deinit_drivers(void)\n{\n\tdeinit_ps2_filesystem_driver();\n}",
    "static void init_drivers(void)\n{\n"
    "    /* EasyRPG-PS2 only needs mass0:. Avoid MC/HDD/CDFS/MX4SIO IRXs. */\n"
    "    init_fileXio_driver();\n"
    "    init_usb_driver(true);\n"
    "}\n\n"
    "static void deinit_drivers(void)\n{\n"
    "    deinit_usb_driver(true);\n"
    "    deinit_fileXio_driver();\n"
    "}",
    "USB-only filesystem bootstrap")
replace_once(
    "src/main/ps2/SDL_ps2_main.c",
    "    char cwd[FILENAME_MAX];\n\n"
    "    prepare_IOP();\n"
    "    init_drivers();\n\n"
    "    getcwd(cwd, sizeof(cwd));\n"
    "    waitUntilDeviceIsReady(cwd);",
    "    char mass_root[] = \"mass0:/\";\n\n"
    "    prepare_IOP();\n"
    "    init_drivers();\n\n"
    "    waitUntilDeviceIsReady(mass_root);",
    "wait specifically for mass0")
replace_once(
    "src/video/ps2/SDL_ps2video.c",
    "    current_mode.w = 640;\n    current_mode.h = 480;",
    "    current_mode.w = 320;\n    current_mode.h = 240;",
    "reported 320x240 mode")
replace_once(
    "src/render/ps2/SDL_render_ps2.c",
    "#define RENDER_QUEUE_PER_POOLSIZE 1024 * 256 // 256K of persistent renderqueue\n"
    "/* Size of Oneshot drawbuffer (Double Buffered, so it uses this size * 2) */\n"
    "#define RENDER_QUEUE_OS_POOLSIZE 1024 * 1024 * 2 // 2048K of oneshot renderqueue",
    "#define RENDER_QUEUE_PER_POOLSIZE 1024 * 128 // 128K: EasyRPG uses a tiny persistent queue\n"
    "/* Size of Oneshot drawbuffer (Double Buffered, so it uses this size * 2) */\n"
    "#define RENDER_QUEUE_OS_POOLSIZE 1024 * 512 // 512K per buffer; ample for one fullscreen quad",
    "smaller EE render queues")
replace_once(
    "src/render/ps2/SDL_render_ps2.c",
    "    gsGlobal->Mode = GS_MODE_NTSC;\n    gsGlobal->Height = 448;",
    "    /* EasyRPG-PS2: true NTSC 240p, exact 320x240 framebuffer. */\n"
    "    gsGlobal->Mode = GS_MODE_NTSC;\n"
    "    gsGlobal->Interlace = GS_NONINTERLACED;\n"
    "    gsGlobal->Field = GS_FRAME;\n"
    "    gsGlobal->Width = 320;\n"
    "    gsGlobal->Height = 240;",
    "native 240p GS mode")
replace_once(
    "src/render/ps2/SDL_render_ps2.c",
    ".flags = SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC | SDL_RENDERER_TARGETTEXTURE,",
    ".flags = SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC,",
    "do not advertise unsupported render targets")
PY

grep -q 'gsGlobal->Interlace = GS_NONINTERLACED' "$SDL/src/render/ps2/SDL_render_ps2.c"
grep -q 'gsGlobal->Width = 320' "$SDL/src/render/ps2/SDL_render_ps2.c"
grep -q 'gsGlobal->Height = 240' "$SDL/src/render/ps2/SDL_render_ps2.c"
rm -rf "$SDL/build-ps2"
cmake -S "$SDL" -B "$SDL/build-ps2" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_PREFIX_PATH="$PREFIX;$PORTS" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS_RELEASE="-O2 -DNDEBUG -ffunction-sections -fdata-sections -I$PREFIX/include" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=OFF \
    -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF
cmake --build "$SDL/build-ps2" -j"$JOBS"
cmake --install "$SDL/build-ps2"
[[ -f "$PREFIX/lib/libSDL2.a" ]] || { echo "ERRO: SDL2 PS2 240p privado não foi instalado." >&2; exit 2; }
[[ -f "$PREFIX/lib/libSDL2main.a" ]] || {
    echo "ERRO: SDL2main PS2 não foi instalado; sem ele não existe main() que invoque SDL_main()." >&2
    exit 2
}

# Verify exact submodule paths are populated before CMake.
git -C "$ROOT" submodule update --init --recursive
[[ -f "$ROOT/lib/liblcf/CMakeLists.txt" ]] || { echo "ERRO: lib/liblcf ausente." >&2; exit 2; }
[[ -d "$ROOT/lib/rtp" ]] || { echo "ERRO: lib/rtp ausente." >&2; exit 2; }

rm -rf "$BUILD"
mkdir -p "$BUILD"

# Configure against the private prefix first. PLAYER_PS2_PREFIX is also added
# to CMAKE_FIND_ROOT_PATH by the PS2 patch, preventing host-library leakage.
cmake -S "$ROOT" -B "$BUILD" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DCMAKE_PREFIX_PATH="$PREFIX;$PORTS" \
    -DPLAYER_PS2_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS_RELEASE="-O2 -DNDEBUG -ffunction-sections -fdata-sections" \
    -DCMAKE_CXX_FLAGS_RELEASE="-O2 -DNDEBUG -ffunction-sections -fdata-sections" \
    -DBUILD_SHARED_LIBS=OFF \
    -DPLAYER_TARGET_PLATFORM=SDL2 \
    -DPLAYER_AUDIO_BACKEND=SDL2 \
    -DPLAYER_BUILD_LIBLCF=ON \
    -DLIBLCF_WITH_INI=ON \
    -DLIBLCF_WITH_ICU=OFF \
    -DLIBLCF_WITH_XML=OFF \
    -DLIBLCF_UPDATE_MIMEDB=OFF \
    -DLIBLCF_ENABLE_TOOLS=OFF \
    -DLIBLCF_ENABLE_TESTS=OFF \
    -DLIBLCF_ENABLE_BENCHMARKS=OFF \
    -DLIBLCF_ENABLE_INSTALL=OFF \
    -DPLAYER_WITH_FREETYPE=OFF \
    -DPLAYER_WITH_HARFBUZZ=OFF \
    -DPLAYER_WITH_LHASA=OFF \
    -DPLAYER_WITH_NLOHMANN_JSON=OFF \
    -DPLAYER_WITH_NATIVE_MIDI=OFF \
    -DPLAYER_WITH_MPG123=OFF \
    -DPLAYER_WITH_LIBSNDFILE=OFF \
    -DPLAYER_WITH_OGGVORBIS=ON \
    -DPLAYER_WITH_OPUS=OFF \
    -DPLAYER_WITH_WILDMIDI=OFF \
    -DPLAYER_WITH_FLUIDSYNTH=OFF \
    -DPLAYER_WITH_FLUIDLITE=OFF \
    -DPLAYER_WITH_XMP=OFF \
    -DPLAYER_ENABLE_FMMIDI=OFF \
    -DPLAYER_ENABLE_DRWAV=ON \
    -DPLAYER_AUDIO_RESAMPLER=OFF \
    -DPLAYER_WITH_SPEEXDSP=OFF \
    -DPLAYER_WITH_SAMPLERATE=OFF \
    -DPLAYER_WITH_BAEKMUK=OFF \
    -DPLAYER_WITH_WQY=OFF \
    -DPLAYER_ENABLE_TESTS=OFF \
    2>&1 | tee "$BUILD/configure.log"

cmake --build "$BUILD" -j"$JOBS" 2>&1 | tee "$BUILD/build.log"

ELF="$BUILD/EasyRPG-PS2.elf"
if [[ ! -f "$ELF" ]]; then
    echo "ERRO: build terminou, mas $ELF não existe." >&2
    find "$BUILD" -maxdepth 3 -name '*.elf' -print >&2 || true
    exit 3
fi

mips64r5900el-ps2-elf-readelf -h "$ELF" > "$BUILD/ELF-HEADER.txt"
mips64r5900el-ps2-elf-readelf -lW "$ELF" > "$BUILD/ELF-PROGRAM-HEADERS.txt"
mips64r5900el-ps2-elf-readelf -SW "$ELF" > "$BUILD/ELF-SECTIONS.txt"
{
    echo "EasyRPG-PS2 build information"
    echo "=============================="
    echo "Bootstrap:     v4.19"
    date -u '+UTC: %Y-%m-%dT%H:%M:%SZ'
    echo "Player:       $(git -C "$ROOT" rev-parse HEAD)"
    echo "liblcf:       $(git -C "$ROOT/lib/liblcf" rev-parse HEAD)"
    echo "RTP:          $(git -C "$ROOT/lib/rtp" rev-parse HEAD)"
    echo "Base ports:    $BASE_SOURCE"
    echo "SDL2:         $SDL_REF (release-2.32.10) + private 320x240p patch"
    echo "PS2SDK src:   $PS2SDK_SRC_REF (private checkout; installed SDK untouched)"
    echo "FatFs:        $FATFS_REF (iop-r0.16; private FF_LFN_UNICODE=2)"
    echo "ps2_drivers:  $P2D_REF (1.8.0) + embedded private UTF-8/exFAT bdmfs_fatfs"
    echo "inih:         $INIH_REF (r62)"
    echo "fmt:          $FMT_REF (12.1.0)"
    echo "Meson:        $MESON_REF (1.3.2 private; host Meson ignored)"
    echo "Pixman:       $PIXVER, SHA512 verified, pthread/TLS/DSPr2 off"
    echo "Prefix:       $PREFIX"
    echo "Video:        NTSC 320x240p, GS_NONINTERLACED, nearest, 1:1"
    echo "Controls:     raw DualShock; Cross=OK Circle/Select=Cancel Start=Settings L1/R1=Page"
    echo "Config:       mass0:/EasyRPG/config"
    echo
    mips64r5900el-ps2-elf-size "$ELF"
} | tee "$INFO"

echo "OK: $ELF"
echo "LOG configure: $BUILD/configure.log"
echo "LOG build:     $BUILD/build.log"
echo "INFO:          $INFO"
echo "ELF PHDR:      $BUILD/ELF-PROGRAM-HEADERS.txt"
echo "ELF sections:  $BUILD/ELF-SECTIONS.txt"
"$ROOT/builds/ps2/deploy_ps2.sh"