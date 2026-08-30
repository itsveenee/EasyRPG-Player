#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ELF="$ROOT/build-ps2/EasyRPG-PS2.elf"
DIST="$ROOT/dist-ps2/EasyRPG"

[[ -f "$ELF" ]] || { echo "ERRO: compile primeiro: $ELF" >&2; exit 2; }
[[ -d "$ROOT/lib/rtp" ]] || { echo "ERRO: submódulo RTP ausente." >&2; exit 2; }

rm -rf "$ROOT/dist-ps2"
mkdir -p "$DIST/RTP" "$DIST/Games" "$DIST/config"
cp "$ELF" "$DIST/EasyRPG-PS2.ELF"
cp -a "$ROOT/lib/rtp/." "$DIST/RTP/"

cat > "$DIST/README-USB.txt" <<'EOF'
Copie esta pasta EasyRPG inteira para a raiz do pendrive.

mass0:/EasyRPG/
  EasyRPG-PS2.ELF
  RTP/
  Games/
  config/

Browser: mass0:/EasyRPG
RTP:     mass0:/EasyRPG/RTP
Config:  mass0:/EasyRPG/config

Vídeo: NTSC 320x240p nativo, não-interlaçado, nearest, apresentação 1:1.
Não há modo 480i neste port.

Controles: Cross=confirmar, Circle/Select=cancelar, Square=Shift,
Start=Settings, L1/R1=Page Up/Down. Select nunca executa Reset.

Áudio: OGG Vorbis + WAV.
Pedido explícito NOME.mid/NOME.midi procura NOME.wav.
EOF

echo "Pacote pronto: $ROOT/dist-ps2/EasyRPG"
