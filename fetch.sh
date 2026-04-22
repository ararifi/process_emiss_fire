#!/usr/bin/env bash
set -euo pipefail

. details.sh

YEAR=2026
REMOTEDIR="/GFED5/GFED5.1NRT/Update/${YEAR}"
OUTDIR="download/Daily/${YEAR}"

mkdir -p "$OUTDIR"

sftp -P "$PORT" "${USER}@${HOST}" <<EOF
cd ${REMOTEDIR}
lcd ${OUTDIR}
mget *spe_CMB*${YEAR}*.nc
bye
EOF
