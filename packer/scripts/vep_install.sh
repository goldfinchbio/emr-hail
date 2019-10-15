#!/bin/bash
#
# VEP
#
# Requirements:
#   HAIL_BUCKET env var must be passed in via packer
#   VEP_VERSION env var must be passed in via packer
#   homo_sapiens VEP cache must exist for both GRCh37 and GRCh38 in $HAIL_BUCKET
#
# Notes:
#   Both homo-sapiens GRCh37 and GRCh38 cache are synced in from s3://$HAIL_BUCKET
#

set -xe

export PERL5LIB="/opt/vep"
GSUTIL_PROFILE="/etc/profile.d/gsutil.sh"
GSUTIL_SOURCE="https://storage.googleapis.com/pub/gsutil.tar.gz"
GSUTIL_TARGET_DIR="/opt"
REPOSITORY_URL="https://github.com/Ensembl/ensembl-vep.git"
export VEP_CACHE_DIR="/opt/vep/cache"
export VEP_S3_SOURCE="s3://$HAIL_BUCKET"
export VEP_S3_CACHE_PATH="/vep/cache"
export VEP_S3_LOFTEE_PATH="/vep/loftee_data"
export VEP_SPECIES="homo_sapiens"
export VEP_DIR="/opt/vep"
export PATH="$PATH:/usr/local/bin"

function install_prereqs {
    yum -y install \
        gcc72-c++ \
        gd-devel \
        expat-devel \
        git \
        mysql55-devel \
        perl-App-cpanminus \
        perl-Env \
        unzip \
        which \
        zlib-devel

    cpanm \
        autodie \
        Compress::Zlib \
        DBD::mysql \
        DBI \
        Digest::MD5 \
        GD \
        HTTP::Tiny \
        Module::Build \
        Try::Tiny

    # Installed alone due to package dependency issues
    cpanm \
        Bio::DB::HTS::Faidx
}

# gsutil used to pull VEP 85 cache from the Broad
function gsutil_install {
  curl "$GSUTIL_SOURCE" | tar --directory "$GSUTIL_TARGET_DIR" -zx
  echo "export PATH=\$PATH:$GSUTIL_TARGET_DIR/gsutil/" >> "$GSUTIL_PROFILE"
}

function vep_install {
    mkdir -p "$VEP_CACHE_DIR"

    # Confirm cache exists in S3
    echo -e "Confirming that the VEP cache exists in $HAIL_BUCKET"
    POP_VEP_S3_CACHE_PATH=$(echo ${VEP_S3_CACHE_PATH#/})  # Remove leading /
    aws s3api head-object --bucket "$HAIL_BUCKET" --key "$POP_VEP_S3_CACHE_PATH/${VEP_SPECIES}_vep_${VEP_VERSION}_GRCh37.tar.gz"
    aws s3api head-object --bucket "$HAIL_BUCKET" --key "$POP_VEP_S3_CACHE_PATH/${VEP_SPECIES}_vep_${VEP_VERSION}_GRCh38.tar.gz"
    # Copy cache archives in, extract, and remove
    aws s3 cp "$VEP_S3_SOURCE$VEP_S3_CACHE_PATH/${VEP_SPECIES}_vep_${VEP_VERSION}_GRCh37.tar.gz" /tmp
    aws s3 cp "$VEP_S3_SOURCE$VEP_S3_CACHE_PATH/${VEP_SPECIES}_vep_${VEP_VERSION}_GRCh38.tar.gz" /tmp

    # Install VEP - the earliest version available from GitHub is 87
    if [ "$VEP_VERSION" -ge 87 ]; then
        cd /opt
        git clone "$REPOSITORY_URL"
        cd ensembl-vep
        git checkout "release/$VEP_VERSION"

        # Auto install (a)pi, (c)ache, and (f)asta GRCh37
        tar --directory "$VEP_CACHE_DIR"  -xf "/tmp/${VEP_SPECIES}_vep_${VEP_VERSION}_GRCh37.tar.gz"
        perl INSTALL.pl --DESTDIR "$VEP_DIR" --CACHEDIR "$VEP_DIR"/cache --CACHEURL "$VEP_CACHE_DIR" \
             --AUTO acf --SPECIES "$VEP_SPECIES" --ASSEMBLY GRCh37 --NO_HTSLIB --NO_UPDATE
        rm "/tmp/${VEP_SPECIES}_vep_${VEP_VERSION}_GRCh37.tar.gz"

        # Auto install (c)ache and (f)asta GRCh38
        tar --directory "$VEP_CACHE_DIR"  -xf "/tmp/${VEP_SPECIES}_vep_${VEP_VERSION}_GRCh38.tar.gz"
        perl INSTALL.pl --DESTDIR "$VEP_DIR" --CACHEDIR "$VEP_DIR"/cache --CACHEURL "$VEP_CACHE_DIR" \
             --AUTO cf --SPECIES "$VEP_SPECIES" --ASSEMBLY GRCh38 --NO_HTSLIB --NO_UPDATE
        rm "/tmp/${VEP_SPECIES}_vep_${VEP_VERSION}_GRCh38.tar.gz"

        # Plugins are installed to $HOME.  Install all plugins, then move to common location
        perl INSTALL.pl --AUTO p --PLUGINS all --NO_UPDATE
        mv "$HOME/.vep/Plugins" "$VEP_DIR"/
    elif [ "$VEP_VERSION" = 85 ]; then
        cpanm CGI
        python -m pip install crcmod
        # Vep 85 comes directly from the Broad Institute via Google Storage
        $GSUTIL_TARGET_DIR/gsutil/gsutil -m cp -r gs://hail-common/vep/vep/loftee "$VEP_DIR"
        $GSUTIL_TARGET_DIR/gsutil/gsutil -m cp -r gs://hail-common/vep/vep/ensembl-tools-release-85 "$VEP_DIR"
        $GSUTIL_TARGET_DIR/gsutil/gsutil -m cp -r gs://hail-common/vep/vep/loftee_data "$VEP_DIR"
        $GSUTIL_TARGET_DIR/gsutil/gsutil -m cp -r gs://hail-common/vep/vep/Plugins "$VEP_DIR"
    fi

    # Loftee for VEP GRCh37 only
    mkdir -p "$VEP_DIR"/loftee_data
    aws s3 sync "$VEP_S3_SOURCE$VEP_S3_LOFTEE_PATH" "$VEP_DIR"/loftee_data
    gunzip "$VEP_DIR"/loftee_data/phylocsf_gerp.sql.gz
}

if [ "$VEP_VERSION" != "none" ]; then
    install_prereqs
    gsutil_install
    vep_install

    # Cleanup
    rm -rf /root/.cpanm
    rm -rf /root/.vep
    rm -rf /root/ensembl-vep
else
    echo "VEP_VERSION environment variable was \"none\".  Skipping VEP installation."
fi
