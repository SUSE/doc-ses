#!/bin/bash
#
# Purpose:
#   Convert manpages from upstream source
#
# First source: https://github.com/ceph/ceph/blob/octopus/doc/man/8/ceph-volume.rst
#
# Second source: https://github.com/nfs-ganesha/nfs-ganesha/tree/V3.3/src/doc/man
#  (all of theseeee)
#
# Author: Tom Schraitle
# Date:  October 2020

ME=${0##*/}
THISDIR=${0%/*}

# Sources of manpages in RST format to convert to DocBook5:
GITHUB_URL="https://github.com/nfs-ganesha/nfs-ganesha.git"
ADDITIONAL_URL="https://github.com/ceph/ceph/raw/octopus/doc/man/8/ceph-volume.rst"

# Template directory, used by mktemp
TEMPDIR_PATH="/tmp/nfs-ganesha-XXXXX"

# Real directory, filled after calling mktemp or passing it through -g/--gitdir option:
TEMPDIR=""

# Relative source path from the cloned GitHub repo:
SRC_MANPAGE_DIR="src/doc/man"

# Relative destination path to write all results:
DEST_MANPAGE_DIR="manpages"

# Helper stylesheet to fine-tune raw XML from pandoc:
XSLT="xslt/fix-manpages.xsl"

# Verbosity level:
VERBOSE=0

function exit_on_error {
    echo -e "ERROR: $1" >&2
    exit 1;
}

function dump {
    if [[ "$VERBOSE" -ne 0 ]]; then
        echo "$1"
    fi
    # echo "$1" 2>&1
}

function usage {
    cat <<EOF_helptext
Usage: $ME [OPTIONS] OUTPUTDIR

Converts RST manpages into DocBook5 files. These sources are investigated:

* $GITHUB_URL
* $ADDITIONAL_URL

The script does the following steps:

  1. Check if all necessary programs are installed. If not, show help text.
  2. Clone the repository (or use the directory from last run).
  3. Download additional manpages.
  4. Remove any ":orphan:" lines from RST (this complicates the conversion process).
  5. Convert RST to DocBook5 with pandoc.
  6. Fix the raw XML file from pandoc, write it to result directory.

Done! :)

Options:
  -h, --help     Shows this help text
  -v, -verbose   Makes output more verbose
  -g, --gitdir   Use cloned GH directory from previous run

Arguments:
  OUTPUTDIR      Directory where result is written (use "manpages")

Author: Thomas Schraitle, October 2020
EOF_helptext
}

function prerequisites() {
    # Check assumptions
    #
    local PROGRAMS="git pandoc xsltproc"
    dump " Checking if $PROGRAMS are available."
    for prog in $PROGRAMS; do
        which $prog 2>&1
        [[ 0 -ne $? ]] && exit_on_error "Program $prog not found. Try 'cnf $prog' and install the package."
    done
}

function clone-repo() {
    # Clone the GitHub repo into a temporary path
    #
    TEMPDIR=$(mktemp --directory ${TEMPDIR_PATH})
    dump "  Clone GitHub repo and download additional RST file"
    git clone $GITHUB_URL $TEMPDIR
    wget --directory-prefix=$TEMPDIR/$SRC_MANPAGE_DIR $ADDITIONAL_URL
}

function rm-orphan-line() {
    # Remove .. orphan in first line
    # Synopsis:
    #   rm-orphan-line FILE
    #
    local FILE="$1"
    dump "  Remove any :orphan: lines"
    sed -i 's/:orphan://g' ${FILE}
}

function add-ns() {
    # Add XLink namespace into first root element
    # Synopsis:
    #  add-ns FILE
    #
    local FILE="$1"
    dump "  Add XLink namespace"
    sed -i 's#<section #<section xmlns:xlink="http://www.w3.org/1999/xlink" #' ${FILE}
}

function convert-to-docbook5() {
    # Convert a single RST file into DocBook5
    # Synopsis:
    #   convert-to-docbook5 INPUT_RST OUTPUT_XML
    #
    # Requisite: No :orphan: is available in RST
    local FILE="$1"
    local BASE="${1##*/}"
    local DIR="${1}"
    local OUTDIR="${2}"
    local OUT="$OUTDIR/${BASE%*.rst}.xml"
    dump "  Convert RST into DocBook"
    pandoc --from=rst --to=docbook5 ${FILE} -o ${OUT}
}

function fix-manpage() {
    # Fix issue after converting with pandoc
    # Synopsis:
    #  fix-manpage XML_FROM_RST  OUTPUTDIR
    #
    local FILE="$1"
    local BASE="${1##*/}"
    local DIR="${1}"
    local OUTDIR="${2}"
    local OUTFILE="$OUTDIR/$BASE"
    dump "  Fix raw DocBook document from pandoc..."
    xsltproc -o "$OUTFILE" "$THISDIR/$XSLT" "$FILE"
}

export POSIXLY_CORRECT=1
ARGS=$(getopt -o "hvg:" -l "help,verbose,gitdir:" -n "$ME" -- "$@")

eval set -- "$ARGS"

while true; do
    case "$1" in
        -h|--help)
            usage
            exit 1
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -g|--gitdir)
            TEMPDIR="$2"
            shift 2
            ;;
        --)
            shift
            break;;
        *) exit_on_error "Internal error!" ;;
    esac
done

unset POSIXLY_CORRECT

## Check for errors
if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi


[[ -d $THISDIR/$DEST_MANPAGE_DIR ]] || mkdir $THISDIR/$DEST_MANPAGE_DIR

prerequisites

if [[ -e "$TEMPDIR" ]]; then
    dump "* Using $TEMPDIR from previous run."
else
    dump "* Cloning GitHub reposity..."
    clone-repo
fi

dump "* Looking into $TEMPDIR/$SRC_MANPAGE_DIR for RST files..."
for file in $TEMPDIR/$SRC_MANPAGE_DIR/*.rst; do
  dump "- $file"
  rm-orphan-line $file
  convert-to-docbook5 $file $TEMPDIR/$SRC_MANPAGE_DIR || exit_on_error "Problems with RST -> DB conversion with $file"
  add-ns "${file%*.rst}.xml"
  fix-manpage "${file%*.rst}.xml" $THISDIR/$DEST_MANPAGE_DIR
done

echo "Done"
echo "Find your results in '$DEST_MANPAGE_DIR'"
