#!/bin/bash
#
##  build script for docu with asciidoc and daps
##  (c) 2018 peters@suse.com
#
function usage() {
  echo "Usage: $0 asciidoc_filename_with_extention.adoc"
  exit 1;
}

#check for parameters
if [ $# -eq 0 ]
then
   echo "No arguments supplied."; usage;
   exit 1;
fi

while [ $# -gt 0 ]; do
      case "$1" in
         -h) usage; exit 1;;
         --help) usage; exit 1;;
         --) shift; break;;
         -*) echo >&2 "Error: Invalid option \"$1\"";   echo; usage; exit 1;;
         *) if [ "adoc" != "${1##*.}" ];then echo "ERROR: invalid extension, need .adoc";usage; exit 2;else INPUTFILE=$1; fi;;
      esac
      shift
done


FN=`basename $INPUTFILE .adoc`

mkdir -p ./xml ./build

# get rid of former processing
rm ./xml/$FN.xml

# run asciidoc
asciidoc --doctype=article --backend=docbook --out-file=./xml/$FN.xml ./$INPUTFILE

# create DAPS DC file
cat << EOF > DC-$FN
MAIN="$FN.xml"
STYLEROOT="/usr/share/xml/docbook/stylesheet/suse2013-ns"
EOF

# rund daps and generate PDF
daps -d DC-$FN pdf

# show pdf
evince ./build/$FN/*.pdf
