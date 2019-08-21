#!/bin/bash
#
# samtools requires htslib
#

set -xe

REPOSITORY_URL="https://github.com/samtools/samtools.git"
HTSLIB_DIR="/opt/htslib"

yum -y install \
    autoconf \
    gcc72 \
    git \
    ncurses-devel

if [ -z "$SAMTOOLS_VERSION" ]; then
    SAMTOOLS_VERSION="master";
    echo "SAMTOOLS_VERSION was empty.  Setting to master."
fi

mkdir -p /opt
cd /opt
git clone "$REPOSITORY_URL"
cd samtools
git checkout "$SAMTOOLS_VERSION"
autoheader
autoconf -Wno-syntax
./configure --with-htslib="$HTSLIB_DIR"
make -j "$(grep -c ^processor /proc/cpuinfo)"
make install

rm -rf /opt/samtools
