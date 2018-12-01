# Download all samples for a given disease, reference, and experimental strategy

# Plan:
# First, get all CCRC UUIDs in SR file - these are all available hg38 data at GDC
# Next, get all CCRC UUIDs in BamMap - these are the data we have downloaded
# Finally, get the UUIDs which exist in the SR which do NOT exist in BamMap - tehse are the ones we want to download

source gdc-import.config.sh

mkdir -p dat

UUID_ALL="dat/UUID-all.dat"
UUID_LOCAL="dat/UUID-local.dat"
UUID_DOWNLOAD="dat/UUID-download.dat"

if [ !  -e $SR_MASTER ]; then
    >&2 echo Error: $SR_MASTER does not exist
    exit 1
fi
if [ !  -e $BAMMAP_MASTER ]; then
    >&2 echo Error: $BAMMAP_MASTER does not exist
    exit 1
fi

echo SR_MASTER: $SR_MASTER
echo BAMMAP_MASTER: $BAMMAP_MASTER

# SR Columns
#     1  sample_name
#     2  case
#     3  disease
#     4  experimental_strategy
#     5  sample_type
#     6  samples
#     7  filename
#     8  filesize
#     9  data_format
#    10  UUID
#    11  MD5
#    12  reference

# BamMap columns
#     1  sample_name
#     2  case
#     3  disease
#     4  experimental_strategy
#     5  sample_type
#     6  data_path
#     7  filesize
#     8  data_format
#     9  reference
#    10  UUID
#    11  system

# Get all UCEC WGS hg38 data in SR 
awk 'BEGIN{FS="\t";OFS="\t"}{if ($3 == "UCEC" && $4 == "WGS" && $12 == "hg38") print $10}' $SR_MASTER | sort > $UUID_ALL
# Get all UCEC WGS hg38 data in BamMap
awk 'BEGIN{FS="\t";OFS="\t"}{if ($3 == "UCEC" && $4 == "WGS" && $9 == "hg38") print $10}' $BAMMAP_MASTER  | sort > $UUID_LOCAL

# now obtain all UUID which exist in UUID_LOCAL but not UUID_ALL
# recall: `comm -23 A B` returns lines unique in A
comm -23 $UUID_ALL $UUID_LOCAL > $UUID_DOWNLOAD

echo written to $UUID_DOWNLOAD