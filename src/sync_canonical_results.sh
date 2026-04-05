#!/usr/bin/env bash
# Bidirectional sync of canonical SSC results across all 4 machines
LOCAL="/home/antoh/Desktop/R55/results/sat/canonical_ssc/results/"
REMOTE_SERVER="hatweb-server:R55/results/sat/canonical_ssc/results/"
REMOTE_ASUS="whobuntu@172.19.0.2:R55/results/sat/canonical_ssc/results/"
REMOTE_LENOVO="whopad@192.168.1.53:R55/results/sat/canonical_ssc/results/"
OPTS="-a --ignore-existing --include=ssc_*.result --exclude=*"

# Local ↔ Server
rsync $OPTS "$LOCAL" "$REMOTE_SERVER" 2>/dev/null
rsync $OPTS "$REMOTE_SERVER" "$LOCAL" 2>/dev/null

# Local ↔ ASUS
rsync $OPTS "$LOCAL" "$REMOTE_ASUS" 2>/dev/null
rsync $OPTS "$REMOTE_ASUS" "$LOCAL" 2>/dev/null

# ASUS → Lenovo (same physical network, fast)
ssh -o ConnectTimeout=5 whobuntu@172.19.0.2 \
  "rsync -a --ignore-existing --include='ssc_*.result' --exclude='*' \
   ~/R55/results/sat/canonical_ssc/results/ \
   whopad@192.168.1.53:~/R55/results/sat/canonical_ssc/results/" 2>/dev/null

# Lenovo → ASUS → Local
ssh -o ConnectTimeout=5 whobuntu@172.19.0.2 \
  "rsync -a --ignore-existing --include='ssc_*.result' --exclude='*' \
   whopad@192.168.1.53:~/R55/results/sat/canonical_ssc/results/ \
   ~/R55/results/sat/canonical_ssc/results/" 2>/dev/null
rsync $OPTS "$REMOTE_ASUS" "$LOCAL" 2>/dev/null
