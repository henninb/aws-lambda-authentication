const jwt = require('jsonwebtoken');

const EMAIL = 'henninb@gmail.com'; // Replace with your email
const PASSWORD = 'monday1'; // Replace with your password
const JWT_KEY = 'your_jwt_key'; // Replace with your JWT key

const handler = async (event) => {
  const request = JSON.parse(event.body);
  if (request["email"] === EMAIL && request["password"] === PASSWORD) {
    const token = jwt.sign(
      {
        email: request["email"],
        password: request["password"],
        nbf: Math.floor(Date.now() / 1000),
        exp: Math.floor(Date.now() / 1000) + 1 * (60 * 60), // Expires: Now + 1h
      },
      JWT_KEY,
    );

    const jsonResponse = {
      token: token,
    };

    return {
      statusCode: 200,
      body: JSON.stringify(jsonResponse),
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': 'https://www.bhenning.com',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-px-cookies, x-px-block',
        'x-brian': '4',
      },
    };
  } else {
    return {
      statusCode: 403,
      body: JSON.stringify({ message: 'user authorization failure' }),
      headers: { 'content-type': 'application/json' },
    };
  }
};

module.exports = { handler };
