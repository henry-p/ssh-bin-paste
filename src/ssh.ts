import { spawn } from "node:child_process";

export interface CommandResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

export async function commandExists(command: string): Promise<string | null> {
  const result = await runLocal("sh", ["-lc", `command -v ${shellQuote(command)}`]);
  const path = result.stdout.trim();
  return result.exitCode === 0 && path.length > 0 ? path : null;
}

export async function runSsh(host: string, remoteCommand: string): Promise<CommandResult> {
  return runLocal("ssh", [host, remoteCommand]);
}

export async function runLocal(command: string, args: string[], input?: string | Buffer): Promise<CommandResult> {
  return new Promise((resolve) => {
    const child = spawn(command, args, { stdio: ["pipe", "pipe", "pipe"] });
    const stdout: Buffer[] = [];
    const stderr: Buffer[] = [];

    child.stdout.on("data", (chunk: Buffer) => stdout.push(chunk));
    child.stderr.on("data", (chunk: Buffer) => stderr.push(chunk));
    child.on("error", (error) => {
      resolve({ stdout: "", stderr: error.message, exitCode: 1 });
    });
    child.on("close", (code) => {
      resolve({
        stdout: Buffer.concat(stdout).toString("utf8"),
        stderr: Buffer.concat(stderr).toString("utf8"),
        exitCode: code ?? 1,
      });
    });

    if (input) child.stdin.end(input);
    else child.stdin.end();
  });
}

export function shellQuote(value: string): string {
  return `'${value.replaceAll("'", "'\\''")}'`;
}
