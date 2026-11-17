import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const functionsRoot = path.resolve(scriptDir, "..");
const libRoot = path.join(functionsRoot, "lib");

function collectMatchingFiles(dir, suffixPattern, results) {
  if (!fs.existsSync(dir)) return;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.name === "node_modules") continue;
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collectMatchingFiles(fullPath, suffixPattern, results);
    } else if (entry.isFile() && suffixPattern.test(entry.name)) {
      results.push(path.relative(functionsRoot, fullPath));
    }
  }
}

const discovered = [];
collectMatchingFiles(libRoot, /\.(test|rules)\.js$/, discovered);

for (const entry of fs.readdirSync(functionsRoot, { withFileTypes: true })) {
  if (entry.isFile() && /\.test\.cjs$/.test(entry.name)) {
    discovered.push(entry.name);
  }
}

discovered.sort((a, b) => a.localeCompare(b));

if (discovered.length === 0) {
  console.error("ERROR: No compiled test or rules files found under functions/lib or functions/*.test.cjs.");
  process.exit(1);
}

const explicitFilters = process.argv.slice(2);
const targets =
  explicitFilters.length > 0
    ? discovered.filter((file) =>
        explicitFilters.some((filter) => file.replaceAll("\\", "/").includes(filter)),
      )
    : discovered;

if (targets.length === 0) {
  console.error(`ERROR: No test files matched filter(s): ${explicitFilters.join(", ")}`);
  process.exit(1);
}

console.log(`Running ${targets.length} Functions test/rules file(s):`);
for (const file of targets) {
  console.log(`  - ${file.replaceAll("\\", "/")}`);
}

const result = spawnSync(
  process.execPath,
  ["--test", "--test-concurrency=1", ...targets],
  {
    cwd: functionsRoot,
    stdio: "inherit",
    env: process.env,
  },
);

if (result.error) {
  console.error(result.error);
  process.exit(1);
}

if (typeof result.status === "number") {
  process.exit(result.status);
}

process.exit(1);
