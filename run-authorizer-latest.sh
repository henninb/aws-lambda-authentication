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
ACCOUNT_ID="025066251945"
FUNCTION_NAME="lead-function"
AUTHORIZER_FUNCTION_NAME="authorizer-function"
ROLE_NAME="lead-role"
AUTHORIZER_NAME="api-lead-authorizer"
STAGE_NAME=prod
API_NAME="api-lead"
RESOURCE_PATH_PART="api-lead"


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
rm -f lead.zip
cd ./$FUNCTION_NAME
npm install
zip -r ../lead.zip index.js
cd -

rm -f authorizer.zip
cd ./authorizer-function
npm install
esbuild ./index.ts --bundle --minify --sourcemap --platform=node --target=es2020 --outfile=dist/index.js
cp dist/index.js index.js
zip -r ../authorizer.zip index.js node_modules/
cd -

if aws lambda get-function --function-name $FUNCTION_NAME 2>/dev/null; then
  echo "Lambda function exists. Proceeding to update code..."
  aws lambda update-function-code --function-name $FUNCTION_NAME --zip-file fileb://lead.zip
else
  echo "Lambda function does not exist. Creating..."
  STATUS="Pending"
  while [ "$STATUS" != "Active" ]; do
    aws lambda create-function --function-name $FUNCTION_NAME \
      --runtime nodejs20.x \
      --role "$ROLE_ARN" \
      --handler index.handler \
      --zip-file fileb://lead.zip \
      --region "$REGION"
    sleep 5
    echo "aws lambda get-function --function-name $FUNCTION_NAME"
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
    echo "aws lambda get-function --function-name $AUTHORIZER_FUNCTION_NAME"
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

# Check if the API already exists
EXISTING_API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text)

if [ -z "$EXISTING_API_ID" ]; then
  echo "API does not exist. Creating a new API..."
  API_ID=$(aws apigateway create-rest-api \
      --name $API_NAME \
      --description "API for lead functionality" \
      --endpoint-configuration types=REGIONAL \
      --query "id" --output text)
  check_status "Failed to create API"
else
  echo "API exists. Using the existing API ID..."
  API_ID=$EXISTING_API_ID
fi

# exit 1

# Step 3: Create the API
# API_ID=$(aws apigateway create-rest-api \
#     --name api-lead \
#     --description "API for lead functionality" \
#     --endpoint-configuration types=REGIONAL \
#     --query "id" --output text)
# check_status "Failed to create API"
# API_ID=tsiiwsxk84

# Step 4: Get the Root Resource ID
ROOT_RESOURCE_ID=$(aws apigateway get-resources \
    --rest-api-id "$API_ID" \
    --query "items[?path=='/'].id" --output text)
check_status "Failed to get the Root Resource ID"

RESOURCE_ID=$(aws apigateway get-resources --rest-api-id "$API_ID" --query "items[?pathPart=='$RESOURCE_PATH_PART'].id" --output text)

if [ -z "$RESOURCE_ID" ]; then
  echo "Resource does not exist. Creating a new resource..."
  RESOURCE_ID=$(aws apigateway create-resource \
      --rest-api-id "$API_ID" \
      --parent-id "$ROOT_RESOURCE_ID" \
      --path-part "$RESOURCE_PATH_PART" \
      --query "id" --output text)
  check_status "Failed to create a new Resource"
else
  echo "Resource exists. Using the existing Resource ID..."
fi

# Define the Authorizer Lambda ARN
AUTHORIZER_LAMBDA_ARN="arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$AUTHORIZER_FUNCTION_NAME"

# Check if the Lambda Authorizer already exists
AUTHORIZER_ID=$(aws apigateway get-authorizers --rest-api-id "$API_ID" --query "items[?name=='$AUTHORIZER_NAME'].id" --output text)

if [ -z "$AUTHORIZER_ID" ]; then
  echo "Authorizer does not exist. Creating a new Authorizer..."
  AUTHORIZER_ID=$(aws apigateway create-authorizer \
      --rest-api-id "$API_ID" \
      --name "$AUTHORIZER_NAME" \
      --type REQUEST \
      --authorizer-uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$AUTHORIZER_LAMBDA_ARN/invocations" \
      --authorizer-result-ttl-in-seconds 0 \
      --query "id" --output text)
  check_status "Failed to create Lambda Authorizer"
else
  echo "Authorizer exists. Using the existing Authorizer ID..."
fi

# CUSTOM_POLICY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/YourCustomPolicy"
# POLICY_ATTACHED=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query "AttachedPolicies[?PolicyArn=='$CUSTOM_POLICY_ARN'].PolicyArn" --output text)

aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
check_status "Failed to attach policy to lead-role"

aws apigateway put-gateway-response \
--rest-api-id "$API_ID" \
--response-type ACCESS_DENIED \
--response-templates 'text/html=$context.authorizer.pxResponseBody,application/json=$context.authorizer.pxResponseBody'
check_status "Failed to create gateway response"

METHOD_EXISTS=$(aws apigateway get-method --rest-api-id "$API_ID" --resource-id "$RESOURCE_ID" --http-method POST --query "httpMethod" --output text 2>/dev/null)

if [ -z "$METHOD_EXISTS" ]; then
  echo "POST method does not exist. Creating a new POST method with Authorizer..."
  aws apigateway put-method \
      --rest-api-id "$API_ID" \
      --resource-id "$RESOURCE_ID" \
      --http-method POST \
      --authorization-type "CUSTOM" \
      --authorizer-id "$AUTHORIZER_ID"
  check_status "Failed to create a POST Method on the Resource"
else
  echo "POST method already exists. Skipping creation..."
fi


# Check if the POST method already has an integration setup
INTEGRATION_URI="arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$FUNCTION_NAME/invocations"
EXISTING_INTEGRATION_URI=$(aws apigateway get-integration --rest-api-id "$API_ID" --resource-id "$RESOURCE_ID" --http-method POST --query "uri" --output text 2>/dev/null)

if [ "$EXISTING_INTEGRATION_URI" != "$INTEGRATION_URI" ]; then
  echo "Integration does not exist or is different. Setting up the integration with the Lambda Function..."
  aws apigateway put-integration \
      --rest-api-id "$API_ID" \
      --resource-id "$RESOURCE_ID" \
      --http-method POST \
      --type AWS_PROXY \
      --integration-http-method POST \
      --uri "$INTEGRATION_URI"
  check_status "Failed to set up the Integration with the Lambda Function"
else
  echo "Integration already exists. Skipping setup..."
fi

# Step 9: Grant API Gateway Permission to Invoke the Lambda Function
UNIQUE_STATEMENT_ID="apigateway-post-$(date +%s)"
aws lambda add-permission \
    --function-name $FUNCTION_NAME \
    --statement-id "$UNIQUE_STATEMENT_ID" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/POST/api-lead"
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
aws apigateway create-deployment \
    --rest-api-id "$API_ID" \
    --stage-name "$STAGE_NAME"
check_status "Failed to deploy the API"

# Step 12: Call the API
API_URL="https://${API_ID}.execute-api.$REGION.amazonaws.com/${STAGE_NAME}/api-lead"
echo curl -X POST "$API_URL" -d '{ "vin": "1HGCM82633A123456", "color": "red", "name": "John Doe", "email": "john.doe@example.com" }'
curl -X POST "$API_URL" -d '{ "vin": "1HGCM82633A123456", "color": "red", "name": "John Doe", "email": "john.doe@example.com" }'

# curl -X POST "https://${API_ID}.execute-api.us-east-1.amazonaws.com/prod/api-lead"  -d '{"email": "henninb@gmail.com", "password": "monday1"}'
# curl -X POST "https://${API_ID}.execute-api.us-east-1.amazonaws.com/prod/api-lead" -H 'Authorization: your-auth-token' -d '{"email": "henninb@gmail.com", "password": "monday1"}' --user-agent "PhantomJS/123"

echo curl -i -X POST "https://${API_ID}.execute-api.us-east-1.amazonaws.com/prod/api-lead" --user-agent "PhantomJS/123" -d '{ "vin": "1HGCM82633A123456", "color": "red", "name": "John Doe", "email": "john.doe@example.com" }'
curl -i -X POST "https://${API_ID}.execute-api.us-east-1.amazonaws.com/prod/api-lead" --user-agent "PhantomJS/brian123" -d '{ "vin": "1HGCM82633A123456", "color": "red", "name": "John Doe", "email": "john.doe@example.com" }'


echo notabot
curl -X POST "https://${API_ID}.execute-api.$REGION.amazonaws.com/$STAGE_NAME/api-lead" \
-H "Content-Type: application/json" \
-d '{ "vin": "1HGCM82633A123456", "color": "red", "name": "John Doe", "email": "john.doe@example.com" }'

exit 0
