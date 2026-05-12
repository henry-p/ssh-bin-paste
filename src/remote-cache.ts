import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { basename } from "node:path";
import { AppConfig } from "./config.js";
import { CapturedImage } from "./clipboard.js";
import { runRemoteHelper } from "./remote-helper.js";
import { runSsh, shellQuote } from "./ssh.js";

export async function uploadImage(config: AppConfig, image: CapturedImage): Promise<string> {
  const cacheDir = await ensureRemoteCache(config);
  const extension = extensionForMime(image.mimeType);
  const remotePath = `${cacheDir.replace(/\/+$/, "")}/ssh-bin-paste-${Date.now()}-${randomUUID()}.${extension}`;
  const data = await readFile(image.path);
  const result = await runSsh(config.host, `cat > ${shellQuote(remotePath)} && chmod 0600 ${shellQuote(remotePath)}`, data);
  if (result.exitCode !== 0) {
    throw new Error(`Failed to upload ${basename(image.path)}: ${result.stderr.trim() || result.stdout.trim()}`);
  }
  return remotePath;
}

export async function cleanupRemoteImages(config: AppConfig, maxAgeSeconds: number): Promise<void> {
  const seconds = Number.isFinite(maxAgeSeconds) && maxAgeSeconds > 0 ? Math.floor(maxAgeSeconds) : 86400;
  const result = await runRemoteHelper(config, ["cleanup", config.remoteCacheDir, String(seconds)]);
  if (result.exitCode !== 0) throw new Error(`Remote cleanup failed: ${result.stderr.trim()}`);
  console.log(`cleaned images older than ${seconds}s on ${config.host}`);
}

export async function remoteCleanupDaemon(config: AppConfig, action: "start" | "stop" | "status"): Promise<void> {
  const command = action === "start" ? "daemon-start" : action === "stop" ? "daemon-stop" : "daemon-status";
  const args =
    action === "start"
      ? [command, config.remoteCacheDir, String(config.cleanupDaemon.maxAgeSeconds), String(config.cleanupDaemon.intervalSeconds)]
      : [command];
  const result = await runRemoteHelper(config, args);
  if (result.exitCode !== 0) throw new Error(`Remote cleanup daemon ${action} failed: ${result.stderr.trim()}`);
  console.log(result.stdout.trim());
}

async function ensureRemoteCache(config: AppConfig): Promise<string> {
  const result = await runRemoteHelper(config, ["ensure-cache", config.remoteCacheDir]);
  if (result.exitCode !== 0) throw new Error(`Remote cache is not writable: ${result.stderr.trim()}`);
  return result.stdout.trim();
}

function extensionForMime(mimeType: string): string {
  switch (mimeType) {
    case "image/png":
      return "png";
    case "image/jpeg":
      return "jpg";
    case "image/webp":
      return "webp";
    case "image/gif":
      return "gif";
    default:
      return "bin";
  }
}
