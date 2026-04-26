# GFED_NRT processing

Pipeline to fetch the GFED NRT daily wildfire emission files and regrid
them onto an ECHAM or ICON grid for use as model input.

## Files

- env.sh                 - shared config (paths, prefixes, modules, creds).
                           Sourced by both scripts.
- fetch_GFED_NRT.sh      - downloads the daily NRT files via SFTP.
- regrid_GFED_NRT.sh     - prepares, merges, remaps and copies metadata
                           for ECHAM or ICON output.
- template/              - grid description files for each target grid.
- grid_area.nc           - per-cell area used to convert totals to fluxes.

## Configuration

Edit `env.sh` to point at your machine:

- `input_root`   - where downloaded files land
- `tmp_root`     - scratch directory used by the regrid pipeline
- `output_root`  - where final regridded files are written
- `MACHINE`      - `snellius` (default) loads the right modules.
                   Set `MACHINE=none` to skip module loading
                   (e.g. when CDO/NCO/parallel come from conda).

`fetch_GFED_NRT.sh` reads `HOST`, `PORT`, `USER` from `env.sh` for SFTP.

## 1. Fetch the data

```
./fetch_GFED_NRT.sh <YEAR>
```

Example:

```
./fetch_GFED_NRT.sh 2025
```

This drops the daily files into `${input_root}/<YEAR>/`.

The pw is given in:
http://globalfiredata.org/ancill/GFED5_SFTP_info.txt

## 2. Regrid

All SLURM resources (job name, account, partition, time, nodes, ntasks,
log dir) live in `env.sh`. They are passed to `sbatch` on the command
line because `#SBATCH` directives can't read shell variables:

```
### ECHAM

source env.sh
YEAR=2025 ; MODE=echam
mkdir -p "$SLURM_LOG_DIR"
sbatch -A "$SLURM_ACCOUNT" -p "$SLURM_PARTITION" \
       --job-name="$SLURM_JOB_NAME" \
       --time="$SLURM_TIME" --nodes="$SLURM_NODES" \
       --ntasks="$SLURM_NTASKS" \
       --output="$SLURM_LOG_DIR/${SLURM_JOB_NAME}_%j.out" \
       --error="$SLURM_LOG_DIR/${SLURM_JOB_NAME}_%j.err" \
       regrid_GFED_NRT.sh "$YEAR" "$MODE"

### ICON

source env.sh
YEAR=2025 ; MODE=icon
mkdir -p "$SLURM_LOG_DIR"
sbatch -A "$SLURM_ACCOUNT" -p "$SLURM_PARTITION" \
       --job-name="$SLURM_JOB_NAME" \
       --time="$SLURM_TIME" --nodes="$SLURM_NODES" \
       --ntasks="$SLURM_NTASKS" \
       --output="$SLURM_LOG_DIR/${SLURM_JOB_NAME}_%j.out" \
       --error="$SLURM_LOG_DIR/${SLURM_JOB_NAME}_%j.err" \
       regrid_GFED_NRT.sh "$YEAR" "$MODE"


```

Or, without SLURM:

```
bash regrid_GFED_NRT.sh <YEAR> <MODE> [CLEAN]
```

Arguments:

- `YEAR`   - year to process (must match a directory under `input_root`)
- `MODE`   - `echam` or `icon`
- `CLEAN`  - optional, what to wipe before running:
    - `all`    (default) - clean both `output_path` and `temp_path`
    - `output` - clean only `output_path`
    - `temp`   - clean only `temp_path`
    - `none`   - clean nothing

Examples:

```
sbatch regrid_GFED_NRT.sh 2025 echam
sbatch regrid_GFED_NRT.sh 2025 icon
bash   regrid_GFED_NRT.sh 2025 echam none
```

## Output

Files are written under
`${output_root}/<MODE>/GFED_NRT/daily/<YEAR>/` and named:

```
emiss_GFED_NRT_<VAR>_wildfire_<YEAR>_<TEMPLATE_GRID>.nc
```

`<TEMPLATE_GRID>` is the value of `echam_template_grid` or
`icon_template_grid` in `env.sh`. Drop in any compatible grid
description file under `template/` and update the variable to
match. Example output filenames with the defaults shipped here:

- echam: `emiss_GFED_NRT_SO2_wildfire_2025_T63.nc`
- icon : `emiss_GFED_NRT_SO2_wildfire_2025_icon_grid_0005_R02B04_G.nc`

Variables processed: `SO2 BC C2H6S OC` (configurable via `variable_names`
in `env.sh`).
