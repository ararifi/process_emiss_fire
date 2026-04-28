#!/usr/bin/env bash
set -euo pipefail



# Password is avaiable at
# https://www.globalfiredata.org/ancill/GFED5_SFTP_info.txt

source "env.sh" || { echo "ERROR: failed to source env.sh" >&2; exit 1; }

# ----------------------------------------------------------------

# Year to fetch (override from CLI: ./fetch_GFED_NRT.sh 2026)
YEAR="${1:-2026}"

# For 2024 and earlier, use the science-quality Reprocessed archive;
# for 2025 onward, use the near-real-time Update directory.
if [ "$YEAR" -le 2024 ]; then
    REMOTEDIR="/GFED5/GFED5.1NRT/Reprocessed/Daily/Species/CMB/${YEAR}"
else
    REMOTEDIR="/GFED5/GFED5.1NRT/Update/${YEAR}"
fi
OUTDIR="${input_root}/GFED_NRT/daily/${YEAR}"

mkdir -p "$OUTDIR"

sftp -P "$PORT" "${USER}@${HOST}" <<EOF
cd ${REMOTEDIR}
lcd ${OUTDIR}
mget *spe_CMB*${YEAR}*.nc
bye
EOF
