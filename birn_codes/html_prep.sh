#!/bin/sh

thisdir=`pwd`

# Scan 1
# with -R, "." determines what gets cut off (left) or left on (right)
find ${thisdir}/./dartmouth/ -type d -name scan1\* -exec rsync -Ravz {} ${thisdir}/html/ \;
find ${thisdir}/./colorado/ -type d -name scan1\* -exec rsync -Ravz {} ${thisdir}/html/ \;
find ${thisdir}/./iu/ -type d -name scan1\* -exec rsync -Ravz {} ${thisdir}/html/ \;

# Scan 2
find ${thisdir}/./dartmouth/ -type d -name scan2\* -exec rsync -Ravz {} ${thisdir}/html/ \;
find ${thisdir}/./colorado/ -type d -name scan2\* -exec rsync -Ravz {} ${thisdir}/html/ \;
find ${thisdir}/./iu/ -type d -name scan2\* -exec rsync -Ravz {} ${thisdir}/html/ \;

# vvnbk
find ${thisdir}/./dartmouth/ -type d -name vvnbk -exec rsync -Ravz {} ${thisdir}/html/ \;

# make sure permissions are OK for reading by "other"
find ${thisdir}/html -type f -exec chmod a+r {} \; 
find ${thisdir}/html -type d -exec chmod a+rx {} \;

