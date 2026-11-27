// Smoke tests for wrangler.jsonc, the deploy workflow, the Worker sources and
// the Worker test descriptions. Files are loaded through Vite's `?raw` imports
// and `import.meta.glob` (typed in support/vite-raw.d.ts), so paths resolve
// relative to this file, not the cwd.
import { describe, expect, it } from "vitest";
import wranglerText from "../../wrangler.jsonc?raw";
import workflowText from "../../.github/workflows/deploy.yml?raw";

const sourceFiles: Record<string, string> = import.meta.glob<string>("../src/**/*.ts", {
  query: "?raw",
  import: "default",
  eager: true,
});

const testFiles: Record<string, string> = import.meta.glob<string>("./**/*.ts", {
  query: "?raw",
  import: "default",
  eager: true,
});

/** Removes `//` and `/* *\/` comments that are outside JSON strings. */
const stripJsonComments = (text: string): string => {
  let out = "";
  let i = 0;
  while (i < text.length) {
    const ch = text[i];
    if (ch === '"') {
      let j = i + 1;
      while (j < text.length && text[j] !== '"') j += text[j] === "\\" ? 2 : 1;
      out += text.slice(i, j + 1);
      i = j + 1;
    } else if (ch === "/" && text[i + 1] === "/") {
      while (i < text.length && text[i] !== "\n") i++;
    } else if (ch === "/" && text[i + 1] === "*") {
      const end = text.indexOf("*/", i + 2);
      i = end < 0 ? text.length : end + 2;
    } else {
      out += ch;
      i++;
    }
  }
  return out;
};

interface WorkflowStep {
  name: string;
  text: string;
}

/** Splits the job's `steps:` list into one entry per `- ` item. */
const workflowSteps = (yaml: string): WorkflowStep[] => {
  const lines = yaml.split(/\r?\n/);
  const start = lines.findIndex((l) => /^\s*steps:\s*$/.test(l));
  const itemIndent = /^(\s*)- /.exec(lines[start + 1] ?? "")?.[1] ?? "";
  const steps: WorkflowStep[] = [];
  for (const line of lines.slice(start + 1)) {
    if (line.startsWith(`${itemIndent}- `)) {
      steps.push({ name: "", text: line });
    } else if (steps.length > 0) {
      steps[steps.length - 1].text += `\n${line}`;
    }
  }
  for (const step of steps) {
    step.name = /(?:^|\n)\s*-?\s*name:\s*(.+)/.exec(step.text)?.[1].trim() ?? "";
  }
  return steps;
};

const config = JSON.parse(stripJsonComments(wranglerText)) as Record<string, unknown>;
const steps = workflowSteps(workflowText);
const stepIndex = (name: string): number => steps.findIndex((s) => s.name === name);

describe("REQ-ROUTE-1: wrangler.jsonc fields", () => {
  it("REQ-ROUTE-1: keeps name and compatibility_date", () => {
    expect(config.name).toBe("sounder");
    expect(config.compatibility_date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it("REQ-ROUTE-1: main points to the Worker entry point", () => {
    expect(config.main).toBe("./worker/src/index.ts");
  });

  it("REQ-ROUTE-1: assets block", () => {
    expect(config.assets).toEqual({
      directory: "./app/build/web",
      binding: "ASSETS",
      not_found_handling: "single-page-application",
      run_worker_first: ["/expand"],
    });
  });

  it("REQ-ROUTE-1: ai binding is AI", () => {
    expect(config.ai).toEqual({ binding: "AI" });
  });

  it("REQ-ROUTE-1: one rate limiter with limit 20 per 60 seconds", () => {
    expect(config.ratelimits).toEqual([
      { name: "EXPAND_RATE_LIMITER", namespace_id: "1001", simple: { limit: 20, period: 60 } },
    ]);
  });

  it("REQ-ROUTE-1, REQ-LOG-1: no observability block", () => {
    expect(config).not.toHaveProperty("observability");
  });
});

describe("REQ-PIPE-1, REQ-PIPE-3: deploy workflow", () => {
  it("REQ-PIPE-1: Worker tests step runs npm ci then npm test in worker/", () => {
    const step = steps[stepIndex("Worker tests")];
    expect(step).toBeDefined();
    expect(step.text).toMatch(/\n\s*working-directory:\s*worker\s*(\n|$)/);
    const ci = step.text.indexOf("npm ci");
    const test = step.text.indexOf("npm test");
    expect(ci).toBeGreaterThan(-1);
    expect(test).toBeGreaterThan(ci);
  });

  it("REQ-PIPE-1: Worker tests comes before Build web app", () => {
    expect(stepIndex("Worker tests")).toBeGreaterThan(-1);
    expect(stepIndex("Worker tests")).toBeLessThan(stepIndex("Build web app"));
  });

  it("REQ-PIPE-1: no continue-on-error anywhere", () => {
    expect(workflowText).not.toContain("continue-on-error");
  });

  it("REQ-PIPE-3: existing steps and wranglerVersion are kept", () => {
    for (const name of ["Engine tests", "App tests", "Build web app", "Deploy to Cloudflare"]) {
      expect(stepIndex(name), name).toBeGreaterThan(-1);
    }
    expect(steps[stepIndex("Deploy to Cloudflare")].text).toMatch(/wranglerVersion:\s*"?[\d.]+"?/);
  });
});

describe("REQ-LOG-1, REQ-LOG-3, REQ-VALIDATOR-4: Worker sources", () => {
  const entries = Object.entries(sourceFiles);

  it("REQ-LOG-1: sources were found", () => {
    expect(entries.length).toBeGreaterThan(0);
    expect(Object.keys(sourceFiles)).toContain("../src/log.ts");
  });

  it("REQ-LOG-1: no cache, KV, D1 or R2 use", () => {
    const banned = [/\bcaches\b/, /\bKVNamespace\b/, /\bD1Database\b/, /\bR2Bucket\b/, /\.put\(/];
    for (const [path, text] of entries) {
      for (const pattern of banned) {
        expect(pattern.test(text), `${path} matches ${pattern}`).toBe(false);
      }
    }
  });

  it("REQ-LOG-3, REQ-VALIDATOR-4: only log.ts calls console", () => {
    for (const [path, text] of entries) {
      if (path === "../src/log.ts") continue;
      expect(/\bconsole\s*\./.test(text), `${path} uses console`).toBe(false);
    }
  });
});

describe("REQ-WORKERTEST-6: test descriptions", () => {
  // A call such as describe("...") or it.each(...)("...") opening a string.
  const callPattern = /\b(?:describe|it|test)(?:\.[A-Za-z]+)*\(\s*(["'`])/g;
  const idPrefix = /^REQ-[A-Z]+-\d+(?:, REQ-[A-Z]+-\d+)*: /;

  const descriptions = (text: string): string[] => {
    const found: string[] = [];
    for (const m of text.matchAll(callPattern)) {
      const quote = m[1];
      const start = (m.index ?? 0) + m[0].length;
      found.push(text.slice(start, text.indexOf(quote, start)));
    }
    return found;
  };

  it("REQ-WORKERTEST-6: every description starts with REQ IDs and a colon", () => {
    let count = 0;
    for (const [path, text] of Object.entries(testFiles)) {
      for (const d of descriptions(text)) {
        count++;
        expect(idPrefix.test(d), `${path}: "${d}"`).toBe(true);
      }
    }
    expect(count).toBeGreaterThan(0);
  });
});
