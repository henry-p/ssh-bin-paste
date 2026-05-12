import { captureClipboardImage } from "./clipboard.js";
import { AppConfig } from "./config.js";
import { resolveTargetPane } from "./panes.js";
import { uploadImage } from "./remote-cache.js";
import { runRemoteHelper } from "./remote-helper.js";

export async function pasteClipboardImage(config: AppConfig, targetPane?: string): Promise<void> {
  const image = await captureClipboardImage();
  const remotePath = await uploadImage(config, image);
  const target = targetPane ?? (await resolveTargetPane(config));
  await injectText(config, target, remotePath);
  console.log(`pasted ${remotePath} into ${target}`);
}

export async function injectText(config: AppConfig, targetPane: string, text: string): Promise<void> {
  const result = await runRemoteHelper(config, ["inject", targetPane], text);
  if (result.exitCode !== 0) throw new Error(`Remote paste failed: ${result.stderr.trim() || result.stdout.trim()}`);
}

