import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { AppConfig } from "./config.js";

export interface DaemonOptions {
  hijackPaste: boolean;
}

export async function runDaemon(config: AppConfig, options: DaemonOptions): Promise<void> {
  const helper = daemonHelperPath();
  const args = [
    helper,
    "--command",
    process.argv[1],
    "--allowlisted-apps",
    config.daemon.allowlistedApps.join(","),
  ];
  if (config.sshCommand) args.push("--ssh", config.sshCommand);
  else args.push("--host", config.host);
  if (options.hijackPaste) args.push("--hijack-paste");

  await new Promise<void>((resolvePromise, reject) => {
    const child = spawn("swift", args, { stdio: "inherit" });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolvePromise();
      else reject(new Error(`daemon exited with code ${code ?? 1}`));
    });
  });
}

function daemonHelperPath(): string {
  const here = dirname(fileURLToPath(import.meta.url));
  return resolve(here, "../native/paste-daemon.swift");
}
