#!/bin/bash


time_type="daily"
year="2024"

sample_file="emiss_GFAS_so2_wildfire_2024_T63.nc"

file_my="/projects/0/prjs1474/aarifi/INPUT/aarifi_GFAS_v0006_emissions_inventories_GFAS_CAMS_T63/${time_type}/${year}/$sample_file"
file_other="/projects/0/prjs1474/aarifi/INPUT/v0006/emissions_inventories/GFAS_CAMS/T63/${time_type}/${year}/$sample_file"

out_file=ncdump_echam_${time_type}.txt; :>$out_file
cat >> $out_file <<"EOF"
#####################################
My version 
#####################################

EOF
ncdump -v time $file_my >> $out_file
cat >> $out_file <<"EOF"

#####################################
Anne's version 
#####################################

EOF
ncdump -v time $file_other >> $out_file



