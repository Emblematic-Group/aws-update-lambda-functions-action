#!/bin/bash

echo "JOB STARTED"

set -e

BRANCH_NAME=$(echo ${GITHUB_REF#refs/heads/})

echo "Check env variables STARTED"

if [[ ! -z "$AWS_FOLDER" ]]; then
    cd $AWS_FOLDER
fi

if [[ -z "$TEMPLATE_S3" ]]; then
    echo "Empty template specified. Looking for s3Stack.yml..."

    if [[ ! -f "s3Stack.yml" ]]; then
        echo s3Stack.yml not found
        exit 1
    fi

    TEMPLATE_S3="s3Stack.yml"
fi

if [[ -z "$TEMPLATE_RDS" ]]; then
    echo "Empty template specified. Looking for rdsStack.yml..."

    if [[ ! -f "rdsStack.yml" ]]; then
        echo rdsStack.yml not found
        exit 1
    fi

    TEMPLATE_RDS="rdsStack.yml"
fi

if [[ -z "$TEMPLATE_LAMBDA" ]]; then
    echo "Empty template specified. Looking for lambdaStack.yml..."

    if [[ ! -f "lambdaStack.yml" ]]; then
        echo lambdaStack.yml not found
        exit 1
    fi

    TEMPLATE_LAMBDA="lambdaStack.yml"
fi

if [[ -z "$AWS_ACCESS_KEY_ID_VALUE" ]]; then
    echo AWS Access Key ID invalid
    exit 1
fi

if [[ -z "$AWS_SECRET_ACCESS_KEY_VALUE" ]]; then
    echo AWS Secret Access Key invalid
    exit 1
fi

if [[ ! -z "$AWS_BUCKET_PREFIX" ]]; then
    AWS_BUCKET_PREFIX="--s3-prefix ${AWS_BUCKET_PREFIX}"
fi


if [[ -z "$AWS_REGION_VALUE" ]]; then
    echo You must define the AWS_REGION_VALUE
    exit 1
fi

if [[ -z "$PGUSER" ]]; then
    echo PGUSER missing
    exit 1
fi

if [[ -z "$PGPASSWORD" ]]; then
    echo PGPASSWORD missing
    exit 1
fi

if [[ -z "$ZC_KEY" ]]; then
    echo ZC_KEY missing
    exit 1
fi

if [[ -z "$ZC_EMAIL" ]]; then
    echo ZC_EMAIL missing
    exit 1
fi

if [[ -z "$REACH_KEY" ]]; then
    echo REACH_KEY missing
    exit 1
fi

if [[ $FORCE_UPLOAD == true ]]; then
    FORCE_UPLOAD="--force-upload"
fi

if [[ $NO_FAIL_EMPTY_CHANGESET == true ]]; then
    NO_FAIL_EMPTY_CHANGESET="--no-fail-on-empty-changeset"
fi

if [[ $USE_JSON == true ]]; then
    USE_JSON="--use-json"
fi

if [[ -z "$CAPABILITIES" ]]; then
    CAPABILITIES="--capabilities CAPABILITY_IAM"
else
    CAPABILITIES="--capabilities $CAPABILITIES"
fi

if [[ ! -z "$PARAMETER_OVERRIDES" ]]; then
    PARAMETER_OVERRIDES="--parameter-overrides $PARAMETER_OVERRIDES"
fi

if [[ ! -z "$TAGS" ]]; then
    TAGS="--tags $TAGS"
fi

mkdir -p ~/.aws
touch ~/.aws/credentials
touch ~/.aws/config

echo "[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID_VALUE
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY_VALUE
region = $AWS_REGION_VALUE" > ~/.aws/credentials

echo "[default]
output = text
region = $AWS_REGION_VALUE" > ~/.aws/config


AWS_STACK_PREFIX=$BRANCH_NAME
STACKS3="${AWS_STACK_PREFIX}-${AWS_REGION_VALUE}-s3"
STACKRDS="${AWS_STACK_PREFIX}-${AWS_REGION_VALUE}-rds"
STACKLAMBDA="${AWS_STACK_PREFIX}-${AWS_REGION_VALUE}-lambda"
AWS_DEPLOY_BUCKET="${AWS_STACK_PREFIX}-${AWS_REGION_VALUE}-packages-bucket"

if [[ -z "$(aws s3api list-buckets --query "Buckets[?Name=='${AWS_DEPLOY_BUCKET}'].Name" --output text)" ]]; then 
    echo "Creating a new s3 to store packages!"
    aws s3 mb s3://$AWS_DEPLOY_BUCKET --region $AWS_REGION_VALUE
fi

echo "Check variables COMPLETED"

#CHECK STACKS DON'T ALREADY EXIST

echo "Check if stack exists STARTED"

CHECK_STACK_S3=$(aws cloudformation describe-stacks \
--region ${AWS_REGION_VALUE} \
--query "Stacks[?StackName=='${STACKS3}'].StackName")

if [[ -z "$CHECK_STACK_S3" ]]; then
    echo "ERROR! The S3 Stack doesn't exist! Deploy it before updating the lambda functions!"
    exit 1
fi

CHECK_STACK_RDS=$(aws cloudformation describe-stacks \
--region ${AWS_REGION_VALUE} \
--query "Stacks[?StackName=='${STACKRDS}'].StackName")

if [[ -z "$CHECK_STACK_RDS" ]]; then
    echo "ERROR! The RDS Stack doesn't exist! Deploy it before updating the lambda functions!"
    exit 1
fi

CHECK_STACK_LAMBDA=$(aws cloudformation describe-stacks \
--region ${AWS_REGION_VALUE} \
--query "Stacks[?StackName=='${STACKLAMBDA}'].StackName")

if [[ -z "$CHECK_STACK_LAMBDA" ]]; then
    echo "ERROR! The Lambda Stack doesn't exist! Deploy it before updating the lambda functions!"
    exit 1
fi

echo "Check if stack exists COMPLETED"

#CREATE PACKAGES

echo "Creation stack package STARTED"


## EVENTUALLY INSTALLING DEPENDENCIES
cd lambda_functions/dependencies/nodejs && npm install && cd ../../..

aws cloudformation package --template-file $TEMPLATE_LAMBDA --output-template-file lambdapackage.yml \
--s3-bucket $AWS_DEPLOY_BUCKET $AWS_BUCKET_PREFIX $FORCE_UPLOAD $USE_JSON


echo "Creation stack package COMPLETED"

#RETRIEVE STACKS' INFOS FOR LAMBDA STACK

echo "Retrieving of s3 and rds stacks' outputs STARTED"

S3NAME=$(aws cloudformation describe-stacks \
  --stack-name $STACKS3 \
  --query "Stacks[0].Outputs[?OutputKey=='S3BucketInstanceName'].OutputValue" \
  --output text
)

S3ARN=$(aws cloudformation describe-stacks \
  --stack-name $STACKS3 \
  --query "Stacks[0].Outputs[?OutputKey=='S3BucketInstanceArn'].OutputValue" \
  --output text
)

RDSADDRESS=$(aws cloudformation describe-stacks \
  --stack-name $STACKRDS \
  --query "Stacks[0].Outputs[?OutputKey=='RDSInstanceAddress'].OutputValue" \
  --output text
)

RDSPORT=$(aws cloudformation describe-stacks \
  --stack-name $STACKRDS \
  --query "Stacks[0].Outputs[?OutputKey=='RDSInstancePort'].OutputValue" \
  --output text
)

echo "Retrieving of s3 and rds stacks' outputs COMPLETED"

#DEPLOY LAMBDA STACK

echo "Deploy lambda stack STARTED"

aws cloudformation deploy --template-file lambdapackage.yml \
--capabilities CAPABILITY_NAMED_IAM --stack-name $STACKLAMBDA \
--parameter-overrides S3StackName=$STACKS3 S3BucketName=$S3NAME S3BucketArn=$S3ARN \
RDSStackName=$STACKRDS RDSInstanceAddress=$RDSADDRESS RDSInstancePort=$RDSPORT \
DB_NAME=$PGUSER DB_USER=$DB_USER DB_PASSWORD=$DB_PASSWORD \
ZC_KEY=$ZC_KEY ZC_EMAIL=$ZC_EMAIL REACH_KEY=$REACH_KEY \
BranchName=$AWS_STACK_PREFIX \
$TAGS $NO_FAIL_EMPTY_CHANGESET

echo "Deploy lambda stack COMPLETED"

#CREATE TRIGGER FOR S3 AND LAMBDA

echo "Creation s3 triggers STARTED"

TRANSCODEARN=$(aws cloudformation describe-stacks \
  --stack-name $STACKLAMBDA \
  --query "Stacks[0].Outputs[?OutputKey=='transcodeVideo'].OutputValue" \
  --output text
)

ONVIDEOARN=$(aws cloudformation describe-stacks \
  --stack-name $STACKLAMBDA \
  --query "Stacks[0].Outputs[?OutputKey=='onVideoTranscoded'].OutputValue" \
  --output text
)

JSON=$(cat <<-EOF
{
    "LambdaFunctionConfigurations": [
        {
            "Id": "transcodeVideo",
            "LambdaFunctionArn": "$TRANSCODEARN",
            "Events": [
                "s3:ObjectCreated:*"
            ],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "prefix",
                            "Value": "inputs/"
                        }
                    ]
                }
            }
        },
        {
            "Id": "onVideoTranscoded",
            "LambdaFunctionArn": "$ONVIDEOARN",
            "Events": [
                "s3:ObjectCreated:*"
            ],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "prefix",
                            "Value": "outputs/"
                        }
                    ]
                }
            }
        }
        ]
}
EOF
)

aws s3api \
  put-bucket-notification-configuration \
  --bucket $S3NAME \
  --notification-configuration "$JSON"

echo "Creation s3 triggers COMPLETED"

#CLEAN PACKAGES
echo "Clean packages STARTED"
rm lambdapackage.yml
echo "Clean packages COMPLETED"

echo "Job COMPLETED"