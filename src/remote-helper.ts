import { AppConfig } from "./config.js";
import { remotePathExpr, runSsh, shellQuote, CommandResult } from "./ssh.js";

export async function runRemoteHelper(config: AppConfig, args: string[], input?: string | Buffer): Promise<CommandResult> {
  const command = [remotePathExpr(config.remoteHelperPath), ...args.map(shellQuote)].join(" ");
  return runSsh(config.host, command, input);
}

