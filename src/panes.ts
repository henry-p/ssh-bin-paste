import readline from "node:readline/promises";
import { stdin as input, stdout as output } from "node:process";
import { AppConfig, saveConfigPatch } from "./config.js";
import { runRemoteHelper } from "./remote-helper.js";

export interface TmuxPane {
  sessionName: string;
  windowPane: string;
  paneId: string;
  panePid: number | null;
  command: string;
  cwd: string;
  title: string;
  score: number;
}

export async function listPanes(config: AppConfig): Promise<TmuxPane[]> {
  const result = await runRemoteHelper(config, ["panes"]);
  if (result.exitCode !== 0) throw new Error(`Failed to list tmux panes: ${result.stderr.trim()}`);
  return result.stdout
    .split("\n")
    .map((line) => line.trimEnd())
    .filter(Boolean)
    .map(parsePaneLine)
    .sort((a, b) => b.score - a.score || a.sessionName.localeCompare(b.sessionName));
}

export function printPanes(panes: TmuxPane[]): void {
  if (panes.length === 0) {
    console.log("No tmux panes found on the remote host.");
    return;
  }
  for (const pane of panes) {
    const target = pane.paneId;
    const score = pane.score > 0 ? ` agent-score=${pane.score}` : "";
    console.log(`${target.padEnd(6)} ${pane.sessionName}:${pane.windowPane.padEnd(5)} ${pane.command.padEnd(16)} ${pane.cwd}${score}`);
  }
}

export async function selectAndSavePane(config: AppConfig, panes: TmuxPane[], requestedTarget?: string): Promise<string> {
  if (panes.length === 0) throw new Error("No tmux panes found on the remote host.");

  const target = requestedTarget ?? (await choosePane(panes));
  const found = panes.find((pane) => pane.paneId === target || `${pane.sessionName}:${pane.windowPane}` === target);
  if (!found) throw new Error(`Target pane ${target} was not found.`);

  await saveConfigPatch({ host: config.host, targetPane: found.paneId });
  console.log(`saved target pane ${found.paneId} (${found.sessionName}:${found.windowPane})`);
  return found.paneId;
}

export function likelyAgentPanes(panes: TmuxPane[]): TmuxPane[] {
  const candidates = panes.filter((pane) => pane.score > 0);
  return candidates.length > 0 ? candidates : panes;
}

export async function resolveTargetPane(config: AppConfig): Promise<string> {
  if (config.targetPane) return config.targetPane;
  const panes = likelyAgentPanes(await listPanes(config));
  if (panes.length === 0) {
    throw new Error("No tmux panes found. Start an agent with `ssh-bin-paste start --agent codex` or select an existing tmux pane.");
  }
  if (panes.length === 1) return panes[0].paneId;
  return choosePane(panes);
}

export function parsePaneLine(line: string): TmuxPane {
  const [sessionName = "", windowPane = "", paneId = "", panePidRaw = "", command = "", cwd = "", title = ""] = line.split("\t");
  const pane: Omit<TmuxPane, "score"> = {
    sessionName,
    windowPane,
    paneId,
    panePid: Number.isFinite(Number(panePidRaw)) ? Number(panePidRaw) : null,
    command,
    cwd,
    title,
  };
  return { ...pane, score: scorePane(pane) };
}

function scorePane(pane: Omit<TmuxPane, "score">): number {
  const haystack = `${pane.sessionName} ${pane.command} ${pane.title}`.toLowerCase();
  let score = 0;
  if (haystack.includes("codex")) score += 4;
  if (haystack.includes("claude")) score += 4;
  if (haystack.includes("agent")) score += 2;
  if (pane.command === "node") score += 1;
  return score;
}

async function choosePane(panes: TmuxPane[]): Promise<string> {
  if (!input.isTTY) throw new Error("Multiple tmux panes found; rerun with `panes --select` in an interactive terminal.");
  printPanes(panes);
  const rl = readline.createInterface({ input, output });
  try {
    const answer = await rl.question("Target pane id: ");
    return answer.trim();
  } finally {
    rl.close();
  }
}
