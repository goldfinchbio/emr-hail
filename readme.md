# Hail on EMR

This repository contains resources for repeatable deployments of [Hail](https://hail.is) on AWS EMR and an [AWS Sagemaker](https://aws.amazon.com/sagemaker/faqs) notebook instance configuration to interaction with the Hail cluster.

## CloudFormation Templates

### hail-s3

This template is deployed once and creates 3 S3 buckets with SSE encryption.

* Hail Bucket - contains VEP cache and configuration JSON for Hail
* Log Bucket - EMR logs will be written here
* SageMaker Jupyter Bucket - Users notebooks will be backed up here, and common/example notebooks will be stored here as well.

### hail-jupyter

This template can be deployed multiple times (one per user).  It will deploy a SageMaker notebook instance for operations against the Hail EMR cluster.  The user's `/home/ec2-user/SageMaker` directory will be backed up via crontab to the SageMaker Jupyter bucket created in the `hail-s3` CloudFormation template.  The user's SageMaker notebook instance will have full S3 CLI control over their respective subdirectory.

For example, if a notebook instance is named `aperry` the user could open a terminal on that instance and have full AWS CLI control on objects under `s3://YOUR_JUPYTER_BUCKET/aperry/`.

When a new SageMaker instance launches it will sync in any scripts in the following directories located in the root of the bucket to the noted locations.

* common-notebooks => /home/ec2-user/SageMaker/common-notebooks
* scripts => /home/ec2-user/SageMaker/bin

You may wish to seed those directories in S3 with the identically named directories under `jupyter` in this repository.  Doing so will allow for a working Hail Plotting example.

### hail-ami

This template leverages [Packer](https://www.packer.io/) in AWS CodeBuild to create AMIs for use with EMR.  You can specify a specific Hail Version, VEP version, and target VPC and subnet.

Review the [expanded documentation](packer/readme.md) for further details.

### hail-emr

This template deploys the EMR cluster using the custom Hail AMI.  There is a single master node and a minimum of 1 core node.   Core node storage size can also be specified as a template parameter.

EMR steps are used to add a location for Livy to output Hail plots directly to files on the master node.   Once written there those plots can be retrieved in the Sagemaker notebook instance and plotted inline.  See the [jupyter/common-notebooks/hail-plotting-example.ipynb](jupyter/common-notebooks/hail-plotting-example.ipynb) for an example.

The plotting pass through is required because the Sparkmagic/Livy can only pass spark and pandas dataframes back to the notebook.

## Deployment Order

For expected results, deploy the templates in the following order.  Resources created by one stack may be used as parameter entries to later stacks.

1. hail-s3.yml
2. hail-jupyter.yml
3. hail-ami.yml
4. hail-emr.yml
