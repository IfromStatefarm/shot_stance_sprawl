const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {enforceAppCheck} = require("../app_check");

const functionsDirectory = path.resolve(__dirname, "..");
const productionEnvironmentPath = path.join(
    functionsDirectory,
    ".env.snap-and-go-prod",
);

function readEnvironment(filePath) {
  const values = new Map();

  for (const line of fs.readFileSync(filePath, "utf8").split(/\r?\n/u)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const separator = trimmed.indexOf("=");
    assert.notEqual(
        separator,
        -1,
        `Invalid environment entry in ${path.basename(filePath)}: ${line}`,
    );
    values.set(
        trimmed.slice(0, separator).trim(),
        trimmed.slice(separator + 1).trim(),
    );
  }

  return values;
}

assert.equal(
    enforceAppCheck.options.default,
    true,
    "App Check must fail closed when project configuration is missing.",
);

assert.equal(
    readEnvironment(productionEnvironmentPath).get("ENFORCE_APP_CHECK"),
    "true",
    "snap-and-go-prod must deploy with ENFORCE_APP_CHECK=true.",
);

console.log("Verified App Check enforcement for snap-and-go-prod.");
