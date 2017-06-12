#!/bin/bash

set -e
set -o pipefail

DOWNLOAD_BIN=/home/tim/dev/download/download_wet.sh

# Defaults.
PARALLELJOBS=8

parse_args() {
    # Parse arguments. Taken from
    # https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash.
    # Use -gt 1 to consume two arguments per pass in the loop (e.g. each
    # argument has a corresponding value to go with it).
    # Use -gt 0 to consume one or more arguments per pass in the loop (e.g.
    # some arguments don't have a corresponding value to go with it such
    # as in the --default example).
    while [[ $# -gt 0 ]]; do
        key="$1"

        case $key in
            -u|--url)
                URL="$2"
                shift # past argument
                ;;
            -o|--output-directory)
                OUTDIR="$2"
                shift # past argument
                ;;
            --sshloginfile)
                SSHLOGINFILE="$2"
                shift # past argument
                ;;
            -j|--jobs)
                PARALLELJOBS="$2"
                shift # past argument
                ;;
            -c|--config)
                CONFIGFILE="$2"
                shift # past argument
                ;;
            *)
                # unknown option
                ;;
        esac
        shift # past argument or value
    done

    # TODO: Check wether all necessary command options are provided.

    if [[ ${SSHLOGINFILE} ]]; then
        PARALLEL_OPTIONS="--nice 19 --progress --sshloginfile ${SSHLOGINFILE} -j ${PARALLELJOBS} --wd ${PWD}"
    else
        PARALLEL_OPTIONS="--nice 19 --progress -j ${PARALLELJOBS} --wd ${PWD}"
    fi
}

setup() {
    # Make directory for specified crawl
    mkdir -p "${OUTDIR}"
    cd "${OUTDIR}"

    # Download path file
    wget -nc "${URL}"

    # Convert to HTTPS URLs
    gzip -cd wet.paths.gz | sed 's/^/https:\/\/commoncrawl.s3.amazonaws.com\//' > wet.paths.http

    # Make subdirectories
    for f in $(gzip -cd wet.paths.gz | cut -d '/' -f 4 | sort | uniq); do
        mkdir -p $f
    done
}

count_downloads() {
    TOTAL=0
    DOWNLOADED=0
    for path in $(cat "${OUTDIR}/wet.paths.http"); do
        TOTAL=$((TOTAL+1))
        # TODO: Explain awk expression.
        FILENAME=$(echo $path | awk ' BEGIN { FS = "/" } { print $(NF-2) "/" $(NF)}')
        if [ -f ${FILENAME}.done ]; then
            DOWNLOADED=$((DOWNLOADED+1))
        fi
    done
    DIFFERENCE=$((TOTAL-DOWNLOADED))
    if [[ "$DIFFERENCE" -ne 0 ]]; then
        echo "There are ${DIFFERENCE} files missing/incomplete."
    fi
}

download() {
    cat "${OUTDIR}/wet.paths.http" | parallel ${PARALLEL_OPTIONS} ${DOWNLOAD_BIN}

    echo "Count downloaded files.."
    while [[ $(count_downloads) ]]; do
        echo "Restarting downloads since there are missing files"
        cat "${OUTDIR}/wet.paths.http" | parallel ${PARALLEL_OPTIONS} ${DOWNLOAD_BIN}
        echo "Counting downloaded files.."
    done
    echo "All files downloaded"
}

parse_args $@
setup
download
