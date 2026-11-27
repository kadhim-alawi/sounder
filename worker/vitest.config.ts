// REQ-WORKERTEST-1: Worker tests run once with `vitest run` (no watch mode).
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
  },
  server: {
    // The shared Validator_Fixture lives in ../fixtures, outside worker/.
    fs: { allow: [".."] },
  },
});
