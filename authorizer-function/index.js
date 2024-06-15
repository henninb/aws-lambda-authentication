const { Enforcer, Config, Res } = require("@humansecurity/aws-api-gateway-lambda-authorizer-enforcer");
const pxConfig = require('./config');

// const pxConfig = {
//   px_app_id: "<APP_ID>",
//   px_cookie_secret: "<COOKIE_SECRET>",
//   px_auth_token: "<AUTH_TOKEN>",
// };

// initialize config outside the handler
const config = new Config(pxConfig);

// define an authorizer handler
exports.handler = async (req) => {
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

// const { Enforcer, Config } = require("@humansecurity/aws-api-gateway-lambda-authorizer-enforcer");
//
// const pxConfig = {
//   px_app_id: "PX123456",
//   px_cookie_secret: "secrete",
//   px_auth_token: "token",
//   // px_custom_first_party_prefix: "/<STAGE_NAME>/<APP_ID_SUFFIX>/"
//   // Add other configuration properties here as needed
// };
//
// // initialize config outside the handler
// const config = new Config(pxConfig);
//
// // define an authorizer handler
// exports.handler = async (req) => {
//   try {
//     // create a new enforcer
//     const enforcer = new Enforcer(config);
//
//     // call enforce and await the response
//     // as early as possible in the Lambda flow
//     let response = await enforcer.enforce(req);
//
//     // if a response exists, return it immediately
//     // as no further processing is required
//     if (response) {
//       return response;
//     }
//
//     // include your custom authorization logic
//     response = {
//       principalId: "*",
//       policyDocument: {
//         Version: "2012-10-17",
//         Statement: [
//           {
//             Action: "execute-api:Invoke",
//             Effect: "Allow",
//             Resource: req.methodArn
//           }
//         ]
//       },
//       context: {}
//     };
//
//     // after creating your response, call postEnforce
//     await enforcer.postEnforce(req, response);
//     // return the response from the handler
//     return response;
//   } catch (error) {
//     console.error("Error in authorizer handler:", error);
//     // Return a valid IAM policy document with a Deny effect in case of an error
//     return {
//       principalId: "*",
//       policyDocument: {
//         Version: "2012-10-17",
//         Statement: [
//           {
//             Action: "execute-api:Invoke",
//             Effect: "Deny",
//             Resource: req.methodArn
//           }
//         ]
//       },
//       context: {}
//     };
//   }
// };
