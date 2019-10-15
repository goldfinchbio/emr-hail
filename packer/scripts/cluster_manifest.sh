#!/bin/bash
#
# Generate cluster details and move to S3 for ease of replication
#

export AMI=$(curl -s http://169.254.169.254/latest/meta-data/ami-id/)
export INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id/)
export MANIFEST_S3_BUCKET=$(aws ssm get-parameter --name /hail/s3/hail --query 'Parameter.Value' --output text)
export MANIFEST_S3_PATH="/cluster-manifests/"
MANIFEST_DIRECTORY="/tmp/manifest"

if [ ! -d "$MANIFEST_DIRECTORY" ]; then mkdir -p "$MANIFEST_DIRECTORY"; fi

# Save AMI details
aws ec2 describe-images --image-ids "$AMI" > "$MANIFEST_DIRECTORY/ami.json"

CLUSTER_ID=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
        --query 'Reservations[].Instances[].Tags[?Key==`aws:elasticmapreduce:job-flow-id`].Value' \
        --output text)

# Cluster Details
aws emr describe-cluster --cluster-id "$CLUSTER_ID" > "$MANIFEST_DIRECTORY/cluster.json"

MASTER_SG_ID=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[].Instances[].SecurityGroups[?starts_with(GroupName, `emr-master-`) == `true`].GroupId' \
    --output text)

PARENT_CF_STACK_ID=$(aws ec2 describe-security-groups --group-ids "$MASTER_SG_ID" \
    --query 'SecurityGroups[].Tags[?Key==`aws:cloudformation:stack-id`].Value' \
    --output text)

# CloudFormation Stack Parameters for ease of replication
aws cloudformation describe-stacks --stack "$PARENT_CF_STACK_ID" --query Stacks[*].Parameters[] > "$MANIFEST_DIRECTORY/cloudformation-parameters.json"

# Python list and freeze
for PY in python python3; do
    PY_V=$($PY --version 2>&1| cut -d ' ' -f 2 | sed 's/\./\-/g')
    $PY -m pip list --format=json | jq -r '.' > "$MANIFEST_DIRECTORY/python-${PY_V}_pip-list.json"
    $PY -m pip freeze > "$MANIFEST_DIRECTORY/python-${PY_V}_pip-requirements.txt"
done

# Deliver to S3
aws s3 sync "$MANIFEST_DIRECTORY" "s3://${MANIFEST_S3_BUCKET}${MANIFEST_S3_PATH}${CLUSTER_ID}/"
