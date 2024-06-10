#!/bin/sh

# aws apigateway get-rest-apis
# aws apigateway get-rest-api --rest-api-id ybomoih66b
# aws apigateway create-rest-api --name api-login-test --description "API for login functionality"  --endpoint-configuration types=REGIONAL

# Step 1: Create the API
API_ID=$(aws apigateway create-rest-api \
    --name api-login2 \
    --description "API for login functionality" \
    --endpoint-configuration types=REGIONAL \
    --query "id" --output text)

# Step 2: Get the Root Resource ID
ROOT_RESOURCE_ID=$(aws apigateway get-resources \
    --rest-api-id $API_ID \
    --query "items[?path=='/'].id" --output text)

# Step 3: Create a new Resource
RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $ROOT_RESOURCE_ID \
    --path-part "api-login" \
    --query "id" --output text)

# Step 4: Create a POST Method on the Resource
aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --authorization-type "NONE"
exit 1


# Step 5: Set up the Integration with the Lambda Function
aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri 'arn:aws:apigateway:{region}:lambda:path/2015-03-31/functions/arn:aws:lambda:{region}:{account-id}:function:api-login/invocations'

# Step 6: Grant API Gateway Permission to Invoke the Lambda Function
aws lambda add-permission \
    --function-name api-login \
    --statement-id apigateway-post \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:{region}:{account-id}:$API_ID/*/POST/api-login"

exit 0
