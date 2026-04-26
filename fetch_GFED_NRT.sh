#!/usr/bin/env bash
set -euo pipefail

source "env.sh" || { echo "ERROR: failed to source env.sh" >&2; exit 1; }

# ----------------------------------------------------------------

# Year to fetch (override from CLI: ./fetch_GFED_NRT.sh 2026)
YEAR="${1:-2026}"

REMOTEDIR="/GFED5/GFED5.1NRT/Update/${YEAR}"
OUTDIR="${input_root}/${YEAR}"

mkdir -p "$OUTDIR"

sftp -P "$PORT" "${USER}@${HOST}" <<EOF
cd ${REMOTEDIR}
lcd ${OUTDIR}
mget *spe_CMB*${YEAR}*.nc
bye
EOF
