#!/bin/bash
#SBATCH --job-name=regrid_icon
#SBATCH --output=regrid_icon_%j.out
#SBATCH --error=regrid_icon_%j.err
#SBATCH --time=04:00:00
#SBATCH --partition=partition_name
#SBATCH --ntasks=64
#SBATCH --nodes=1
#SBATCH --account=your_account

envtls1


#--------------------------------------------------------
# USER DEFINITION


# --- INPUT ARG ---
export YEAR="${1:-}"
if [[ -z "$YEAR" ]]; then
    echo "ERROR: Missing YEAR argument. Usage: sbatch icon.sh <YEAR>" >&2
    exit 2
fi

# --- PATHS ---

export template_grid="icon_grid_0005_R02B04_G"
export template="/template/${template_grid}.nc"

export temp_path="/tmp/icon_GFED/${YEAR}"; mkdir -p $temp_path; cd $temp_path || exit


# --- INPUT DATA ---
export input_path="/download/Daily/${YEAR}"
export input_eco="grid_area.nc"

# --- OUTPUT DATA --- 
# {name}_{data_version}_{grid}.nb
export output_path="/icon/daily/${YEAR}"
mkdir -p "$output_path"


# --- PARALLELIZATION --- 
export NJOBS=$SLURM_NTASKS
#export NJOBS=64

#--------------------------------------------------------
# CONSTANT DEFINITION

# --- VARIABLES ---
export variable_names="SO2 BC C2H6S OC"

# --- CHECK ---
if [ ! -f "$template" ]; then
    echo "ERROR: Template grid file not found: $template" >&2
    exit 1
fi

if [ ! -d "$input_path" ]; then
    echo "ERROR: Input path not found: $input_path" >&2
    exit 1
fi

# --- NUM PROCESS ---
export OMP_NUM_THREADS=$NJOBS

#--------------------------------------------------------
# FUNCTIONS

prepare(){
    var="$1"
    
    input_file="$2"

    cd "$temp_path" || exit 1
        
    file_name="$(basename "${input_file%.*}")"_"$var"

    cp "$input_file" "$file_name".nc
    
    ncks -A -v grid_area "$input_eco" "$file_name".nc

    # here redirected since the warning resulted from mismatch between nan values from grid_cell and var
    ncap2 -O -s "$var=$var/grid_area" "$file_name".nc "$file_name"_temp.nc 2>/dev/null

    mv "$file_name"_temp.nc "$file_name".nc

    ncks -v $var "$file_name".nc "$file_name"_temp.nc

    mv "$file_name"_temp.nc "$file_name".nc

    ncap2 -O -s "
    ${var}=${var}*1.157407407e-8;
    ${var}@units=\"kg m-2 s-1\";
    " "${file_name}".nc "${file_name}_temp".nc

    mv "$file_name"_temp.nc "$file_name".nc

}
export -f prepare

merge() {
    var="$1"
    
    input_prefix="GFED5NRTspe_CMB"

    target_file_name="emiss_GFED_${var}_wildfire_${YEAR}"
    
    cd "$temp_path" || exit 1

    mapfile -t source_files < <(printf '%s\n' "${input_prefix}"*"${var}".nc | sort)

    cdo -O -selvar,"$var" -mergetime "${source_files[@]}" "$target_file_name".nc
}
export -f merge

remap(){

    cd "$temp_path" || exit 1
    
    var=$1
    file_name="emiss_GFED_${var}_wildfire_${YEAR}"

    temp_file=${file_name}_temp_$$.nc
    source_file=${file_name}.nc
    target_file=${output_path}/${file_name}_${template_grid}.nc

    cdo -b F64 --eccodes -f nc \
        -remapycon,"$template" \
       ${source_file} ${temp_file}

    ncrename -v "${var}",emiss_fire ${temp_file}

    cdo -b F64 -O \
    -setcalendar,standard \
    -setreftime,1800-01-01,00:00:00,days \
    "${temp_file}" \
    "$target_file"

    rm -f "${temp_file}"
}
export -f remap

copy_meta(){
    variable=$1
    file_name=emiss_GFED_${variable}_wildfire_${YEAR}

    source_name=emiss_GFAS_${variable,,}_wildfire_2015
    source_file="/template/2015/${source_name}_T63.nc"
    
    target_file=${output_path}/${file_name}_${template_grid}.nc

    # Extract attributes from the source file variable
    varname="code"; type="i";
    value="$(ncdump -h $source_file | grep "emiss_fire:code" | cut -d '=' -f 2 | cut -d ';' -f 1)"
    # remove leading and trailing whitespaces
    value="$(echo -e "${value}" | tr -d '[:space:]')"
    ncatted -a $varname,emiss_fire,o,$type,"$value" $target_file

    varname="table"; type="i";
    value="$(ncdump -h $source_file | grep "emiss_fire:table" | cut -d '=' -f 2 | cut -d ';' -f 1)"
    value="$(echo -e "${value}" | tr -d '[:space:]')"
    ncatted -a $varname,emiss_fire,o,$type,"$value" $target_file

    # varname="grid_type"; type="c";
    # value="$(ncdump -h $source_file | grep "emiss_fire:grid_type" | cut -d '=' -f 2 | cut -d ';' -f 1)"
    # value="$(echo -e "${value}" | tr -d '[:space:]')"
    # # remove \" from the value
    # value="${value//\"}"
    
    ncatted -a $varname,emiss_fire,o,$type,"$value" $target_file
}
export -f copy_meta

# --------------------------------------------------------
# TEST EXAMPLE (one variable, one day, no GNU parallel)
# Comment out the PRODUCTION block below and uncomment this to test.

: <<"TEST"
test_var="SO2"
export output_path="/projects/0/prjs1474/aarifi/INPUT/aarifi_GFED5p1BETA_2024_GFED5p1NRT_2025_${template_grid}/daily/TEST"
mkdir -p $output_path
test_file=$(ls "$input_path"/*.nc | head -1)
echo "INFO: [TEST] var=$test_var  file=$test_file"
rm -f "$temp_path"/*.nc "$output_path"/*_${template_grid}.nc
prepare "$test_var" "$test_file"
merge   "$test_var"
remap   "$test_var"
copy_meta "$test_var"
echo "INFO: [TEST] Done."
exit 0
TEST

#: <<"CMT"
# --------------------------------------------------------
# PRODUCTION

parallel --jobs $NJOBS rm -rf ::: $output_path/*_${template_grid}.nc
echo "INFO: All files in $output_path have been deleted."
parallel --jobs $NJOBS rm -rf ::: $temp_path/*.nc
echo "INFO: All files in $temp_path have been deleted."

parallel --jobs $NJOBS prepare {1} {2} ::: $variable_names ::: "$input_path"/*.nc
echo "INFO: Prepare the data."
echo "INFO: All files have been prepared for merging."
parallel --jobs $NJOBS merge ::: $variable_names
echo "INFO: All files have been merged anually."
parallel --jobs $NJOBS remap ::: $variable_names
echo "INFO: All files have been remapped and variables have been renamed to emiss_fire."
parallel --jobs $NJOBS copy_meta ::: $variable_names
echo "INFO: All metadata has been copied."
#CMT