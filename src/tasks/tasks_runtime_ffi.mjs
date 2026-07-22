export function halt(code) {
  if (typeof process !== "undefined" && typeof process.exit === "function") {
    process.exit(code);
  }

  if (typeof Deno !== "undefined") {
    Deno.exit(code);
  }

  throw new Error("Exiting the process is not supported by this runtime");
}
