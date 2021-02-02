# aws-update-lambda-functions-action

This action must be used when you want to update the lambda functions. It will fails if the stacks (s3, rds and lambdas) don’t exist.

## Example workflows file
```yaml
name: "update_lambda_stack"
on:
  workflow_dispatch:
    branches:
    - awsstaging
    - awsproduction
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v1
    - uses: Emblematic-Group/aws-update-lambda-functions-action@main
      env:
        AWS_FOLDER: 'aws_cf_stack'
        AWS_REGION_VALUE: 'eu-north-1'
        AWS_ACCESS_KEY_ID_VALUE: ${{ secrets.AWS_ACCESS_KEY_ID_S3USER }}
        AWS_SECRET_ACCESS_KEY_VALUE: ${{ secrets.AWS_SECRET_ACCESS_KEY_S3USER }}
```

## Example break-down
This actions can be triggered only from the Action tab since it is a workflow_dispatch.

The only branch allowed to dispatch this action is awsstaging and awsproduction.

### Steps:
- actions/checkout@v1 is used to allow the action to pull the repo
- Emblematic-Group/aws-update-lambda-functions-action@main runs AWS CLI/SAM commands to update the lambda functions.

### Env variables
- AWS_FOLDER, which is the path to the folder in the repo where you can find the SAM templates
- AWS_STACK_PREFIX, will be the prefix for all the three stacks. By default is the branch name and is retrieved in the second step
- AWS_REGION_VALUE is the region where to deploy the resources
- AWS_ACCESS_KEY_ID_VALUE and AWS_SECRET_ACCESS_KEY_VALUE are credentials of the IAM AWS user used to login on AWS Cli


### Second step summary
- Checks whether the env variables are initialized
- Confirms the stacks (s3, rds, lambda) exist
- Retrieves RDS endpoint and port and S3 bucket name then deploys the lambda stack and apply the triggers to S3. The names of s3 and rds stacks are retrieved by the AWS_STACK_PREFIX and by appending “s3” or “rds”.
- Deletes the packages as a clean up
