"use strict";

const { Utils } = require("../../utils/aws-helpers");

exports.handler = async (event) => {
  return Utils.createAPIResponse(200, {
    ok: true,
    service: "WizzUser",
    environment: process.env.ENVIRONMENT || "unknown",
    timestamp: new Date().toISOString(),
  });
};
