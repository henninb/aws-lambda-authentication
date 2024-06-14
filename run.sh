#!/bin/sh

# aws apigateway get-rest-apis
# aws apigateway get-rest-api --rest-api-id ybomoih66b
# aws apigateway create-rest-api --name api-login-test --description "API for login functionality"  --endpoint-configuration types=REGIONAL
FUNCTION_NAME=login-function
ROLE_NAME="login-role"
REGION=us-east-1
ACCOUNT_ID=423310193800

aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://$HOME/tmp/edge-lambda-role.json
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)

rm -f login.zip
cd ./login-function
npm install
zip -r ../login.zip index.js node_modules/
cd -

if aws lambda get-function --function-name $FUNCTION_NAME 2>/dev/null; then
  echo "Lambda function exists. Proceeding to update code..."
  aws lambda update-function-code --function-name $FUNCTION_NAME --zip-file fileb://login.zip
else
  echo "Lambda function does not exist so create one."
   STATUS="Pending"
  while [ "$STATUS" != "Active" ]; do
  aws lambda create-function --function-name $FUNCTION_NAME \
  --runtime nodejs20.x \
  --role "$ROLE_ARN" \
  --handler index.handler \
  --zip-file fileb://login.zip \
  --region "$REGION"
    sleep 5
    STATUS=$(aws lambda get-function --function-name $FUNCTION_NAME | jq -r '.Configuration.State')
    echo "Creation status: $STATUS"

    if [ "$STATUS" = "Failed" ]; then
      echo "Lambda function creation failed."
      exit 1
    fi
  done
fi

# Function to check the status of the last executed command
check_status() {
    if [ $? -ne 0 ]; then
        echo "Error: $1"
        exit 1
    fi
}

# Step 1: Create the API
API_ID=$(aws apigateway create-rest-api \
    --name api-login2 \
    --description "API for login functionality" \
    --endpoint-configuration types=REGIONAL \
    --query "id" --output text)
check_status "Failed to create API"

# Step 2: Get the Root Resource ID
ROOT_RESOURCE_ID=$(aws apigateway get-resources \
    --rest-api-id "$API_ID" \
    --query "items[?path=='/'].id" --output text)
check_status "Failed to get the Root Resource ID"

# Step 3: Create a new Resource
RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id "$API_ID" \
    --parent-id "$ROOT_RESOURCE_ID" \
    --path-part "api-login2" \
    --query "id" --output text)
check_status "Failed to create a new Resource"

# Step 4: Create a POST Method on the Resource
aws apigateway put-method \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method POST \
    --authorization-type "NONE"
check_status "Failed to create a POST Method on the Resource"

# Step 5: Set up the Integration with the Lambda Function
aws apigateway put-integration \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$FUNCTION_NAME/invocations"
check_status "Failed to set up the Integration with the Lambda Function"

# Step 6: Grant API Gateway Permission to Invoke the Lambda Function
UNIQUE_STATEMENT_ID="apigateway-post-$(date +%s)"
aws lambda add-permission \
    --function-name api-login \
    --statement-id "$UNIQUE_STATEMENT_ID" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/POST/api-login2"
check_status "Failed to grant API Gateway Permission to Invoke the Lambda Function"

# Step 7: Deploy the API
STAGE_NAME=prod
aws apigateway create-deployment \
    --rest-api-id "$API_ID" \
    --stage-name "$STAGE_NAME"
check_status "Failed to deploy the API"

# Step 8: Call the API
API_URL="https://${API_ID}.execute-api.$REGION.amazonaws.com/${STAGE_NAME}/api-login2"
echo curl -X POST "$API_URL" -d '{"email": "henninb@gmail.com", "password": "monday1"}'
curl -X POST "$API_URL" -d '{"email": "henninb@gmail.com", "password": "monday1"}'
check_status "Failed to call the API"

exit 0
