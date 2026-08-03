#!/bin/bash
####@ Dependencies:
####@   jq     - https://stedolan.github.io/jq/
####@   iperf3 - client (a reachable iperf3 server is required on the target host)
####@   bc
####@   ping
####@   jp     - JSON terminal chart renderer (used to plot the bitrate chart)
####@ to install jq on OSX using <brew install jq>
####@ to install jq on CentOS:
####@   yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
####@   yum install jq -y
####
#BEGIN -- Configuration
####
BASE="./"
####
#END -- Configuration
####

####
#BEGIN -- Don't touch
####
STORAGE="./"
DIR=$(date +"%m_%d_%Y_%H_%M_%S")
DATE=$(date +"%m/%d/%Y %H:%M:%S")
FILE="benchmark.json"
TMP="temp.json"
BITRATE="bitrate.json"

####
#END -- Don't touch
####

# Verify that every external command this script relies on is installed
check_dependencies()
{
MISSING=""
for cmd in iperf3 jq bc ping jp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING="$MISSING $cmd"
    fi
done

if [ -n "$MISSING" ]; then
    echo "Error: missing required command(s):$MISSING"
    echo "Please install them before running this script."
    exit 1
fi
}

# Validate that a value is a positive integer (used for -i/--intervals and -t/--threads)
is_positive_integer()
{
case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0) return 1 ;;
    *) return 0 ;;
esac
}

do_upload()
{
HOST=$1
TIMES=$2
THREADS=$3

progressBar 10 100
progressBar 20 100
progressBar 30 100

mkdir $BASE$DIR
if [ $? -ne 0 ]; then
    echo
    echo "Error: could not create directory $BASE$DIR"
    exit 1
fi
#to server: every 1 second, tcp size of 500K, 2 times, 5 threads, JSON output
iperf3 -c $HOST -i 1 -w 500K -t $TIMES -P $THREADS -J > $BASE$DIR"/"$FILE
if [ $? -ne 0 ] || [ ! -s $BASE$DIR"/"$FILE ]; then
    echo
    echo "Error: iperf3 upload test failed. Is $HOST reachable and running an iperf3 server?"
    exit 1
fi
progressBar 40 100
progressBar 50 100
progressBar 60 100

#transforming data
#bitrate
cat $BASE$DIR"/"$FILE | jq --compact-output '[.intervals[].streams[]]' > $BASE$DIR"/"$TMP
DATA=$(<$BASE$DIR"/"$TMP)
if [ -z "$DATA" ]; then
    echo
    echo "Error: no interval/stream data found in the iperf3 output."
    exit 1
fi
jq -n --argjson data $DATA '{"benchmark":{"results": $ARGS.named["data"]}}' > $BASE$DIR"/"$BITRATE
rm $BASE$DIR"/"$TMP
progressBar 70 100

#bandwidth
cat $BASE$DIR"/"$FILE | jq --compact-output '.end.sum_sent.bits_per_second' > $BASE$DIR"/"$TMP
BW=$(<$BASE$DIR"/"$TMP)
if [ -z "$BW" ] || [ "$BW" = "null" ]; then
    echo
    echo "Error: could not read bandwidth from the iperf3 output."
    exit 1
fi
BW=$(echo "scale=2; $BW / 1048576"|bc)
rm $BASE$DIR"/"$TMP
progressBar 80 100

#transfer
cat $BASE$DIR"/"$FILE | jq --compact-output '.end.sum_sent.bytes' > $BASE$DIR"/"$TMP
TR=$(<$BASE$DIR"/"$TMP)
if [ -z "$TR" ] || [ "$TR" = "null" ]; then
    echo
    echo "Error: could not read transferred bytes from the iperf3 output."
    exit 1
fi
TR=$(echo "scale=1; $TR / 1048576"|bc)
rm $BASE$DIR"/"$TMP
progressBar 90 100

#latency, with the old ping
ping -c $TIMES $HOST > $BASE$DIR"/"$TMP
if [ ! -s $BASE$DIR"/"$TMP ]; then
    echo
    echo "Error: ping to $HOST produced no output."
    exit 1
fi
LT=$(cat $BASE$DIR"/"$TMP | tail -1| awk '{print $4}' | cut -d '/' -f 2)
TM=$(cat $BASE$DIR"/"$TMP | tail -2| head -1 | awk '{print $1}')
RC=$(cat $BASE$DIR"/"$TMP | tail -2| head -1 | awk '{print $4}')
LS=$(cat $BASE$DIR"/"$TMP | tail -2| head -1 | awk '{for(i=1;i<=NF;i++) if ($i ~ /%$/) print $i}')
rm $BASE$DIR"/"$TMP
progressBar 100 100
echo
echo
echo "-------------------------------------------------"
echo "| BENCHMARK UPLOAD RESULTS: $DATE |"
echo "-------------------------------------------------"
echo
cat $BASE$DIR"/"$BITRATE|jp -y ..bytes -height 25 -width 118
echo
echo "-----------------------------------------------------------------------------------------------------------------------"
echo
echo "Transfer $TR MBytes, Latency $LT ms, Bandwidth $BW Mbits/sec, Transmitted $TM packets, Received $RC packets, Loss $LS"
echo
}

do_download()
{
HOST=$1
TIMES=$2
THREADS=$3

progressBar 10 100
progressBar 20 100
progressBar 30 100

mkdir $BASE$DIR
if [ $? -ne 0 ]; then
    echo
    echo "Error: could not create directory $BASE$DIR"
    exit 1
fi
#to server: every 1 second, tcp size of 500K, 2 times, 5 threads, JSON output
iperf3 -c $HOST -i 1 -w 500K -t $TIMES -P $THREADS -R -J > $BASE$DIR"/"$FILE
if [ $? -ne 0 ] || [ ! -s $BASE$DIR"/"$FILE ]; then
    echo
    echo "Error: iperf3 download test failed. Is $HOST reachable and running an iperf3 server?"
    exit 1
fi
progressBar 40 100
progressBar 50 100
progressBar 60 100

#transforming data
#bitrate
cat $BASE$DIR"/"$FILE | jq --compact-output '[.intervals[].streams[]]' > $BASE$DIR"/"$TMP
DATA=$(<$BASE$DIR"/"$TMP)
if [ -z "$DATA" ]; then
    echo
    echo "Error: no interval/stream data found in the iperf3 output."
    exit 1
fi
jq -n --argjson data $DATA '{"benchmark":{"results": $ARGS.named["data"]}}' > $BASE$DIR"/"$BITRATE
rm $BASE$DIR"/"$TMP
progressBar 70 100

#bandwidth
cat $BASE$DIR"/"$FILE | jq --compact-output '.end.sum_sent.bits_per_second' > $BASE$DIR"/"$TMP
BW=$(<$BASE$DIR"/"$TMP)
if [ -z "$BW" ] || [ "$BW" = "null" ]; then
    echo
    echo "Error: could not read bandwidth from the iperf3 output."
    exit 1
fi
BW=$(echo "scale=2; $BW / 1048576"|bc)
rm $BASE$DIR"/"$TMP
progressBar 80 100

#transfer
cat $BASE$DIR"/"$FILE | jq --compact-output '.end.sum_sent.bytes' > $BASE$DIR"/"$TMP
TR=$(<$BASE$DIR"/"$TMP)
if [ -z "$TR" ] || [ "$TR" = "null" ]; then
    echo
    echo "Error: could not read transferred bytes from the iperf3 output."
    exit 1
fi
TR=$(echo "scale=1; $TR / 1048576"|bc)
rm $BASE$DIR"/"$TMP
progressBar 90 100

#latency, with the old ping
ping -c $TIMES $HOST > $BASE$DIR"/"$TMP
if [ ! -s $BASE$DIR"/"$TMP ]; then
    echo
    echo "Error: ping to $HOST produced no output."
    exit 1
fi
LT=$(cat $BASE$DIR"/"$TMP | tail -1| awk '{print $4}' | cut -d '/' -f 2)
TM=$(cat $BASE$DIR"/"$TMP | tail -2| head -1 | awk '{print $1}')
RC=$(cat $BASE$DIR"/"$TMP | tail -2| head -1 | awk '{print $4}')
LS=$(cat $BASE$DIR"/"$TMP | tail -2| head -1 | awk '{for(i=1;i<=NF;i++) if ($i ~ /%$/) print $i}')
#rm $BASE$DIR"/"$TMP
progressBar 100 100
echo
echo
echo "---------------------------------------------------"
echo "| BENCHMARK DOWNLOAD RESULTS: $DATE |"
echo "---------------------------------------------------"
echo
cat $BASE$DIR"/"$BITRATE|jp -y ..bytes -height 25 -width 118
echo
echo "-----------------------------------------------------------------------------------------------------------------------"
echo
echo "Transfer $TR MBytes, Latency $LT ms, Bandwidth $BW Mbits/sec, Transmitted $TM packets, Received $RC packets, Loss $LS"
echo
}

#BEGIN - MAIN

# Fail fast if a required command is missing
check_dependencies

SEQUENCE="upload"
HOST="localhost"
TIMES=1
THREADS=1

# Loop through arguments and process them
for arg in "$@"
do
    case $arg in
        -m|--man)
        echo "Usage: -h/--host <host>, -i/--intervals <count>, -t/--threads <count>, -d/--sequence (download)"
        exit 1
        ;;
        -d|--sequence)
        SEQUENCE="download"
        shift # Remove -d/--sequence from processing
        ;;
        -h|--host)
        if [ -z "$2" ]; then
            echo "Error: -h/--host requires a value."
            exit 1
        fi
        HOST="$2"
        shift # Remove -h/--host from processing
        shift # Remove host value from processing
        ;;
        -i|--intervals)
        if [ -z "$2" ] || ! is_positive_integer "$2"; then
            echo "Error: -i/--intervals requires a positive integer value."
            exit 1
        fi
        TIMES="$2"
        shift # Remove -i/--intervals from processing
        shift # Remove intervals value from processing
        ;;
        -t|--threads)
        if [ -z "$2" ] || ! is_positive_integer "$2"; then
            echo "Error: -t/--threads requires a positive integer value."
            exit 1
        fi
        THREADS="$2"
        shift # Remove -t/--threads from processing
        shift # Remove threads value from processing
        ;;
    esac
done

# Progress
function progressBar()
{
let _progress=(${1}*100/${2}*100)/100
let _done=(${_progress}*4)/10
let _left=40-$_done

_fill=$(printf "%${_done}s")
_empty=$(printf "%${_left}s")

printf "\rProgress : [${_fill// /#}${_empty// /-}] ${_progress}%%"
}

# Case for functions access
echo
echo "Try to get a benchmarking: type $SEQUENCE, host $HOST, intervals $TIMES, threads $THREADS..."
echo

case $SEQUENCE in
    "download" )
        do_download $HOST $TIMES $THREADS
        ;;
    "upload" )
        do_upload $HOST $TIMES $THREADS
        ;;
esac
#END - MAIN
