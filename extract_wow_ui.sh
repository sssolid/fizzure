#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./extract_wow_ui_v2.sh "<WOW_ROOT>" "<PROJECT_ROOT>"
# Example:
#   ./extract_wow_ui_v2.sh "/games/ascension-wow/drive_c/Program Files/Ascension Launcher/resources/epoch_live" \
#                          "/run/media/solid/Miss_Files/Fizzure"

WOW_ROOT="${1:-}"
PROJ_ROOT="${2:-}"
if [[ -z "${WOW_ROOT}" || -z "${PROJ_ROOT}" ]]; then
  echo "Usage: $0 \"<WOW_ROOT>\" \"<PROJECT_ROOT>\"" >&2
  exit 2
fi

OUT_DIR="${PROJ_ROOT%/}/libs/wow335-interface"
FRAME_DIR="$OUT_DIR/Interface/FrameXML"
GLUE_DIR="$OUT_DIR/Interface/GlueXML"
ADDONS_DIR="$OUT_DIR/Interface/AddOns"
mkdir -p "$OUT_DIR"

# --- Find MPQExtractor ---
MPQBIN="${MPQBIN:-}"
if [[ -z "${MPQBIN}" ]]; then
  if command -v MPQExtractor >/dev/null 2>&1; then
    MPQBIN="$(command -v MPQExtractor)"
  elif [[ -x "$HOME/MPQExtractor/build/bin/MPQExtractor" ]]; then
    MPQBIN="$HOME/MPQExtractor/build/bin/MPQExtractor"
  elif [[ -x "$HOME/Downloads/MPQExtractor/build/bin/MPQExtractor" ]]; then
    MPQBIN="$HOME/Downloads/MPQExtractor/build/bin/MPQExtractor"
  else
    echo "MPQExtractor not found. Set MPQBIN=/full/path/to/MPQExtractor and re-run." >&2
    exit 3
  fi
fi

echo "Using MPQExtractor: $MPQBIN"
echo "WoW root:          $WOW_ROOT"
echo "Output folder:     $OUT_DIR"
echo

# --- Gather archives (base + patches + locale patches) ---
mapfile -t ALL_MPQS < <(find "$WOW_ROOT" -type f -iname '*.mpq' | grep -i '/data/' | sort -f)
if [[ ${#ALL_MPQS[@]} -eq 0 ]]; then
  echo "No MPQs under $WOW_ROOT/Data" >&2
  exit 4
fi

BASE_ORDER=(common.MPQ common-2.MPQ expansion.MPQ lichking.MPQ)
BASE_MPQS=()
PATCH_MPQS=()

shopt -s nocasematch
for f in "${ALL_MPQS[@]}"; do
  base="$(basename "$f")"
  if [[ " ${BASE_ORDER[*]} " == *" $base "* ]]; then
    BASE_MPQS+=("$f")
  else
    # all others treated as patches (includes patch-*.MPQ and locale e.g. enUS/patch-enUS*.MPQ)
    PATCH_MPQS+=("$f")
  fi
done
shopt -u nocasematch

ORDERED_MPQS=()
for b in "${BASE_ORDER[@]}"; do
  for f in "${BASE_MPQS[@]}"; do
    [[ "$(basename "$f")" == "$b" ]] && ORDERED_MPQS+=("$f")
  done
done
if [[ ${#PATCH_MPQS[@]} -gt 0 ]]; then
  mapfile -t SORTED_PATCHES < <(printf '%s\n' "${PATCH_MPQS[@]}" | sort -f)
  ORDERED_MPQS+=("${SORTED_PATCHES[@]}")
fi

# --- Extract helper that tries multiple masks ---
extract_try() {
  local mpq="$1"; shift
  local ok=1
  for mask in "$@"; do
    echo "    mask: $mask"
    if "$MPQBIN" -o "$OUT_DIR" -f -e "$mask" "$mpq" >/dev/null 2>&1; then
      ok=0
    fi
  done
  return $ok
}

echo "Extracting Interface trees..."
for mpq in "${ORDERED_MPQS[@]}"; do
  echo "From: $mpq"

  # FrameXML
  extract_try "$mpq" \
    'Interface/FrameXML/*' \
    'Interface\FrameXML\*' \
    'INTERFACE/FRAMEXML/*' \
    'INTERFACE\FRAMEXML\*' || true

  # GlueXML
  extract_try "$mpq" \
    'Interface/GlueXML/*' \
    'Interface\GlueXML\*' \
    'INTERFACE/GLUEXML/*' \
    'INTERFACE\GLUEXML\*' || true

  # Blizzard_* AddOns inside archives (some builds ship a subset)
  extract_try "$mpq" \
    'Interface/AddOns/Blizzard_*/*' \
    'Interface\AddOns\Blizzard_*\*' \
    'INTERFACE/ADDONS/BLIZZARD_*/*' \
    'INTERFACE\ADDONS\BLIZZARD_*\*' || true
done

# --- Copy your already-unpacked Addons tree (fast and reliable) ---
# Your path (Linux-side) shows: .../Interface/Addons  (note lowercase 'o')
SRC_ADDONS="$WOW_ROOT/Interface/Addons"
ALT_ADDONS="$WOW_ROOT/Interface/AddOns"
if [[ -d "$SRC_ADDONS" ]]; then
  mkdir -p "$ADDONS_DIR"
  rsync -a --delete "$SRC_ADDONS/" "$ADDONS_DIR/"
elif [[ -d "$ALT_ADDONS" ]]; then
  mkdir -p "$ADDONS_DIR"
  rsync -a --delete "$ALT_ADDONS/" "$ADDONS_DIR/"
fi

echo
echo "Post-check:"
echo "  FrameXML: $(find "$FRAME_DIR" -type f 2>/dev/null | wc -l || echo 0) files"
echo "  GlueXML:  $(find "$GLUE_DIR"  -type f 2>/dev/null | wc -l || echo 0) files"
echo "  AddOns:   $(find "$ADDONS_DIR" -maxdepth 2 -type f 2>/dev/null | wc -l || echo 0) files"

# --- Fallback: if FrameXML/GlueXML still empty, fetch a clean 3.3.5 dump ---
need_fallback=0
[[ ! -d "$FRAME_DIR" || -z "$(ls -A "$FRAME_DIR" 2>/dev/null || true)" ]] && need_fallback=1
[[ ! -d "$GLUE_DIR"  || -z "$(ls -A "$GLUE_DIR"  2>/dev/null || true)" ]] && need_fallback=1

if [[ $need_fallback -eq 1 ]]; then
  echo
  echo "No FrameXML/GlueXML found in your MPQs. Pulling pre-extracted 3.3.5 UI as fallback..."
  mkdir -p "$OUT_DIR/Interface"
  tmp="$OUT_DIR/.tmp-335"
  rm -rf "$tmp"
  git clone --depth=1 https://github.com/wowgaming/3.3.5-interface-files "$tmp"
  rsync -a "$tmp/FrameXML/" "$FRAME_DIR/"
  rsync -a "$tmp/GlueXML/"  "$GLUE_DIR/"  || true
  # Prefer your live Addons, but fill Blizzard_* if missing
  if [[ ! -d "$ADDONS_DIR" || -z "$(ls -A "$ADDONS_DIR" 2>/dev/null || true)" ]]; then
    rsync -a "$tmp/AddOns/" "$ADDONS_DIR/"
  fi
  rm -rf "$tmp"
fi

echo
echo "Done. Library root is ready at: $OUT_DIR"
