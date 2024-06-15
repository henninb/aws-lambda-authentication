#!/bin/sh

# Function to check the status of the last executed command
check_status() {
    if [ $? -ne 0 ]; then
        echo "Error: $1"
        exit 1
    fi
}

# Set region and account ID
REGION="us-east-1"
ACCOUNT_ID="423310193800"
FUNCTION_NAME="login-function"
AUTHORIZER_FUNCTION_NAME="authorizer-function"
ROLE_NAME="login-role"
AUTHORIZER_NAME="api-login-authorizer"


cat <<  EOF > "$HOME/tmp/edge-lambda-role.json"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com",
        "Service": "edgelambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Step 1: Create IAM Role
aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://$HOME/tmp/edge-lambda-role.json
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)
check_status "Failed to create IAM Role"

# Step 2: Package and Deploy the Lambda Function
rm -f login.zip
cd ./login-function
npm install
zip -r ../login.zip index.js node_modules/
cd ..
pwd

rm -f authorizer.zip
cd ./authorizer-function
npm install
zip -r ../authorizer.zip index.js node_modules/
cd ..
pwd

if aws lambda get-function --function-name $FUNCTION_NAME 2>/dev/null; then
  echo "Lambda function exists. Proceeding to update code..."
  aws lambda update-function-code --function-name $FUNCTION_NAME --zip-file fileb://login.zip
else
  echo "Lambda function does not exist. Creating..."
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

echo "Publishing the Lambda function '$FUNCTION_NAME'..."
while true; do
  PUBLISH_OUTPUT=$(aws lambda publish-version --function-name $FUNCTION_NAME 2>&1)
  if echo "$PUBLISH_OUTPUT" | grep -q "ResourceConflictException"; then
    echo "Resource conflict detected. Retrying..."
    sleep 5
  else
    break
  fi
done

VERSION=$(echo $PUBLISH_OUTPUT | jq -r '.Version')

if [ -z "$PUBLISH_OUTPUT" ]; then
  echo "Failed to publish the Lambda function '$FUNCTION_NAME'."
  exit 1
fi

if aws lambda get-function --function-name $AUTHORIZER_FUNCTION_NAME 2>/dev/null; then
  echo "Lambda function exists. Proceeding to update code..."
  aws lambda update-function-code --function-name $AUTHORIZER_FUNCTION_NAME --zip-file fileb://authorizer.zip
else
  echo "Lambda function does not exist. Creating..."
  STATUS="Pending"
  while [ "$STATUS" != "Active" ]; do
    aws lambda create-function --function-name $AUTHORIZER_FUNCTION_NAME \
      --runtime nodejs20.x \
      --role "$ROLE_ARN" \
      --handler index.handler \
      --zip-file fileb://authorizer.zip \
      --region "$REGION"
    sleep 5
    STATUS=$(aws lambda get-function --function-name $AUTHORIZER_FUNCTION_NAME | jq -r '.Configuration.State')
    echo "Creation status: $STATUS"

    if [ "$STATUS" = "Failed" ]; then
      echo "Lambda function creation failed."
      exit 1
    fi
  done
fi

echo "Publishing the Lambda function '$AUTHORIZER_FUNCTION_NAME'..."
while true; do
  PUBLISH_OUTPUT=$(aws lambda publish-version --function-name $AUTHORIZER_FUNCTION_NAME 2>&1)
  if echo "$PUBLISH_OUTPUT" | grep -q "ResourceConflictException"; then
    echo "Resource conflict detected. Retrying..."
    sleep 5
  else
    break
  fi
done

VERSION=$(echo $PUBLISH_OUTPUT | jq -r '.Version')

if [ -z "$PUBLISH_OUTPUT" ]; then
  echo "Failed to publish the Lambda function '$FUNCTION_NAME'."
  exit 1
fi
# Step 3: Create the API
API_ID=$(aws apigateway create-rest-api \
    --name api-login2 \
    --description "API for login functionality" \
    --endpoint-configuration types=REGIONAL \
    --query "id" --output text)
check_status "Failed to create API"

# Step 4: Get the Root Resource ID
ROOT_RESOURCE_ID=$(aws apigateway get-resources \
    --rest-api-id "$API_ID" \
    --query "items[?path=='/'].id" --output text)
check_status "Failed to get the Root Resource ID"

# Step 5: Create a new Resource
RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id "$API_ID" \
    --parent-id "$ROOT_RESOURCE_ID" \
    --path-part "api-login2" \
    --query "id" --output text)
check_status "Failed to create a new Resource"

# Step 6: Create a Lambda Authorizer (Ensure you have a Lambda function for this)
AUTHORIZER_LAMBDA_ARN="arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$AUTHORIZER_FUNCTION_NAME"
AUTHORIZER_ID=$(aws apigateway create-authorizer \
    --rest-api-id "$API_ID" \
    --name "$AUTHORIZER_NAME" \
    --type REQUEST \
    --authorizer-uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$AUTHORIZER_LAMBDA_ARN/invocations" \
    --authorizer-result-ttl-in-seconds 0 \
    --query "id" --output text)
check_status "Failed to create Lambda Authorizer"

aws apigateway put-gateway-response \
--rest-api-id "$API_ID" \
--response-type ACCESS_DENIED \
--response-templates 'text/html=$context.authorizer.pxResponseBody,application/json=$context.authorizer.pxResponseBody'
check_status "Failed to create gateway response"

# Step 7: Create a POST Method on the Resource with Authorizer
aws apigateway put-method \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method POST \
    --authorization-type "CUSTOM" \
    --authorizer-id "$AUTHORIZER_ID"
check_status "Failed to create a POST Method on the Resource"

# Step 8: Set up the Integration with the Lambda Function
aws apigateway put-integration \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$FUNCTION_NAME/invocations"
check_status "Failed to set up the Integration with the Lambda Function"

# Step 9: Grant API Gateway Permission to Invoke the Lambda Function
UNIQUE_STATEMENT_ID="apigateway-post-$(date +%s)"
aws lambda add-permission \
    --function-name $FUNCTION_NAME \
    --statement-id "$UNIQUE_STATEMENT_ID" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/POST/api-login2"
check_status "Failed to grant API Gateway Permission to Invoke the Lambda Function"

# Step 10: Grant API Gateway Permission to Invoke the Authorizer Lambda Function
# AUTH_UNIQUE_STATEMENT_ID="apigateway-authorizer-$(date +%s)"
# aws lambda add-permission \
#     --function-name "$FUNCTION_NAME" \
#     --statement-id "$AUTH_UNIQUE_STATEMENT_ID" \
#     --action lambda:InvokeFunction \
#     --principal apigateway.amazonaws.com \
#     --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/authorizers/$AUTHORIZER_ID"
# check_status "Failed to grant API Gateway Permission to Invoke the Authorizer Lambda Function"



AUTH_UNIQUE_STATEMENT_ID="apigateway-authorizer-$(date +%s)"
aws lambda add-permission \
    --function-name "$AUTHORIZER_FUNCTION_NAME" \
    --statement-id "$AUTH_UNIQUE_STATEMENT_ID" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/authorizers/$AUTHORIZER_ID"
check_status "Failed to grant API Gateway Permission to Invoke the Authorizer Lambda Function"

# Step 11: Deploy the API
STAGE_NAME=prod
aws apigateway create-deployment \
    --rest-api-id "$API_ID" \
    --stage-name "$STAGE_NAME"
check_status "Failed to deploy the API"

# Step 12: Call the API
API_URL="https://${API_ID}.execute-api.$REGION.amazonaws.com/${STAGE_NAME}/api-login2"
echo curl -X POST "$API_URL" -H "Authorization: your-auth-token" -d '{"email": "henninb@gmail.com", "password": "monday1"}'
curl -X POST "$API_URL" -H "Authorization: your-auth-token" -d '{"email": "henninb@gmail.com", "password": "monday1"}'

curl -X POST "https://${API_ID}.execute-api.us-east-1.amazonaws.com/prod/api-login2"  -d '{"email": "henninb@gmail.com", "password": "monday1"}'

exit 0
