import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { AppConfig } from "./config.js";
import { remotePathExpr, runSsh } from "./ssh.js";

export async function installRemoteHelper(config: AppConfig): Promise<void> {
  const script = await readRemoteHelperAsset();
  const dir = remoteDirname(config.remoteHelperPath);

  const mkdir = await runSsh(config.host, `mkdir -p ${remotePathExpr(dir)}`);
  if (mkdir.exitCode !== 0) throw new Error(`Failed to create remote helper directory: ${mkdir.stderr.trim()}`);

  const install = await runSsh(
    config.host,
    `cat > ${remotePathExpr(config.remoteHelperPath)} && chmod 0755 ${remotePathExpr(config.remoteHelperPath)}`,
    script,
  );
  if (install.exitCode !== 0) throw new Error(`Failed to install remote helper: ${install.stderr.trim()}`);

  const verify = await runSsh(config.host, `${remotePathExpr(config.remoteHelperPath)} version`);
  if (verify.exitCode !== 0) throw new Error(`Remote helper did not run: ${verify.stderr.trim()}`);

  console.log(`installed ${config.remoteHelperPath} on ${config.host} (${verify.stdout.trim()})`);
}

async function readRemoteHelperAsset(): Promise<string> {
  const here = dirname(fileURLToPath(import.meta.url));
  const candidates = [
    resolve(here, "../remote/ssh-bin-paste-remote.sh"),
    resolve(here, "../../remote/ssh-bin-paste-remote.sh"),
  ];
  const errors: string[] = [];
  for (const candidate of candidates) {
    try {
      return await readFile(candidate, "utf8");
    } catch (error) {
      errors.push(`${candidate}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  throw new Error(`Could not find remote helper asset:\n${errors.join("\n")}`);
}

function remoteDirname(path: string): string {
  const normalized = path.replace(/\/+$/, "");
  const idx = normalized.lastIndexOf("/");
  return idx <= 0 ? "." : normalized.slice(0, idx);
}
