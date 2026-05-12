import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";
import { runLocal } from "./ssh.js";

export interface CapturedImage {
  path: string;
  mimeType: string;
  sizeBytes: number;
}

export async function captureClipboardImage(): Promise<CapturedImage> {
  const dir = await mkdtemp(join(tmpdir(), "ssh-bin-paste-"));
  const outputPath = join(dir, `${randomUUID()}.png`);
  const script = await clipboardHelperPath();
  const result = await runLocal("swift", [script, "--output", outputPath]);
  if (result.exitCode !== 0) {
    throw new Error(result.stderr.trim() || "No image found on the clipboard");
  }

  try {
    return JSON.parse(result.stdout) as CapturedImage;
  } catch {
    throw new Error(`Clipboard helper returned invalid JSON: ${result.stdout}`);
  }
}

async function clipboardHelperPath(): Promise<string> {
  const here = dirname(fileURLToPath(import.meta.url));
  const candidates = [
    resolve(here, "../native/clipboard-image.swift"),
    resolve(here, "../../native/clipboard-image.swift"),
  ];
  for (const candidate of candidates) {
    return candidate;
  }
  throw new Error("Could not find clipboard helper");
}

