curl -X POST 'https://api.bhenning.com/api-login' -d '{"email": "henninb@gmail.com", "password": "monday1"}'

aws lambda invoke --function-name arn:aws:lambda:us-east-1:423310193800:function:login-function --payload '{"email": "henninb@gmail.com", "password": "monday1"}' response.json
