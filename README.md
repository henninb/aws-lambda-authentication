# AWS Lambda Authentication

An AWS Lambda-based authentication system using API Gateway with a custom authorizer. Includes login, lead capture, and token authorization Lambda functions.

## Architecture

```
Client → API Gateway → Authorizer Lambda (validates token)
                    → Login Lambda (issues token)
                    → Lead Lambda (protected endpoint)
```

## Functions

| Directory | Description |
|-----------|-------------|
| `login-function/` | Handles user login and returns a token |
| `authorizer-function/` | Custom Lambda authorizer that validates tokens |
| `lead-function/` | Protected endpoint example |

## Login Endpoint

```bash
curl -X POST 'https://api.bhenning.com/api-login' \
  -d '{"email": "user@example.com", "password": "yourpassword"}'
```

## Invoke Directly

```bash
aws lambda invoke \
  --function-name arn:aws:lambda:us-east-1:<account-id>:function:login-function \
  --payload '{"email": "user@example.com", "password": "yourpassword"}' \
  response.json
```

## API Gateway CORS

Add these headers to the API Gateway resource:

- **Origin**: `https://pages.bhenning.com`
- **Headers**: `x-px-headers,x-px-block`
- **Methods**: `GET,POST,PATCH,OPTIONS`

## IAM Permissions

See `LambdaAuthorizerPolicy.json` for the required IAM policy. Permission files (`permission.json`, `permission-2.json`, etc.) contain resource-based policies for cross-service invocation.

## Related

- [aws-lambda-api](../aws-lambda-api) — Transaction Lambda API
