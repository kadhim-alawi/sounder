// Minimal types for the two Vite features config.test.ts uses (REQ-WORKERTEST-6
// and the smoke checks). `vite/client` is not referenced because it needs DOM
// types, which the Worker tsconfig does not load.
declare module "*?raw" {
  const src: string;
  export default src;
}

interface ImportMeta {
  glob<T>(
    pattern: string,
    options: { query: "?raw"; import: "default"; eager: true },
  ): Record<string, T>;
}
