#!/bin/bash

export WIDTH="${1:-1080}"
export HEIGHT="${2:-1920}"

for file in docs/scenario/*.txt
do
	echo "$file"
	if ls ${file/.txt/.mp4} &> /dev/null
	then
		echo "DONE"
       	else
		./tools/record_scenario.sh "${file}" $WIDTH $HEIGHT
	fi 
done
