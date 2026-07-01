#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="/home/moxiao/pdk/smic55/sram/generated/macros"
PDK_SRAM_DIR="/home/moxiao/pdk/smic55/sram/compiler"
JAVA_BIN="/opt/synopsys/verdi/Verdi_O-2018.09-SP2/bin/java"
MACRO_1RW="smic55_4096x32_1rw"
MACRO_2P="smic55_8192x32_2p"

export DISPLAY="${DISPLAY:-$(awk '/nameserver/{print $2; exit}' /etc/resolv.conf):0.0}"
export LIBGL_ALWAYS_INDIRECT="${LIBGL_ALWAYS_INDIRECT:-1}"

mkdir -p \
  "$OUT_DIR/$MACRO_1RW/rtl" \
  "$OUT_DIR/$MACRO_1RW/lib" \
  "$OUT_DIR/$MACRO_1RW/doc" \
  "$OUT_DIR/$MACRO_1RW/report" \
  "$OUT_DIR/$MACRO_2P/rtl" \
  "$OUT_DIR/$MACRO_2P/lib" \
  "$OUT_DIR/$MACRO_2P/doc" \
  "$OUT_DIR/$MACRO_2P/report"

gen_1rw="$(mktemp -d)"
gen_2p="$(mktemp -d)"

"$JAVA_BIN" -jar "$PDK_SRAM_DIR/S55NLLGSPH/S55NLLGSPH/v1p1pa/S55NLLGSPH.jar" \
  -words 4096 \
  -bits 32 \
  -mux 16 \
  -bitwrite \
  -v -lib -pdf \
  -instname "$MACRO_1RW" \
  -savepath "$gen_1rw"

"$JAVA_BIN" -jar "$PDK_SRAM_DIR/S55NLLGDPH/S55NLLGDPH.jar" \
  -words 8192 \
  -bits 32 \
  -mux 16 \
  -bitwrite \
  -v -lib -pdf \
  -instname "$MACRO_2P" \
  -savepath "$gen_2p"

cp "$gen_1rw/$MACRO_1RW.v" "$OUT_DIR/$MACRO_1RW/rtl/"
cp "$gen_1rw/$MACRO_1RW.pdf" "$OUT_DIR/$MACRO_1RW/doc/"
cp "$gen_1rw"/"$MACRO_1RW"_*.lib "$OUT_DIR/$MACRO_1RW/lib/"

cp "$gen_2p/$MACRO_2P.v" "$OUT_DIR/$MACRO_2P/rtl/"
cp "$gen_2p/$MACRO_2P.pdf" "$OUT_DIR/$MACRO_2P/doc/"
cp "$gen_2p"/"$MACRO_2P"_*.lib "$OUT_DIR/$MACRO_2P/lib/"

echo "Generated SMIC55 SRAM views under $OUT_DIR"
