#!/bin/bash

# ---------------------------------------------------------------
# PROJECT ROOT
# ---------------------------------------------------------------
# Absolute path to this project directory
export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------
# MODULES
# ---------------------------------------------------------------
# The pipeline needs three tools: GNU parallel, CDO, and NCO
# (ncks, ncap2, ncatted, ncrename). Their toolchain dependencies
# (GCC, OpenMPI, HDF5, netCDF) are auto-loaded by Lmod, so they
# don't have to be listed.
#
# Pick the machine via $MACHINE (default: snellius). Set
# MACHINE=none to skip module loading (e.g. when CDO/NCO/parallel
# are installed via conda/mamba/spack). For other clusters, add a
# new case below with the corresponding module names.

export MACHINE="${MACHINE:-snellius}"

case "$MACHINE" in
    snellius)
        module load 2024
        module load parallel/20240722-GCCcore-13.3.0
        module load CDO/2.4.4-gompi-2024a
        module load NCO/5.2.9-foss-2024a
        ;;
    none)
        ;;
    *)
        echo "WARN: Unknown MACHINE='$MACHINE'; no modules loaded." >&2
        ;;
esac
# ---------------------------------------------------------------

# ---------------------------------------------------------------
# SLURM (used when submitting regrid_GFED_NRT.sh via sbatch)
# ---------------------------------------------------------------
# These are NOT picked up by `#SBATCH` directives (sbatch parses
# those before the script runs). Pass them on the sbatch command
# line, e.g.:
#   source env.sh
#   YEAR=2025 ; MODE=echam
#   mkdir -p "$SLURM_LOG_DIR"
#   sbatch -A "$SLURM_ACCOUNT" -p "$SLURM_PARTITION" \
#          --job-name="$SLURM_JOB_NAME" \
#          --time="$SLURM_TIME" --nodes="$SLURM_NODES" \
#          --ntasks="$SLURM_NTASKS" \
#          --output="$SLURM_LOG_DIR/${SLURM_JOB_NAME}_%j.out" \
#          --error="$SLURM_LOG_DIR/${SLURM_JOB_NAME}_%j.err" \
#          regrid_GFED_NRT.sh "$YEAR" "$MODE"

# SLURM account to charge the job to
export SLURM_ACCOUNT="srsei10308"

# SLURM partition / queue to submit to
export SLURM_PARTITION="rome"

# Wall-time limit (HH:MM:SS)
export SLURM_TIME="04:00:00"

# Number of nodes
export SLURM_NODES=1

# Number of tasks (also drives parallel --jobs in regrid_GFED_NRT.sh)
export SLURM_NTASKS=64

# SLURM job name
export SLURM_JOB_NAME="regrid_GFED_NRT"

# Directory for SLURM stdout/stderr log files (created if missing)
export SLURM_LOG_DIR="${PROJECT_ROOT}/logs"


# --- SFTP credentials (used by fetch_GFED_NRT.sh) ---
# For more details check: https://www.globalfiredata.org/data.html

# Remote SFTP host that serves the GFED_NRT data
export HOST="ftp.prd.dip.wur.nl"

# SFTP port on the remote host
export PORT=1022

# SFTP username for authentication
export USER="sftp0041-1-r"

# Password is avaiable at
# https://www.globalfiredata.org/ancill/GFED5_SFTP_info.txt

# ---------------------------------------------------------------
# ROOT PATHS (shared by echam and icon)
# ---------------------------------------------------------------

# Root directory for raw downloads (dataset/frequency/year are
# appended by fetch_GFED_NRT.sh and regrid_GFED_NRT.sh,
#  e.g. data/download/GFED_NRT/daily/2025)
export input_root="${PROJECT_ROOT}/data/download"

# Root scratch directory for intermediate files
# (mode/GFED_NRT/year subdirectories are appended in regrid.sh,
#  e.g. /tmp/echam/GFED_NRT/2025 or /tmp/icon/GFED_NRT/2025)
export tmp_root="/tmp"

# Root output directory for processed files
# (mode/GFED_NRT/daily/year subdirectories are appended in regrid.sh,
#  e.g. data/processed/echam/GFED_NRT/daily/2025
#       data/processed/icon/GFED_NRT/daily/2025)
export output_root="${PROJECT_ROOT}/data/processed"


# --- SHARED INPUT FILES ---

# NetCDF file with grid-cell areas, used to convert per-cell totals
# to per-area fluxes during the `prepare` step
# file is sourced from 
export input_eco="${PROJECT_ROOT}/data/grid_area.nc"

# Directory holding the metadata template files (year 2015 on T63)
# used as a source for ncatted in copy_meta
export meta_template_dir="${PROJECT_ROOT}/template/2015"


# --- SHARED FILENAME PREFIXES ---

# Filename prefix of the raw GFED_NRT input files
export input_prefix="GFED5NRTspe_CMB"

# Prefix used when constructing target output filenames.
# Final filenames follow the pattern:
#   ${target_prefix}_${var}_wildfire_${YEAR}_${template_grid}.nc
# e.g. echam: emiss_GFED_NRT_SO2_wildfire_2025_T63.nc
#      icon : emiss_GFED_NRT_SO2_wildfire_2025_icon_grid_0005_R02B04_G.nc
export target_prefix="emiss_GFED_NRT"


# --- GRID TEMPLATES (the only per-mode difference) ---
# regrid.sh selects one of these based on $MODE and derives
# grid_path (template/<template_grid>) and grid_suffix (= template_grid).

# ECHAM grid identifier
export echam_template_grid="T63"

# ICON grid identifier
export icon_template_grid="icon_grid_0005_R02B04_G"

# 1x1 deg regular global grid (CDO built-in descriptor)
export r1x1_template_grid="r360x180"


# --- PROCESSING ---

# Species to process through the regridding pipeline
export variable_names="SO2 BC C2H6S OC"

