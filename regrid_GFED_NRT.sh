#!/bin/bash
# NOTE: All SLURM resource settings (--job-name, --account, --partition,
# --time, --nodes, --ntasks, --output, --error) live in env.sh and must
# be passed on the sbatch command line, since `#SBATCH` directives can't
# read shell variables:
#
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


source "env.sh" || { echo "ERROR: failed to source env.sh" >&2; exit 1; }

# -----------------------------------------------------------------

#--------------------------------------------------------
# USER ARGS

export YEAR="${1:-}"
export MODE="${2:-}"
# CLEAN selects which directories to wipe before running:
#   all    - clean both output_path and temp_path (default)
#   output - clean only output_path
#   temp   - clean only temp_path
#   none   - clean nothing
export CLEAN="${3:-all}"

if [[ -z "$YEAR" || -z "$MODE" ]]; then
    echo "ERROR: Missing arguments." >&2
    echo "Usage (SLURM): sbatch regrid.sh <YEAR> <MODE> [CLEAN]" >&2
    echo "Usage (local): bash   regrid.sh <YEAR> <MODE> [CLEAN]" >&2
    echo "       (or chmod +x regrid.sh && ./regrid.sh <YEAR> <MODE> [CLEAN])" >&2
    echo "  MODE  must be 'echam' or 'icon'" >&2
    echo "  CLEAN must be 'all' | 'output' | 'temp' | 'none' (default: all)" >&2
    exit 2
fi

if [[ "$MODE" != "echam" && "$MODE" != "icon" ]]; then
    echo "ERROR: Invalid MODE '$MODE'. Must be 'echam' or 'icon'." >&2
    exit 2
fi

case "$CLEAN" in
    all|output|temp|none) ;;
    *)
        echo "ERROR: Invalid CLEAN '$CLEAN'. Must be 'all' | 'output' | 'temp' | 'none'." >&2
        exit 2
        ;;
esac

#--------------------------------------------------------
# MODE-SPECIFIC CONFIG (resolve YEAR-dependent paths)

# Pick the grid template for this mode; derive grid_path and grid_suffix.
if [[ "$MODE" == "echam" ]]; then
    export template_grid="$echam_template_grid"
else
    export template_grid="$icon_template_grid"
fi
export grid_path="${PROJECT_ROOT}/template/${template_grid}"
export grid_suffix="${template_grid}"

# Compose per-mode, per-year paths from the shared roots in env.sh
export input_path="${input_root}/${YEAR}"
export temp_path="${tmp_root}/${MODE}/GFED_NRT/${YEAR}"
export output_path="${output_root}/${MODE}/GFED_NRT/daily/${YEAR}"

mkdir -p "$temp_path" && cd "$temp_path" || exit
mkdir -p "$output_path"

#--------------------------------------------------------
# COMMON CONFIG

export NJOBS=$SLURM_NTASKS
export NJOBS=${NJOBS:-16}
export OMP_NUM_THREADS=$NJOBS

# --- CHECK ---
if [ ! -e "$grid_path" ]; then
    echo "ERROR: Grid template not found: $grid_path" >&2
    exit 1
fi

if [ ! -d "$input_path" ]; then
    echo "ERROR: Input path not found: $input_path" >&2
    exit 1
fi

#--------------------------------------------------------
# FUNCTIONS (shared)

# CORE function: applied per input file
prepare(){
    var="$1"
    input_file="$2"

    cd "$temp_path" || exit 1

    file_name="$(basename "${input_file%.*}")"_"$var"


    # copy the data into the temporary directory
    cp "$input_file" "$file_name".nc

    # attach grid area to the original file
    ncks -A -v grid_area "$input_eco" "$file_name".nc

    # compute emissions / area
    ncap2 -O -s "$var=$var/grid_area" "$file_name".nc "$file_name"_temp.nc 2>/dev/null
    mv "$file_name"_temp.nc "$file_name".nc

    # strip $var 
    ncks -v $var "$file_name".nc "$file_name"_temp.nc
    mv "$file_name"_temp.nc "$file_name".nc

    # convert unit
    ncap2 -O -s "
    ${var}=${var}*1.157407407e-8;
    ${var}@units=\"kg m-2 s-1\";
    " "${file_name}".nc "${file_name}_temp".nc
    mv "$file_name"_temp.nc "$file_name".nc
}
export -f prepare

# merge time, note that the data is processing for a specific year, where the directory's name is depending on the year!
merge() {
    var="$1"

    target_file_name="${target_prefix}_${var}_wildfire_${YEAR}"

    cd "$temp_path" || exit 1

    mapfile -t source_files < <(printf '%s\n' "${input_prefix}"*"${var}".nc | sort)

    cdo -O -selvar,"$var" -mergetime "${source_files[@]}" "$target_file_name".nc
}
export -f merge

#--------------------------------------------------------
# FUNCTIONS (mode-specific)

remap_echam(){
    var=$1
    file_name=${target_prefix}_${var}_wildfire_${YEAR}

    source_file=${temp_path}/${file_name}.nc
    target_file=${output_path}/${file_name}_${grid_suffix}.nc

    cdo -O remapcon,"$grid_path" ${source_file} ${target_file}
    ncrename -v "${var}",emiss_fire ${target_file}
}
export -f remap_echam

remap_icon(){
    cd "$temp_path" || exit 1

    var=$1
    file_name="${target_prefix}_${var}_wildfire_${YEAR}"

    temp_file=${file_name}_temp_$$.nc
    source_file=${file_name}.nc
    target_file=${output_path}/${file_name}_${grid_suffix}.nc

    cdo -b F64 --eccodes -f nc \
        -remapycon,"$grid_path" \
       ${source_file} ${temp_file}

    ncrename -v "${var}",emiss_fire ${temp_file}

    cdo -b F64 -O \
        -setcalendar,standard \
        -setreftime,1800-01-01,00:00:00,days \
        "${temp_file}" \
        "$target_file"

    rm -f "${temp_file}"
}
export -f remap_icon

remap(){
    if [[ "$MODE" == "echam" ]]; then
        remap_echam "$1"
    else
        remap_icon "$1"
    fi
}
export -f remap

# Copy meta data from previous echam emission files
copy_meta(){
    variable=$1
    file_name=${target_prefix}_${variable}_wildfire_${YEAR}
    source_name=emiss_GFAS_${variable,,}_wildfire_2015

    source_file="${meta_template_dir}/${source_name}_T63.nc"
    target_file=${output_path}/${file_name}_${grid_suffix}.nc

    echo $source_file

    varname="code"; type="i";
    value="$(ncdump -h $source_file | grep "emiss_fire:code" | cut -d '=' -f 2 | cut -d ';' -f 1)"
    value="$(echo -e "${value}" | tr -d '[:space:]')"
    ncatted -a $varname,emiss_fire,o,$type,"$value" $target_file

    varname="table"; type="i";
    value="$(ncdump -h $source_file | grep "emiss_fire:table" | cut -d '=' -f 2 | cut -d ';' -f 1)"
    value="$(echo -e "${value}" | tr -d '[:space:]')"
    ncatted -a $varname,emiss_fire,o,$type,"$value" $target_file

    if [[ "$MODE" == "echam" ]]; then
        varname="grid_type"; type="c";
        value="$(ncdump -h $source_file | grep "emiss_fire:grid_type" | cut -d '=' -f 2 | cut -d ';' -f 1)"
        value="$(echo -e "${value}" | tr -d '[:space:]')"
        value="${value//\"}"
        ncatted -a $varname,emiss_fire,o,$type,"$value" $target_file
    fi
}
export -f copy_meta

convert_time(){
    variable=$1
    target_name=${target_prefix}_${variable}_wildfire_${YEAR}_${grid_suffix}

    cd $output_path || exit

    cdo -O -setcalendar,standard -setreftime,1800-01-01,00:00:00,days ${target_name}.nc ${target_name}_time.nc
    mv ${target_name}_time.nc ${target_name}.nc
}
export -f convert_time

#--------------------------------------------------------
# PIPELINE

if [[ "$CLEAN" == "all" || "$CLEAN" == "output" ]]; then
    parallel --jobs $NJOBS rm -rf ::: $output_path/*_${grid_suffix}*.nc
    echo "INFO: All files in $output_path have been deleted."
else
    echo "INFO: Skipping cleanup of $output_path (CLEAN=$CLEAN)."
fi

if [[ "$CLEAN" == "all" || "$CLEAN" == "temp" ]]; then
    parallel --jobs $NJOBS rm -rf ::: $temp_path/*.nc
    echo "INFO: All files in $temp_path have been deleted."
else
    echo "INFO: Skipping cleanup of $temp_path (CLEAN=$CLEAN)."
fi

parallel --jobs $NJOBS prepare {1} {2} ::: $variable_names ::: "$input_path"/*.nc
echo "INFO: All files have been prepared for merging."

parallel --jobs $NJOBS merge ::: $variable_names
echo "INFO: All files have been merged anually."

parallel --jobs $NJOBS remap ::: $variable_names
echo "INFO: All files have been remapped and variables have been renamed to emiss_fire."

parallel --jobs $NJOBS copy_meta ::: $variable_names
echo "INFO: All metadata has been copied."

parallel --jobs $NJOBS convert_time ::: $variable_names
echo "INFO: Time has been converted to days since 1800-01-01 00:00:00."

echo "INFO: Re-gridding done"
