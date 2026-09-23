import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { promisify } from "node:util";

const run = promisify(execFile);

/** One row of `portly list --json` (every value is a string there). */
export interface PortRow {
  port: string;
  proto: string;
  pid: string;
  processName: string;
  frameworkLabel: string;
  projectName: string;
  gitBranch: string;
  bindAddress: string;
  exposedToNetwork: string;
}

// Raycast runs extensions with a minimal PATH, so look where Portly's CLI is
// actually installed rather than relying on `portly` resolving.
const CANDIDATES = [
  "/opt/homebrew/bin/portly",
  "/usr/local/bin/portly",
  "/Applications/Portly.app/Contents/MacOS/portly-cli",
];

export function portlyPath(): string | undefined {
  return CANDIDATES.find((path) => existsSync(path));
}

export class PortlyMissingError extends Error {
  constructor() {
    super("Portly isn't installed. Install it with `brew install --cask hellohopper/portly/portly`.");
  }
}

export async function portly(args: string[]): Promise<string> {
  const binary = portlyPath();
  if (!binary) throw new PortlyMissingError();
  const { stdout } = await run(binary, args, { timeout: 15_000 });
  return stdout;
}

export async function listPorts(): Promise<PortRow[]> {
  return JSON.parse(await portly(["list", "--json"])) as PortRow[];
}

/** Title shown for a row: the framework when detected, else the process name. */
export function describe(row: PortRow): string {
  return row.frameworkLabel || row.processName;
}
