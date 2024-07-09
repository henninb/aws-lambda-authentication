import { Enforcer, Config, Res } from "@humansecurity/aws-api-gateway-lambda-authorizer-enforcer";

const pxConfig = require('./config');

// initialize config outside the handler
const config = new Config(pxConfig);

// define an authorizer handler
export const handler = async (req: APIGatewayRequestAuthorizerEvent): Promise<Res> => {
  // create a new enforcer
  const enforcer = new Enforcer(config);
  // call enforce and await the response
  // as early as possible in the Lambda flow
  let response = await enforcer.enforce(req);

  // if a response exists, return it immediately
  // as no further processing is required
  if (response) {
    return response;
  }

  // include your custom authorization logic
  response = {
    principalId: "*",
    policyDocument: {
      Version: "2012-10-17",
      Statement: [
        {
          Action: "execute-api:Invoke",
          Effect: "Allow",
          Resource: req.methodArn
        }
      ]
    },
    context: {}
  };

  // after creating your response, call postEnforce
  await enforcer.postEnforce(req, response);
  // return the response from the handler
  return response;
};
