curl -X POST 'https://api.bhenning.com/api-login' -d '{"email": "henninb@gmail.com", "password": "monday1"}'

aws lambda invoke --function-name arn:aws:lambda:us-east-1:423310193800:function:login-function --payload '{"email": "henninb@gmail.com", "password": "monday1"}' response.json


on the api gateway resounce /api-lead
add to the cors headers

origin: https://pages.bhenning.com
headers: x-px-headers,x-px-block
methods: GET,POST,PATCH,OPTIONS


Access Denied add cors headers
origin: https://pages.bhenning.com
headers: x-px-headers,x-px-block
methods: GET,POST,PATCH,OPTIONS


deploy the api after adding the cors
