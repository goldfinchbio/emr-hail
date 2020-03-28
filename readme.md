# Hail on EMR

This solution was designed to provide a reproducible, easy to deploy environment to integrate [Hail](https://hail.is) with [AWS EMR](https://aws.amazon.com/emr/faqs/?nc=sn&loc=7).  Where possible, AWS native tools have been used.

![emr-hail_1](docs/images/emr-hail.png)

To integrate Hail and EMR, we leverage [Packer](https://www.packer.io/) from Hashicorp alongside [AWS CodeBuild](https://aws.amazon.com/codebuild/faqs/?nc=sn&loc=5) to create a custom AMI pre-packaged with Hail, and optionally containing the [Variant Effect Predictor (VEP)](https://uswest.ensembl.org/info/docs/tools/vep/index.html).  Then, an EMR cluster is launched using this custom AMI.

Users access Jupyter via a SageMaker notebook hosted in AWS, and pass commands to Hail from the notebook via [Apache Livy](https://livy.incubator.apache.org/).

This repository contains CloudFormation templates, scripts, and sample notebooks which will enable you to deploy this solution in your own AWS account. Certain parts of this repository assume a working knowledge of:  AWS, CloudFormation, S3, EMR, Hail, Jupyter, SageMaker, EC2, Packer, and shell scripting.

The repository is organized into several directories:

- cloudformation - Contains the templates used to deploy resources in AWS
- packer - Documentation and example configuration of Packer (used in the AMI build process)
- jupyter - Sample Jupyter Notebook for SageMaker deployment

This ReadMe will walk through deployment steps, and highlight potential pitfalls.

## Table of Contents

- [Hail on EMR](#hail-on-emr)
  - [Table of Contents](#table-of-contents)
  - [Deployment Guide](#deployment-guide)
  - [CloudFormation Templates](#cloudformation-templates)
    - [hail-s3](#hail-s3)
    - [hail-emr](#hail-emr)
      - [Autoscaling Task Nodes](#autoscaling-task-nodes)
      - [Plotting](#plotting)
      - [SSM Access](#ssm-access)
      - [EFS](#efs)
    - [hail-jupyter](#hail-jupyter)
      - [Optional EFS Access](#optional-efs-access)
    - [hail-ami](#hail-ami)
  - [Public AMIs](#public-amis)
    - [Hail with VEP](#hail-with-vep)
    - [Hail Only](#hail-only)

## Deployment Guide

_Note:  This process will create S3 buckets, IAM resources, AMI build resources, a SageMaker notebook, and an EMR cluster.  These resources may not be covered by the AWS Free Tier, and may generate significant cost.  For up to date information, refer to the [AWS Pricing page](https://aws.amazon.com/pricing/)._

_You will require elevated IAM privileges in AWS, ideally AdministratorAccess, to complete this process._

To deploy Hail on EMR, follow these steps:

1. Log into your AWS account, and access the CloudFormation console

2. Deploy the [hail-s3.yml](#hail-s3) template to create S3 resources, ensuring you use unique names for the S3 buckets

3. Once the `hail-s3` stack deployment completes, deploy the [hail-jupyter.yml](#hail-jupyter) template to create the SageMaker notebook instance

4. At this point you have created S3 buckets, and now have a SageMaker notebook instance you can log into.  You may repeat Step 3 as needed for multiple users.  For more details, see the [hail-jupyter](#hail-jupyter) section below

5. Once the `hail-jupyter` stack deployment completes, deploy the [hail-ami.yml](#hail-ami) template to create the custom AMI build process using CodeBuild and Packer (note that this step is optional if you intend to use the public AMIs listed below)

6. If you do not intend to use the public AMIs, follow the [expanded documentation](packer/readme.md) to create your Hail AMIs

7. Once the AMI build is complete (or you have selected your public AMI), deploy the [hail-emr.yml](#hail-emr) template to create the EMR cluster using a custom Hail AMI.  Note that you _must_ deploy the EMR cluster in the same subnet that you deployed the SageMaker notebook in step 4, otherwise you may run into routing issues

8. After the `hail-emr` stack deployment completes, you may log into the Jupyter notebook and access the Hail cluster

Note that following these steps _in order_ is crucial, as resources created by one stack may be used as parameter entries to later stacks.  For detailed information about individual templates (including troubleshooting), see the following section.

## CloudFormation Templates

This section contains detailed descriptions of the CloudFormation templates discussed in the [Deployment Guide](#deployment-guide).

### hail-s3

This template is deployed _once_.

The template consumes 3 parameters, and creates 3 S3 buckets with [Server-Side Encryption](https://docs.aws.amazon.com/AmazonS3/latest/dev/serv-side-encryption.html) (SSE).

- Hail Bucket - contains VEP cache and configuration JSON for Hail
- Log Bucket - EMR logs will be written here
- SageMaker Jupyter Bucket - Users notebooks will be backed up here, and common/example notebooks will be stored here as well.

*Note: S3 bucket names MUST be unique.  If the S3 bucket name is in use elsewhere, deployment will fail.*

### hail-emr

This template can be deployed _multiple times_ (one per cluster).

This template deploys the EMR cluster using the custom Hail AMI.  There is a single master node, a minimum of 1 core node, and optional autoscaling task nodes.

_Note:  The EMR cluster MUST be deployed in the same subnet as the Jupyter notebook.  Otherwise, you may see ephemeral routing issues._

#### Autoscaling Task Nodes

Task nodes can be set to `0` to omit them.   The target market, `SPOT` or `ON_DEMAND`, is also set via parameters.  If `SPOT` is selected, the bid price is set to the current on demand price of the selected instance type.

The following scaling actions are set by default:

- +2 instances when YARNMemoryAvailablePercentage < 15 % over 5 min
- +2 instances when ContainerPendingRatio > .75 over 5 min
- -2 instances when YARNMemoryAvailablePercentage > 80 % over 15 min

#### Plotting

EMR steps are used to add a location for Livy to output Hail plots directly to files on the master node.   Once written there those plots can be retrieved in the Sagemaker notebook instance and plotted inline.  See the [jupyter/common-notebooks/hail-plotting-example.ipynb](jupyter/common-notebooks/hail-plotting-example.ipynb) for an example.

The plotting pass through is required because the Sparkmagic/Livy can only pass spark and pandas dataframes back to the notebook.

#### SSM Access

The [AWS Systems Manager Agent](https://docs.aws.amazon.com/systems-manager/latest/userguide/ssm-agent.html) can be used to gain ingress to the EMR nodes.  This agent is pre-installed on the AMI.  CloudFormation parameters exist on both the EMR stack and the Jupyter stack to optionally allow notebook IAM roles shell access to the EMR nodes via SSM.  The respective stack parameters must both be set to `true` to allow proper IAM access.

Example connection from Jupyter Lab shell:

![jupyter_ssm_emr_example](docs/images/jupyter_ssm_emr_example.png)

#### EFS

An EFS volume may be used to pass notebooks between the EMR cluster and end users Notebook instances.   EFS IAM access is used to allow notebook users to have read/write to specific File System Access Points (FSAPs).   The EMR cluster then has _read only_ access to these directories.

When creating your EFS volume, use the following File System Policy.  The `elasticfilesystem:NoAction` action is invalid and intentional.  It is required to turn IAM access on for the file system.  Policies on the notebook instances can then be used to grant access. Substitute your file system ARN in the policy below accordingly.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "intentionally-put-invalid-action-to-enable-iam-permissions",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": "elasticfilesystem:NoAction",
            "Resource": "arn:aws:elasticfilesystem:<REGION>:<ACCOUNT_ID>:file-system/<FS-ID>"
        }
    ]
}
```

Use the file system ID as a CloudFormation template parameter to mount the EFS volume on `/efs`.

### hail-jupyter

This template can be deployed _multiple times_ (one per user).

The template deploys a SageMaker notebook instance which will be used for operations against the Hail EMR cluster.  The user's `/home/ec2-user/SageMaker` directory is backed up via crontab to the SageMaker Jupyter bucket created in the previous step with the `hail-s3` CloudFormation template.

The user's notebook instance will have full control via the AWS CLI over their respective S3 subdirectory.  For example, if a notebook instance is named `aperry`, the user has full control of S3 objects in `s3://YOUR_JUPYTER_BUCKET/aperry/` from the terminal on that instance via the AWS CLI.

When a new notebook instance launches, the instance will sync in any scripts in the following directories located in the root of the bucket to the following locations on the local instance:

- `common-notebooks` => `/home/ec2-user/SageMaker/common-notebooks`
- `scripts` => `/home/ec2-user/SageMaker/bin`

You may wish to seed those directories in S3 with the identically named directories under `emr-hail/jupyter` in this repository.  Doing so will allow for a working Hail Plotting example.

CLI Example from repository root directory:

```bash
aws --profile <PROFILE> s3 sync jupyter/ s3://<YOUR_JUPYTER_BUCKET>/ --acl bucket-owner-full-control
```

Post upload, the bucket contents should look similar to this:

```bash
14:16 $ aws --profile <PROFILE> s3 ls --recursive s3://<YOUR_JUPYTER_BUCKET>/
2019-09-30 14:14:36      13025 common-notebooks/hail-plotting-example.ipynb
2019-09-30 14:14:36       1244 scripts/list-clusters
2019-09-30 14:14:36       1244 scripts/ssm
```

#### Optional EFS Access

If your cluster has been configured to mount an EFS volume, you can create [File System Access Points](https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html) (FSAPs) for individual users.  This allows users read/write access to a specific directory on EFS.   The EMR master node mounts the full EFS volume as _read only_ on `/efs`.

A FSAP must be created for each notebook/user.  Because CloudFormation did not have support for FSAP creation when this process was created, the AWS CLI is used.

Use the following steps to create a user specific FSAP.  The UID and GID should remain 500 and 501, respectively, for all users.

- Substitute the EFS file system ID and create the FSAP for user `jsmith`

    ```bash
    aws --profile <YOUR_PROFILE> efs create-access-point \
    --file-system-id <EFS_FS_ID> \
    --posix-user 'Uid=500,Gid=501' \
    --root-directory 'Path=/sagemaker/jsmith,CreationInfo={OwnerUid=500,OwnerGid=501,   Permissions=750}' \
    --tags 'Key=Name,Value=jsmith'
    ```

- Collect the `AccessPointId` from the output of that command.
- Deploy the `hail-jupyter.yml` CloudFormation template.  Use the `AccessPointId` as a value for the **File System Access Point ID** parameter.
- Once the notebook instance has launched, log in and create `/home/ec2-user/SageMaker/custom-user-startup.sh`, mode **700** and add the following script.  Substitute the EFS file system ID and FSAP ID accordingly.

    ```bash
    export EFS_DIRECTORY="/home/ec2-user/SageMaker/efs"
    if [ ! -d "$EFS_DIRECTORY" ]; then mkdir -p "$EFS_DIRECTORY"; fi
    export REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document/ | jq -r '.region')
    sudo yum install -y amazon-efs-utils
    sudo sed -i "s/#region.*$/region = $REGION/" /etc/amazon/efs/efs-utils.conf
    sudo mount -t efs -o iam,tls,accesspoint=<THEIR_FSAP> <EFS_FS_ID> "$EFS_DIRECTORY"
    ```

- Execute the script for the initial setup.  Going forward this script will be run automatically each time the notebook starts.

    ```bash
    bash /home/ec2-user/SageMaker/custom-user-startup.sh
    ```

This completes the notebook EFS configuration.  When the user connects to the EMR master node their files will exist under `/efs/sagemaker/<username>`.

### hail-ami

_Note: Deployment of this template is OPTIONAL.  It is only necessary if you wish to create your own custom AMIs.  [Public AMIs](#public-amis) are published below and can be used in place of this deployment process_

This template is deployed _once_.

Use this template to create your own custom Hail AMI for use with EMR.  Alternatively, instead of deploying this template, you may leverage the [public AMIs](#public-amis) listed below.

This template leverages [Packer](https://www.packer.io/) in AWS CodeBuild to create AMIs for use with EMR.  You can specify a specific Hail Version, VEP version, and target VPC and subnet.

Review the [expanded documentation](packer/readme.md) for further details.

## Public AMIs

Public AMIs are available in specific regions. Select the AMI for your target region and deploy with the noted version of EMR for best results.

### Hail with VEP

| Region    | Hail Version | VEP Version | EMR Version | AMI ID                |
|:---------:|:------------:|:-----------:|:-----------:|:--------------------: |
| us-east-1 | 0.2.32       | 99          | 5.29.0      | ami-070a61a0df447c1f9 |
| us-east-2 | 0.2.32       | 99          | 5.29.0      | ami-0dbbc39e5b74d69fe |
| us-west-2 | 0.2.32       | 99          | 5.29.0      | ami-00ec4cab7cfc07ebc |
| us-east-1 | 0.2.31       | 99          | 5.29.0      | ami-0f51d75d56c8469f7 |
| us-east-2 | 0.2.31       | 99          | 5.29.0      | ami-0ddba7b9f36e79d47 |
| us-west-2 | 0.2.31       | 99          | 5.29.0      | ami-0af36d6360120ea35 |
| us-east-1 | 0.2.29       | 98          | 5.28.0      | ami-0b016dfca524fec33 |
| us-east-2 | 0.2.29       | 98          | 5.28.0      | ami-082b3c5dadecc4a87 |
| us-west-2 | 0.2.29       | 98          | 5.28.0      | ami-0aa2d49e3149759e9 |

### Hail Only

| Region    | Hail Version | EMR Version | AMI ID                |
|:---------:|:------------:|:-----------:|:--------------------: |
| us-east-1 | 0.2.32       | 5.29.0      | ami-081a850d47216fdf9 |
| us-east-2 | 0.2.32       | 5.29.0      | ami-06e96d4a7a55397df |
| us-west-2 | 0.2.32       | 5.29.0      | ami-0c5bedc3759e69114 |
| us-east-1 | 0.2.31       | 5.29.0      | ami-00fbbaf3c6ca73c57 |
| us-east-2 | 0.2.31       | 5.29.0      | ami-0daa264e629449221 |
| us-west-2 | 0.2.31       | 5.29.0      | ami-07fc30be8fe168cdb |
| us-east-1 | 0.2.29       | 5.28.0      | ami-05e440db5d3e3bcba |
| us-east-2 | 0.2.29       | 5.28.0      | ami-064ce48aad3e10749 |
| us-west-2 | 0.2.29       | 5.28.0      | ami-0d8c99d07ae2ebc5b |
