import { spawn } from "node:child_process";
import { homedir } from "node:os";

export interface CommandResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

export interface SshCommandTarget {
  host: string;
  sshCommand?: string;
}

export async function commandExists(command: string): Promise<string | null> {
  const result = await runLocal("sh", ["-lc", `command -v ${shellQuote(command)}`]);
  const path = result.stdout.trim();
  return result.exitCode === 0 && path.length > 0 ? path : null;
}

export async function runSsh(target: string | SshCommandTarget, remoteCommand: string, input?: string | Buffer): Promise<CommandResult> {
  const args = sshArgs(target, remoteCommand);
  return runLocal(args[0], args.slice(1), input);
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

export function remotePathExpr(value: string): string {
  if (value === "~") return '"$HOME"';
  if (value.startsWith("~/")) return `"$HOME/${escapeDoubleQuoted(value.slice(2))}"`;
  return shellQuote(value);
}

export function targetLabel(target: string | SshCommandTarget): string {
  if (typeof target === "string") return target;
  return target.sshCommand ?? target.host;
}

export function sshArgs(target: string | SshCommandTarget, remoteCommand: string): string[] {
  if (typeof target === "string" || !target.sshCommand) {
    return ["ssh", typeof target === "string" ? target : target.host, remoteCommand];
  }

  const parsed = parseShellWords(target.sshCommand).map(expandHomeArg);
  if (parsed.length === 0) throw new Error("SSH command is empty");
  if (parsed[0] !== "ssh" && !parsed[0].endsWith("/ssh")) {
    throw new Error(`SSH command must start with ssh: ${target.sshCommand}`);
  }
  return [...parsed, remoteCommand];
}

export function sshDisplayCommand(target: string | SshCommandTarget, remoteCommand: string, sshOptions: string[] = []): string {
  const args =
    typeof target === "string" || !target.sshCommand
      ? ["ssh", ...sshOptions, typeof target === "string" ? target : target.host, remoteCommand]
      : [parseShellWords(target.sshCommand)[0], ...sshOptions, ...parseShellWords(target.sshCommand).slice(1), remoteCommand];
  return args.map((arg, index) => (index === 0 ? arg : shellQuote(arg))).join(" ");
}

export function parseShellWords(input: string): string[] {
  const words: string[] = [];
  let current = "";
  let quote: "'" | '"' | null = null;
  let escaped = false;

  for (const char of input) {
    if (escaped) {
      current += char;
      escaped = false;
      continue;
    }
    if (char === "\\" && quote !== "'") {
      escaped = true;
      continue;
    }
    if (quote) {
      if (char === quote) quote = null;
      else current += char;
      continue;
    }
    if (char === "'" || char === '"') {
      quote = char;
      continue;
    }
    if (/\s/.test(char)) {
      if (current.length > 0) {
        words.push(current);
        current = "";
      }
      continue;
    }
    current += char;
  }

  if (escaped) current += "\\";
  if (quote) throw new Error("Unterminated quote in SSH command");
  if (current.length > 0) words.push(current);
  return words;
}

function escapeDoubleQuoted(value: string): string {
  return value.replaceAll("\\", "\\\\").replaceAll('"', '\\"').replaceAll("$", "\\$").replaceAll("`", "\\`");
}

function expandHomeArg(value: string): string {
  if (value === "~") return homedir();
  if (value.startsWith("~/")) return `${homedir()}/${value.slice(2)}`;
  return value;
}
