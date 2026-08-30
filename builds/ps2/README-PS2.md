# EasyRPG Player PS2

- standalone `.elf`
- sem RetroArch/libretro runtime/SNESticle
- SDL2 + PS2SDK/ps2_drivers
- DualShock via eventos SDL joystick crus, com mapa PS2 próprio e seguro
- SDL2/fmt/Pixman/inih/ps2_drivers específicos ficam em `.ps2deps/prefix`
- Meson 1.3.2 privado fica em `.ps2deps/meson`; o Meson do sistema não é usado para Pixman
- vídeo fixo **NTSC 320x240p nativo**, `GS_NONINTERLACED`
- apresentação EasyRPG 320x240 -> GS 320x240 em **1:1**, `nearest`, sem bilinear
- sem opção 480i
- browser: `mass0:/EasyRPG`
- RTP: `mass0:/EasyRPG/RTP`
- config persistente: `mass0:/EasyRPG/config`
- FAT32 + exFAT (BDM/FatFs com LFN UTF-8 e exFAT)
- áudio: OGG Vorbis + WAV
- `.mid`/`.midi` explícito -> `.wav` homônimo

Build:

```bash
export PS2DEV="/caminho/real/para/ps2dev"
export PS2SDK="$PS2DEV/ps2sdk"
export PATH="$PS2DEV/bin:$PS2DEV/ee/bin:$PS2DEV/iop/bin:$PS2DEV/dvp/bin:$PS2SDK/bin:$PATH"
./builds/ps2/build_ps2.sh
```

Saídas:
- `build-ps2/EasyRPG-PS2.elf`
- `build-ps2/EasyRPG-PS2.map`
- `build-ps2/BUILD-INFO.txt`
- `build-ps2/configure.log` e `build-ps2/build.log`
- `build-ps2/ELF-HEADER.txt`, `ELF-PROGRAM-HEADERS.txt` e `ELF-SECTIONS.txt`
- `dist-ps2/EasyRPG/`

## Controles padrão PS2

- D-pad / analógico esquerdo: direção
- Cross: confirmar
- Circle: cancelar
- Select: cancelar/voltar (**nunca Reset**)
- Square: Shift
- Start: Settings
- L1 / R1: Page Up / Page Down
- Triangle, L2, R2, L3, R3 e analógico direito: sem ação perigosa por padrão

## Decisões conservadoras do primeiro build

O build usa `-O2`, `--gc-sections`, sem `-ffast-math` e sem LTO. Isso preserva
previsibilidade no R5900 antes de profiling real.

FreeType/HarfBuzz, Lhasa, MIDI synths, MP3, Opus, XMP, libsndfile, resampler,
ICU, XML, JSON e fontes CJK extras ficam desligados para reduzir RAM, código e
superfície de falhas. Sem ICU, jogos japoneses/CP932 continuam sendo uma etapa
posterior do port.

Pixman 0.46.4 tem o tarball verificado por SHA-512 antes da extração. Threads,
TLS e MIPS32 DSPr2 ficam desligados; o R5900 usa o caminho genérico. O antigo
`pixman-no-tls.patch` do EasyRPG não é aplicado porque foi escrito para Pixman
0.43.4.

O FatFs pinado para o PS2SDK habilita LFN e exFAT. O build mantém o PS2SDK
instalado totalmente intocado: clona uma árvore-fonte privada e pinada do PS2SDK,
usa um FatFs privado/pinado com apenas `FF_LFN_UNICODE=2`, recompila somente
`bdmfs_fatfs.irx` e manda o `ps2_drivers` privado embutir esse IRX por um override
CMake estreito. Nenhum SDL2/fmt/Pixman/inih/ps2_drivers customizado é instalado
globalmente.

SDL2 `release-2.32.10` é recompilado especificamente para este port com:
- `GS_MODE_NTSC`
- `GS_NONINTERLACED`
- `GS_FRAME`
- framebuffer `320x240`
- filas de render menores (adequadas ao único quad fullscreen do EasyRPG)
- sem anunciar render-target, pois o backend PS2 não o implementa de verdade

No EasyRPG, o caminho PS2 ignora scaling genérico/bilinear e apresenta a textura
320x240 diretamente no framebuffer 320x240. Isso evita pixels desiguais e
artefatos de escala fracionária. Configurações antigas não podem reativar
bilinear/widescreen/vsync-off: as invariantes PS2 são reaplicadas após ler o INI.

O SDL2 PS2 expõe o DualShock como joystick cru, sem mapeamento GameController.
O port trata `SDL_JOYBUTTON*`/`SDL_JOYAXISMOTION` diretamente e converte os 16
bits do libpad para Cross/Circle/Square/Triangle, D-pad, Start/Select, L/R e sticks.


A lista de jogos corrige também o comparador do `std::sort` para usar ordem
estrita (`< 0`, não `<= 0`), evitando comportamento indefinido quando dois
nomes diferem apenas por maiúsculas/minúsculas.

O build distingue o prefixo instalado `PS2SDK` da árvore-fonte privada
`PS2SDKSRC`: o checkout fonte é pinado e usado só para `bdmfs_fatfs`. Também
verifica previamente os toolchains EE/IOP e todos os IRXs/libs instalados
exigidos pelo `ps2_drivers` 1.8.0, e fixa FatFs, `inih r62` e `fmt 12.1.0`
pelos commits exatos auditados.
