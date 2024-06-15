exports.handler = async (event) => {
  // Parse the incoming event body
  const body = JSON.parse(event.body);

  const vin = body.vin;
  const color = body.color;
  const name = body.name;
  const email = body.email;

  // Generate lead (this is just an example, replace it with actual lead generation logic)
  const lead = {
    id: new Date().getTime(), // Just an example, use a proper ID generator
    vin,
    color,
    name,
    email,
    createdAt: new Date().toISOString(),
  };

  // Log the lead (you can replace this with actual database save logic)
  console.log('Lead generated:', lead);

  // Return the response
  const response = {
    statusCode: 200,
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      message: 'Lead generated successfully',
      lead,
    }),
  };

  return response;
};
