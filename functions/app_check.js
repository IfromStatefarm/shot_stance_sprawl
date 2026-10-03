const {defineBoolean} = require("firebase-functions/params");

// Fail closed if a deployment does not load its project-specific parameter
// file. Local emulator suites that cannot mint App Check tokens must opt out
// explicitly in their own environment configuration.
const enforceAppCheck = defineBoolean("ENFORCE_APP_CHECK", {
  default: true,
  description: "Reject callable requests without valid App Check tokens.",
});

module.exports = {enforceAppCheck};
