# GDC Import details
## Installation

Scripts here rely on [importGDC.git](/gscuser/mwyczalk/src/importGDC). This is installed as a submodule with command,
```
git clone --recursive https://github.com/ding-lab/importGDC.CPTAC3.b1
mv importGDC.CPTAC3.b1 importGDC.CPTAC3.b2
```

Importing here relies on data file `SR.CPTAC3.b1.dat` generated by [queryGDC.git](https://github.com/ding-lab/queryGDC).  This file is generated at and copied
from `epazote:/Users/mwyczalk/Data/CPTAC3/discover.CPTAC3.b1` 
[Google link](https://drive.google.com/open?id=1-GBKph16nUPtJ0LIMXQgfHqulMEcaA01)

GDC User Token is obtained from GDC and copied to `./token`.
Note that this token expires after some time (one month?) so this process needs to be repeated.  

### `gdc-import.config.sh`
A number of locale-specific variables are defined in `gdc-import.config.sh`:

* `BATCH`
* `IMPORT_DATAD_H`
* `GDC_TOKEN`
* set up `SR` file

#### OLD 

* `DATA_DIR` is where data will be stored; in particular, tokens will be written to $DATA_DIR/token and read data will be written to `$DATA_DIR/GDC_import` 
* `GDC_TOKEN` is path to token file, e.g., `token/gdc-user-token.2017-11-04T01-21-42.215Z.txt`.


## Execution chain

The script `start_batch_import.sh` sources `gdc-import.config.sh` to get paths, and then calls `import_GDC/start_step.sh`.
This in turn calls `import_GDC/GDC_import.sh` which launches the docker container, and executes `import_GDC/process_GDC_uuid.sh` within it.

## LSF Groups

*Specific to MGI*

Using LSF groups to limit download bandwidth; doing max 5 running jobs seems to do the trick.
* Background: https://confluence.gsc.wustl.edu/pages/viewpage.action?pageId=27592450
* Submission script (`start_batch_import.sh`) uses LSF groups if LSF_GROUP environment variable is defined.  Suggested use:
    export LSF_GROUP="/mwyczalk/gdc-download"
* To limit to 5 running jobs: `bgadd -L 5 /mwyczalk/gdc-download`  (this should be a part of a setup script?)
* To examine: `bjgroup -s /mwyczalk/gdc-download`
* To modify, `bgmod -L 2 /mwyczalk/gdc-download`

## Batches

Collections of SR (Submitted Reads, i.e., BAM or FASTQ files) to be processed together.  Here, CPTAC3.b1 is split
into WGS, WXS, and RNA-Seq batches.

## Workflow

Importing in practice tends to be a nonlinear workflow where it may be necessary to track, diagnose, and restart SR import jobs.
To aid in this, we have two tools to track job status and start jobs:
* evaluate_status.sh : check status of download for each SR in batch
* start_step.sh : Start a processing step (import, typically) for given SR UUIDs

Scripts `evaluate_batch_status.sh` and `start_batch_step.sh` are wrappers around importGDC.git scripts which are specific to CPTAC3 Batch 1 work at MGI.
The following command will start import of all WXS samples which have a status of "ready":
```
    export LSF_GROUP="/mwyczalk/gdc-download"
    bash evaluate_batch_status.sh -u -f import:ready WXS | bash start_batch_import.sh -
```
Note that these scripts need to be edited for specific paths, if token changes, etc.

### DC2
TODO: illustrate how downloads started on DC2


## BAM Map

Validation of downloading and indexing, as well as providing summaries of downloaded data, is done with `summarize_batch_import.sh`
Create summaries of all completed RNA-Seq downloads with,
```
    ./evaluate_batch_status.sh -u -f import:completed RNA-Seq.batch.dat | ./summarize_batch_import.sh -H -

```


## Debug procedure and information for MGI downloads

Command to download/index/flagstat one UUID:
```
    bash start_batch_import.sh 59f284e7-cffa-4891-a76c-60dd8e46a01d
```

Testing with UUID `c336c120-966a-4ec0-9fc7-6d5c856bbc22` successful, with .bai and flagstat files created.  Data directory:
    /gscmnt/gc2521/dinglab/mwyczalk/somatic-wrapper-data/GDC_import/data/c336c120-966a-4ec0-9fc7-6d5c856bbc22
Log directory:
    /gscmnt/gc2521/dinglab/mwyczalk/somatic-wrapper-data/GDC_import/import.config/CPTAC3.b2/logs

Note, three preliminary WGS runs need to be fixed:
    * confirm .bam file downloaded
    * confirm filenames names correct
    * index and flagstat
    - 27552a72-0d2c-4307-aefc-1cd193436953
    - 59f284e7-cffa-4891-a76c-60dd8e46a01d
    - e933d585-96d2-4ab6-89b1-2b542d07fa9e


Starting batch download of all WGS ready samples (this can be run in docker-interactive session):
```
export LSF_GROUP="/mwyczalk/gdc-download"
./evaluate_batch_status.sh -u -f import:ready WGS | ./start_batch_import.sh -
```

### Status

Confirm that one download is running at a time.
```
bjgroup -s /mwyczalk/gdc-download
```

Get details of given running job:
```
bjobs -w 5660277
```

Confirm download is going by looking at log:
```
/gscmnt/gc2521/dinglab/mwyczalk/somatic-wrapper-data/GDC_import/import.config/CPTAC3.b2/logs/14c0cb14-71e4-4f26-89f1-349ce26f0bf9.out
```

## DC2 procedures

```
mkdir -p logs
LOG="logs/run1.WGS.log"; ./evaluate_batch_status.sh -f import:ready -u WGS | nohup ./start_batch_import.sh - &>$LOG &
LOG="logs/run1.WXS.log"; ./evaluate_batch_status.sh -f import:ready -u WXS | nohup ./start_batch_import.sh - &>$LOG &
LOG="logs/run1.RNA-Seq.log"; ./evaluate_batch_status.sh -f import:ready -u RNA-Seq | nohup ./start_batch_import.sh - &>$LOG &
```

After full download, should compress logs with,
```
tar -zvcf logs.tar.gz logs; rm -rf logs
```
