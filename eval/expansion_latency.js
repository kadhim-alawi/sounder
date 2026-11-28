// Expansion latency measurement for the hosted Sounder app (REQ-LATENCY-1, REQ-STEER-2).
//
// How to run:
//   1. Open https://sounder.kadhim-alawi.workers.dev/ in a browser on a broadband connection.
//   2. Open the developer tools console (F12), paste this whole file and press Enter.
//   3. Wait about 90 seconds. The script prints one line per request, then a summary.
//   4. Copy the printed lines into eval/expansion_latency.md.
//
// What it does: sends the six spike-3 Token_Lists (spikes/expand_spike/src/index.ts) in turn,
// four rounds, 24 POST /expand requests in total. Sends start at least 3.5 s apart, so the
// Worker's limit of 20 requests per 60 s is never reached. Each duration is performance.now()
// from just before fetch() to the parsed JSON reply.
//
// Privacy: it prints request numbers, Token_List numbers, statuses, durations and candidate
// counts only. It never prints candidate text, reply bodies or error messages.
//
// The reported median adds one frame (about 17 ms) for showing the result (design L5).
//
// Nothing in eval/ ships. This file is not part of any build or test suite.

(async () => {
  const TOKEN_LISTS = [
    ["I", "W", "S", "W", "P"],
    ["C", "Y", "H", "M"],
    ["I", "A", "T"],
    ["P", "C", "M", "D"],
    ["I", "N", "T", "G", "T", "T", "B"],
    ["W", "T", "I", "I"],
  ];
  const ROUNDS = 4;
  const SPACING_MS = 3500;
  const ABORT_MS = 15000; // Only stops a hung request; the app's own timeout is 6 s.
  const FRAME_MS = 17;

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  const median = (xs) => {
    if (xs.length === 0) return NaN;
    const s = [...xs].sort((a, b) => a - b);
    const mid = Math.floor(s.length / 2);
    return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  };

  async function measureOne(tokens) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), ABORT_MS);
    const start = performance.now();
    try {
      const res = await fetch("/expand", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ tokens }),
        signal: controller.signal,
        cache: "no-store",
      });
      let count = null;
      try {
        const body = await res.json();
        count = body && Array.isArray(body.candidates) ? body.candidates.length : null;
      } catch {
        count = null; // Unreadable body; its content is not printed.
      }
      const ms = performance.now() - start;
      return { status: String(res.status), ms, count };
    } catch (e) {
      const ms = performance.now() - start;
      const label = e && e.name === "AbortError" ? "abort" : "network-error";
      return { status: label, ms, count: null };
    } finally {
      clearTimeout(timer);
    }
  }

  const rows = [];
  let lastSend = -Infinity;
  let n = 0;
  for (let round = 0; round < ROUNDS; round++) {
    for (let list = 0; list < TOKEN_LISTS.length; list++) {
      const wait = lastSend + SPACING_MS - performance.now();
      if (wait > 0) await sleep(wait);
      lastSend = performance.now();
      n += 1;
      const r = await measureOne(TOKEN_LISTS[list]);
      const row = { request: n, list: list + 1, status: r.status, ms: Math.round(r.ms), candidates: r.count };
      rows.push(row);
      console.log(
        `request ${row.request} list ${row.list} status ${row.status} ms ${row.ms} candidates ${row.candidates ?? "-"}`,
      );
    }
  }

  const ok = rows.filter((r) => r.status === "200").map((r) => r.ms);
  const all = rows.map((r) => r.ms);
  const statusCounts = rows.reduce((acc, r) => ((acc[r.status] = (acc[r.status] || 0) + 1), acc), {});

  console.log(`raw ms (all, in order): ${all.join(", ")}`);
  console.log(`statuses: ${JSON.stringify(statusCounts)}`);
  console.log(`200 replies: ${ok.length} of ${rows.length}`);
  console.log(`median ms (200 only): ${Math.round(median(ok))}`);
  console.log(`median ms (200 only) + one frame (${FRAME_MS} ms): ${Math.round(median(ok) + FRAME_MS)}`);
  console.log(`median ms (all requests) + one frame: ${Math.round(median(all) + FRAME_MS)}`);
})();
