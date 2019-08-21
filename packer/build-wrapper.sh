#!/bin/bash
#
# Wraps the build process for validations, etc
#

# TODO: make a build specifically to build new VEP cache base on version
# TODO: validate environment variables before execution

REPOSITORY_URL="https://github.com/hail-is/hail.git"

usage(){
cat <<EOF

  usage: build-wrapper.sh [ARGUMENTS]

    --hail-version  [Number Version]    - OPTIONAL.  If omitted, the current HEAD of master branch will be pulled.
    --vep-version   [Number Version]    - REQUIRED
    --hail-bucket   [S3 Bucket Name]    - REQUIRED
    --var-file      [Full File Path]    - REQUIRED
    --vpc-var-file  [Full File Path]    - REQUIRED

    Example:

   build-wrapper.sh --hail-version 0.2.18 --vep-version 96 --hail-bucket YOUR_HAIL_BUCKET \
    --var-file builds/emr-5.25.0.vars --vpc-var-file builds/vpcs/account123-vpc01.vars

EOF
}

while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        --help)
            usage
            shift
            exit 0
            ;;
        --hail-version)
            HAIL_VERSION="$2"
            shift
            shift
            ;;
        --vep-version)
            VEP_VERSION="$2"
            shift
            shift
            ;;
        --hail-bucket)
            HAIL_BUCKET="$2"
            shift
            shift
            ;;
        --var-file)
            CORE_VAR_FILE="$2"
            shift
            shift
            ;;
        --vpc-var-file)
            VPC_VAR_FILE="$2"
            shift
            shift
            ;;
    esac
done

HAIL_NAME_VERSION="$HAIL_VERSION"  # Used by AMI name

if [ -z "$HAIL_VERSION" ]; then
    HAIL_VERSION=$(git ls-remote "$REPOSITORY_URL" refs/heads/master | awk '{print $1}')
    echo "HAIL_VERSION env var unset.  Setting to HEAD of master branch: $HAIL_VERSION"
    HAIL_NAME_VERSION=master-$(echo "$HAIL_VERSION" | cut -c1-7)
fi

export AWS_MAX_ATTEMPTS=600  # Builds time out with default value
packer build --var hail_name_version="$HAIL_NAME_VERSION" \
             --var hail_version="$HAIL_VERSION" \
             --var vep_version="$VEP_VERSION" \
             --var hail_bucket="$HAIL_BUCKET" \
             --var-file="$CORE_VAR_FILE" \
             --var-file="$VPC_VAR_FILE" \
             amazon-linux.json
