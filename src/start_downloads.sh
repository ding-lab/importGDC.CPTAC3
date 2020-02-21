#!/bin/bash

# author: Matthew Wyczalkowski m.wyczalkowski@wustl.edu

read -r -d '' USAGE <<'EOF'
Usage: start_downloads.sh [options] UUID [UUID2 ...]

Start import of GDC data

Required arguments:
-S CATALOG: path to Catalog data file. Required 
-O IMPORT_DATAD: path to base of download directory (will write to $IMPORT_DATAD/GDC_import/data). Required
-t TOKEN: token filename.  Required

Options:
-h: print help message
-d: dry run.  This may be repeated (e.g., -dd or -d -d) to pass the -d argument to called functions instead, 
    with each called function called in dry run mode if it gets one -d, and popping off one and passing rest otherwise
-1 : stop after one case processed.
-J NJOBS: Specify number of UUID to download in parallel.  Default 0 runs downloads sequentially
-l LOGD: Log output base directory.  Default: ./logs

Arguments passed to launch_download.sh
-g LSF_ARGS: Additional args to pass to LSF.  LSF mode only
-M: Run in LSF environment (MGI or compute1)
-B: Start docker container, map paths, and run bash instead of starting download
-i IMAGE: docker image to use.  Default mwyczalkowski/importgdc

Arguments passed to download_GDC.sh
-D: Download only, do not index
-I: Index only, do not Download.  DT must be "BAM"
-f: force overwrite of existing data files

All paths passed to this script are relative to host.

If UUID is - then read UUID from STDIN

Catalog file described here: https://github.com/ding-lab/CPTAC3.catalog#cptac3catalogdat
It provides filename and file type for each UUID, which is necessary for processing of BAM files
EOF

source utils.sh
SCRIPT=$(basename $0)
START_TIME=$(date)

while getopts ":S:O:t:hd1J:l:g:MBi:DIf" opt; do
  case $opt in
    S) 
      CATALOG=$OPTARG
      ;;
    O) 
      IMPORT_DATAD="$OPTARG"
      ;;
    t) 
      TOKEN=$OPTARG
      ;;
    h) 
      echo "$USAGE"
      exit 0
      ;;
    d)  # -d is a stack of parameters, each script popping one off until get to -d
      DRYRUN="d$DRYRUN"
      ;;
    1)
      >&2 echo "Will stop after one case"
      JUSTONE=1
      ;;
    J)
      NJOBS=$OPTARG
      MYID=$(date +%Y%m%d%H%M%S)
      ;;
    l)  
      LOGD="$OPTARG"
      XARGS="$XARGS -l $OPTARG"
      ;;
    g) 
      XARGS="$XARGS -g $OPTARG"
      ;;
    M)  
      XARGS="$XARGS -M"
      ;;
    B) 
      XARGS="$XARGS -B"
      ;;
    i) 
      XARGS="$XARGS -i $OPTARG"
      ;;
    D)  
      XARGS="$XARGS -D"
      ;;
    I)  
      XARGS="$XARGS -I"
      ;;
    f)  
      XARGS="$XARGS -f"
      ;;
    \?)
      >&2 echo "Invalid option: -$OPTARG" 
      >&2 echo "$USAGE"
      exit 1
      ;;
    :)
      >&2 echo "Option -$OPTARG requires an argument." 
      >&2 echo "$USAGE"
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))


# Parallel code based on https://github.com/mwyczalkowski/BICSEQ2/blob/master/src/process_cases.sh
function launch_import {
    UUID=$1

    NMATCH=$(grep $UUID $CATALOG | wc -l)
    if [ $NMATCH -ne "1" ]; then
        >&2 echo ERROR: UUID $UUID  matches $NMATCH lines in $CATALOG \(expecting unique match\)
        exit 1;
    fi

    # Columns of SR.dat - Jan2018 update with sample_name
    #     1 sample_name
    #     2 case
    #     3 disease
    #     4 experimental_strategy
    #     5 sample_type
    #     6 samples
    #     7 filename
    #     8 filesize
    #     9 data_format
    #    10 UUID
    #    11 MD5
    FN=$(grep $UUID $CATALOG | cut -f 7)
    DF=$(grep $UUID $CATALOG | cut -f 9)

    if [ -z "$FN" ]; then
        >&2 echo Error: UUID $UUID not found in $CATALOG
        exit 1
    fi

    CMD="bash src/start_downloads.sh $XARGS -t $TOKEN -O $IMPORT_DATAD -p $DF -n $FN  $UUID"

    if [ $NJOBS != 0 ]; then
        JOBLOG="$LOGD/parallel.${UUID}.log"
        test_exit_status
        
        CMD=$(echo "$CMD" | sed 's/"/\\"/g' )   # This will escape the quotes in $CMD 
        CMD="parallel --semaphore -j$NJOBS --id $MYID --joblog $JOBLOG --tmpdir $LOGD \"$CMD\" "
    fi
    run_cmd "$CMD" $DRYRUN
}

confirm $CATALOG
confirm $TOKEN

if [ "$#" -lt 1 ]; then
    >&2 echo Error: Wrong number of arguments
    >&2 echo "$USAGE"
    exit 1
fi

if [ $NJOBS == 0 ] ; then
    >&2 echo Running single case at a time \(single mode\)
else
    >&2 echo Job submission with $NJOBS cases in parallel
fi

# If DRYRUN is 'd' then we're in dry run mode (only print the called function),
# otherwise call the function as normal with one less -d argument than we got
if [ -z $DRYRUN ]; then   # DRYRUN not set
    :   # no-op
elif [ $DRYRUN == "d" ]; then  # DRYRUN is -d: echo the command rather than executing it
    >&2 echo "Dry run in $SCRIPT" 
else    # DRYRUN has multiple d's: strip one d off the argument and pass it to function
    DRYARG=${DRYRUN%?}
    XARGS="$XARGS -$DRYARG"
fi

# this allows us to get UUIDs in one of two ways:
# 1: start_step.sh ... UUID1 UUID2 UUID3
# 2: cat UUIDS.dat | start_step.sh ... -
if [ $1 == "-" ]; then
    UUIDS=$(cat - )
else
    UUIDS="$@"
fi

VAR=( $UUIDS )
N_UUIDS=${#VAR[@]}
UUIDS_SEEN=0

# Loop over all remaining arguments
for UUID in $UUIDS
do
    UUIDS_SEEN=$(($UUIDS_SEEN + 1))
    >&2 echo Processing $UUIDS_SEEN / $N_UUIDS [ $(date) ]: $UUID
    launch_import $UUID
    if [ $JUSTONE ]; then
        break
    fi
done

# this will wait until all jobs completed
if [ $NJOBS != 0 ] ; then
    CMD="parallel --semaphore --wait --id $MYID"
    eval "$CMD"
    test_exit_status
fi

END_TIME=$(date)
>&2 echo Download successfullly completed
>&2 echo Start time: $START_TIME
>&2 echo End time: $END_TIME