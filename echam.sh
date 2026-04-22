#!/bin/bash
#SBATCH --job-name=regrid_echam
#SBATCH --output=regrid_echam_%j.out
#SBATCH --error=regrid_echam_%j.err
#SBATCH --time=04:00:00
#SBATCH --partition=partition_name
#SBATCH --ntasks=64
#SBATCH --nodes=1
#SBATCH --account="your account"

envtls1

export gird_path="/template/T63"

export temp_path="/tmp/echam_GFED/${YEAR}"; mkdir -p $temp_path; cd $temp_path || exit

export YEAR="${1:-}"

if [[ -z "$YEAR" ]]; then
    echo "ERROR: Missing YEAR argument. Usage: sbatch regrid.sh <YEAR>" >&2
    exit 2
fi

export NJOBS=$SLURM_NTASKS
export NJOBS=64
# --- INPUT ---

export input_path="/download/Daily/${YEAR}"
export input_eco="grid_area.nc"


# --- OUTPUT ---

export output_path="/echam/daily/${YEAR}"
mkdir -p $output_path

# --- VARIABLES ---
export variable_names="SO2 BC C2H6S OC"


# --- CHECK ---

# check if grid files exist
if [ ! -f "$gird_path" ]; then
    exit 1
fi


# --- PROCESS ---

export OMP_NUM_THREADS=$NJOBS

# filename is here defined as like emiss_GFED_NRT_bc_wildfire_2000_T63.nc but without _T63.nc

# change_unit(){
#     variable=$1
#     target_name=emiss_GFED_NRT_${variable}_wildfire_${YEAR}_T63
#     cd $output_path || exit
#     mv ${target_name}_unit.nc ${target_name}.nc
# }
# export -f change_unit


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
    
    input_prefix="GFED5eNRTspe_CMB"

    target_file_name="emiss_GFED_NRT_${var}_wildfire_${YEAR}"
    
    cd "$temp_path" || exit 1

    mapfile -t source_files < <(printf '%s\n' "${input_prefix}"*"${var}".nc | sort)

    cdo -O -selvar,"$var" -mergetime "${source_files[@]}" "$target_file_name".nc
}
export -f merge

remap(){
    var=$1
    file_name=emiss_GFED_NRT_${var}_wildfire_${YEAR}

    source_file=${temp_path}/${file_name}.nc
    target_file=${output_path}/${file_name}_T63.nc

    cdo -O remapcon,"$gird_path" ${source_file} ${target_file}

    ncrename -v "${var}",emiss_fire ${target_file}
}
export -f remap


delete_meta(){
    file_name=$1
    target_file=${output_path}/${file_name}_T63.nc
    
    # Extract all attribute names for the variable
    ncdump -h $target_file | grep -A10 "variables:$variable_name" | grep ':' | cut -d ':' -f 1 | xargs -I {} echo {} > attr_list_$file_name.txt

    # Delete each attribute
    while read attr_name; do
        ncatted -a $attr_name,$variable_name,d,, $target_file
    done < attr_list_$file_name.txt

    # Clean up
    rm attr_list_$file_name.txt

    echo "All metadata for $variable_name has been deleted in $target_file."
}
export -f delete_meta

copy_meta(){
    variable=$1
    file_name=emiss_GFED_NRT_${variable}_wildfire_${YEAR}
    source_name=emiss_GFAS_${variable,,}_wildfire_2015

    source_file="/template/2015/${source_name}_T63.nc"
    target_file=${output_path}/${file_name}_T63.nc

    echo $source_file

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

    varname="grid_type"; type="c";
    value="$(ncdump -h $source_file | grep "emiss_fire:grid_type" | cut -d '=' -f 2 | cut -d ';' -f 1)"
    value="$(echo -e "${value}" | tr -d '[:space:]')"
    # remove \" from the value
    value="${value//\"}"
    
    ncatted -a $varname,emiss_fire,o,$type,"$value" $target_file
}
export -f copy_meta


convert_time(){
    variable=$1
    target_name=emiss_GFED_NRT_${variable}_wildfire_${YEAR}_T63

    cd $output_path || exit

    cdo -O -setcalendar,standard -setreftime,1800-01-01,00:00:00,days ${target_name}.nc ${target_name}_time.nc
    mv ${target_name}_time.nc ${target_name}.nc
}
export -f convert_time


add_gfire(){
    variable=$1
    target_name=emiss_GFED_NRT_${variable}_wildfire_${YEAR}_T63

    cd $output_path || exit
    cdo mulc,0 ${target_name}.nc ${target_name}_gfire.nc
    cdo chname,emiss_fire,gfire ${target_name}_gfire.nc ${target_name}_gfire_chname.nc
    cdo -O merge ${target_name}.nc ${target_name}_gfire_chname.nc ${target_name}'_modified.nc'
    rm -rf ${target_name}_gfire.nc ${target_name}_gfire_chname.nc
}
export -f add_gfire


# include selvar as well 

# parallel --jobs $NJOBS remap ::: $file_names
# clean 
parallel --jobs $NJOBS rm -rf ::: $output_path/*_T63*.nc
echo "INFO: All files in $output_path have been deleted."
parallel --jobs $NJOBS rm -rf ::: $temp_path/*.nc
echo "INFO: All files in $temp_path have been deleted."

# --- FOR TESTING ---
:<< 'TEST'
variable_names=SO2
parallel prepare {1} {2} ::: $variable_names ::: /projects/0/prjs1474/aarifi/INPUT/process_GFED_NRT/download/Daily/${YEAR}/*2025-01-*
TEST
parallel prepare {1} {2} ::: $variable_names ::: /projects/0/prjs1474/aarifi/INPUT/process_GFED_NRT/download/Daily/${YEAR}/*

echo "INFO: All files have been prepared for merging."
parallel --jobs $NJOBS merge ::: $variable_names
echo "INFO: All files have been merged anually."
parallel --jobs $NJOBS remap ::: $variable_names
echo "INFO: All files have been remapped and variables have been renamed to emiss_fire."
parallel --jobs $NJOBS copy_meta ::: $variable_names
echo "INFO: All metadata has been copied."
parallel --jobs $NJOBS convert_time ::: $variable_names
echo "INFO: Time has been converted to days since 1800-01-01 00:00:00."
#parallel --jobs $NJOBS change_unit ::: $variable_names
#echo "INFO: Changed untis g m-2 day-1 -> kg m-2 s-1"
parallel --jobs $NJOBS add_gfire ::: $variable_names
echo "INFO: gfire has been added to all files."
