#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# Installa SAT Modulo Symmetries (Kirchweger-Szeider, TU Wien)
#
# Prerequisiti: libboost-all-dev, cmake, python3
# ═══════════════════════════════════════════════════════════════════

set -e

INSTALL_DIR="$HOME/Desktop/R55/tools/sms"
mkdir -p "$INSTALL_DIR"

echo "═══════════════════════════════════════════════════════════"
echo "  Installazione SAT Modulo Symmetries (SMS)"
echo "═══════════════════════════════════════════════════════════"

# ─── Verifica dipendenze ─────────────────────────────────────────
echo ""
echo "─── Verifica dipendenze ───"

MISSING=""
if ! dpkg -l libboost-all-dev &>/dev/null; then
    MISSING="$MISSING libboost-all-dev"
fi
if ! command -v cmake &>/dev/null; then
    MISSING="$MISSING cmake"
fi
if ! command -v python3 &>/dev/null; then
    MISSING="$MISSING python3"
fi
if ! command -v git &>/dev/null; then
    MISSING="$MISSING git"
fi

if [ -n "$MISSING" ]; then
    echo "  Pacchetti mancanti:$MISSING"
    echo "  Installa con: sudo apt install -y$MISSING"
    exit 1
fi
echo "  Tutte le dipendenze presenti"

# ─── Clone repository ────────────────────────────────────────────
echo ""
echo "─── Clone repository SMS ───"

if [ -d "$INSTALL_DIR/sat-modulo-symmetries" ]; then
    echo "  Repository già presente, aggiornamento..."
    cd "$INSTALL_DIR/sat-modulo-symmetries"
    git pull
else
    cd "$INSTALL_DIR"
    git clone https://github.com/markirch/sat-modulo-symmetries.git
    cd sat-modulo-symmetries
fi

# ─── Build ───────────────────────────────────────────────────────
echo ""
echo "─── Build SMS + CaDiCaL integrato ───"

# Build locale (senza root)
if [ -f "./build-and-install.sh" ]; then
    chmod +x ./build-and-install.sh
    ./build-and-install.sh -l 2>&1 | tail -20
else
    # Fallback: build manuale
    echo "  build-and-install.sh non trovato, build manuale..."
    mkdir -p build && cd build
    cmake .. -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR/local"
    make -j$(nproc)
    make install
fi

# ─── Verifica installazione ──────────────────────────────────────
echo ""
echo "─── Verifica installazione ───"

# Cerca il binario smsg
SMSG=""
for candidate in \
    "$INSTALL_DIR/sat-modulo-symmetries/build/smsg" \
    "$INSTALL_DIR/local/bin/smsg" \
    "$HOME/.local/bin/smsg" \
    "/usr/local/bin/smsg"; do
    if [ -x "$candidate" ]; then
        SMSG="$candidate"
        break
    fi
done

if [ -n "$SMSG" ]; then
    echo "  smsg trovato: $SMSG"
    echo "  Versione:"
    "$SMSG" --help 2>&1 | head -3 || true
else
    echo "  ATTENZIONE: smsg non trovato nel path standard"
    echo "  Cerca manualmente in: $INSTALL_DIR/sat-modulo-symmetries/"
    find "$INSTALL_DIR" -name "smsg" -type f 2>/dev/null
fi

# ─── Verifica PySMS ──────────────────────────────────────────────
echo ""
echo "─── Verifica PySMS ───"
if python3 -c "from pysms.graph_builder import GraphEncodingBuilder; print('  PySMS OK')" 2>/dev/null; then
    echo "  PySMS importabile"
else
    echo "  PySMS non trovato come modulo Python"
    echo "  Prova: pip install pysms  oppure  cd $INSTALL_DIR/sat-modulo-symmetries && pip install -e ."
fi

# ─── Symlink per comodità ────────────────────────────────────────
echo ""
if [ -n "$SMSG" ] && [ ! -f "$HOME/Desktop/R55/tools/smsg" ]; then
    ln -sf "$SMSG" "$HOME/Desktop/R55/tools/smsg"
    echo "  Symlink: ~/Desktop/R55/tools/smsg → $SMSG"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Installazione completata!"
echo ""
echo "  Test rapido (n=10, dovrebbe trovare grafi in secondi):"
echo "    python3 ~/Desktop/R55/src/sms_encoding.py -n 10 --dimacs-only"
echo "    smsg -v 10 --dimacs ~/Desktop/R55/results/sat/r55_10_sms.cnf"
echo ""
echo "  Per R(5,5,43):"
echo "    python3 ~/Desktop/R55/src/sms_encoding.py -n 43 --smsg-direct"
echo "═══════════════════════════════════════════════════════════"
