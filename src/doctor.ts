import { access } from "node:fs/promises";
import { constants } from "node:fs";
import { AppConfig } from "./config.js";
import { commandExists, remotePathExpr, runSsh, shellQuote } from "./ssh.js";

interface Check {
  label: string;
  ok: boolean;
  detail: string;
  required: boolean;
}

export async function runDoctor(config: AppConfig, agentCommand: string): Promise<boolean> {
  const checks: Check[] = [];

  checks.push({
    label: "local platform",
    ok: process.platform === "darwin",
    detail: process.platform === "darwin" ? "macOS" : `${process.platform}; macOS is required for clipboard capture`,
    required: true,
  });

  for (const command of ["ssh", "scp", "swift"]) {
    const path = await commandExists(command);
    checks.push({
      label: `local ${command}`,
      ok: path !== null,
      detail: path ?? "not found in PATH",
      required: true,
    });
  }

  checks.push(await remoteCheck(config, "ssh access", "printf ok", "ok", true));
  checks.push(await remoteCommandCheck(config, "remote tmux", "tmux", true));
  checks.push(await remoteCommandCheck(config, "remote agent", agentCommand, true));
  checks.push(await remoteWritableCacheCheck(config));

  for (const check of checks) {
    const mark = check.ok ? "ok" : check.required ? "fail" : "warn";
    console.log(`${mark.padEnd(4)} ${check.label}: ${check.detail}`);
  }

  return checks.every((check) => check.ok || !check.required);
}

async function remoteCommandCheck(config: AppConfig, label: string, command: string, required: boolean): Promise<Check> {
  const result = await runSsh(config.host, `command -v ${shellQuote(command)} 2>/dev/null || true`);
  const detail = result.stdout.trim();
  return {
    label,
    ok: result.exitCode === 0 && detail.length > 0,
    detail: detail.length > 0 ? detail : `${command} not found on ${config.host}`,
    required,
  };
}

async function remoteWritableCacheCheck(config: AppConfig): Promise<Check> {
  const command = [
    `mkdir -p ${remotePathExpr(config.remoteCacheDir)}`,
    `test -d ${remotePathExpr(config.remoteCacheDir)}`,
    `test -w ${remotePathExpr(config.remoteCacheDir)}`,
    `printf ok`,
  ].join(" && ");
  return remoteCheck(config, "remote cache dir", command, "ok", true, config.remoteCacheDir);
}

async function remoteCheck(
  config: AppConfig,
  label: string,
  command: string,
  expected: string,
  required: boolean,
  successDetail = expected,
): Promise<Check> {
  const result = await runSsh(config.host, command);
  const out = result.stdout.trim();
  const err = result.stderr.trim();
  const ok = result.exitCode === 0 && out === expected;
  return {
    label,
    ok,
    detail: ok ? successDetail : err || out || `remote command exited ${result.exitCode}`,
    required,
  };
}

export async function assertReadable(path: string): Promise<boolean> {
  try {
    await access(path, constants.R_OK);
    return true;
  } catch {
    return false;
  }
}
