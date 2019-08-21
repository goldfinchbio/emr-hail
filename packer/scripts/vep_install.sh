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
S3_MAX_CONCURRENT_REQUESTS="30"
export VEP_CACHE_DIR="/opt/vep/cache"
export VEP_S3_SOURCE="s3://$HAIL_BUCKET"
export VEP_S3_CACHE_PATH="/vep/cache"
export VEP_S3_LOFTEE_PATH="/vep/loftee_data"
export VEP_SPECIES="homo_sapiens"
export VEP_DIR="/opt/vep"

function install_prereqs {
    yum -y install \
        gcc72-c++ \
        git \
        mysql55-devel \
        perl-App-cpanminus \
        unzip \
        which \
        zlib-devel

    cpanm \
        autodie \
        Compress::Zlib \
        DBD::mysql \
        DBI \
        Digest::MD5 \
        HTTP::Tiny \
        Module::Build \
        Try::Tiny
}

# gsutil used to pull VEP 85 cache from the Broad
function gsutil_install {
  curl "$GSUTIL_SOURCE" | tar --directory "$GSUTIL_TARGET_DIR" -zx
  echo "export PATH=\$PATH:$GSUTIL_TARGET_DIR/gsutil/" >> "$GSUTIL_PROFILE"
}

function vep_install {
    mkdir -p "$VEP_CACHE_DIR"

    # Confirm cache exists in S3
    echo -e "Confirming that the VEP cache exists in $HAIL_BUCKET
        $VEP_S3_SOURCE$VEP_S3_CACHE_PATH/$VEP_SPECIES/${VEP_VERSION}_GRCh37/info.txt
        $VEP_S3_SOURCE$VEP_S3_CACHE_PATH/$VEP_SPECIES/${VEP_VERSION}_GRCh38/info.txt"
    POP_VEP_S3_CACHE_PATH=$(echo ${VEP_S3_CACHE_PATH#/})  # Remove leading /
    aws s3api head-object --bucket "$HAIL_BUCKET" --key "$POP_VEP_S3_CACHE_PATH/$VEP_SPECIES/${VEP_VERSION}_GRCh37/info.txt"
    aws s3api head-object --bucket "$HAIL_BUCKET" --key "$POP_VEP_S3_CACHE_PATH/$VEP_SPECIES/${VEP_VERSION}_GRCh38/info.txt"

    aws configure set default.s3.max_concurrent_requests "$S3_MAX_CONCURRENT_REQUESTS"
    aws s3 sync "$VEP_S3_SOURCE$VEP_S3_CACHE_PATH/$VEP_SPECIES/${VEP_VERSION}_GRCh37" "$VEP_CACHE_DIR/$VEP_SPECIES/${VEP_VERSION}_GRCh37"
    aws s3 sync "$VEP_S3_SOURCE$VEP_S3_CACHE_PATH/$VEP_SPECIES/${VEP_VERSION}_GRCh38" "$VEP_CACHE_DIR/$VEP_SPECIES/${VEP_VERSION}_GRCh38"

    # Install VEP - the earliest version available from GitHub is 87
    if [ "$VEP_VERSION" -ge 87 ]; then
        cd /opt
        git clone "$REPOSITORY_URL"
        cd ensembl-vep
        git checkout "release/$VEP_VERSION"
        perl INSTALL.pl --DESTDIR "$VEP_DIR" --CACHEDIR "$VEP_DIR"/cache \
             --AUTO acf --SPECIES "$VEP_SPECIES" --ASSEMBLY GRCh37 --NO_HTSLIB --NO_UPDATE
        perl INSTALL.pl --DESTDIR "$VEP_DIR" --CACHEDIR "$VEP_DIR"/cache \
             --AUTO c --SPECIES "$VEP_SPECIES" --ASSEMBLY GRCh38 --NO_HTSLIB --NO_UPDATE

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

    # Loftee for VEP - set paths appropriately in your Hail vep-configuration.json
    mkdir -p "$VEP_DIR"/loftee_data
    # CRCh37 in link - does this matter?  Ask Adam Tebbe
    # loftee_data below is cached in local s3 bucket for speed
    #aws s3 cp s3://bcbio_nextgen/human_ancestor.fa.gz "$VEP_DIR"/loftee_data
    #curl https://personal.broadinstitute.org/konradk/loftee_data/GRCh37/phylocsf_gerp.sql.gz --output "$VEP_DIR"/loftee_data/phylocsf_gerp.sql.gz
    #gunzip "$VEP_DIR"/loftee_data/phylocsf_gerp.sql.gz
    #curl https://personal.broadinstitute.org/konradk/loftee_data/GRCh37/GERP_scores.final.sorted.txt.gz --output "$VEP_DIR"/loftee_data/GERP_scores.final.sorted.txt.gz

    aws s3 sync "$VEP_S3_SOURCE$VEP_S3_LOFTEE_PATH" "$VEP_DIR"/loftee_data
    gunzip "$VEP_DIR"/loftee_data/phylocsf_gerp.sql.gz
}

install_prereqs
gsutil_install
vep_install

# Cleanup
rm -rf /root/.cpanm
rm -rf /root/.vep
rm -rf /root/ensembl-vep
