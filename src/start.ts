import { AppConfig, resolveAgentCommand, saveConfigPatch } from "./config.js";
import { listPanes } from "./panes.js";
import { runSsh, shellQuote, sshDisplayCommand, targetLabel } from "./ssh.js";

export async function startManagedAgent(config: AppConfig, agent: string, sessionOverride?: string): Promise<void> {
  const sessionName = sessionOverride ?? config.tmuxSession;
  const agentCommand = resolveAgentCommand(config, agent);
  const tmuxCommand = [
    `tmux has-session -t ${shellQuote(sessionName)} 2>/dev/null`,
    `tmux new-session -d -s ${shellQuote(sessionName)} -n agent ${shellQuote(`exec ${agentCommand}`)}`,
  ].join(" || ");

  const result = await runSsh(config, tmuxCommand);
  if (result.exitCode !== 0) throw new Error(`Failed to start managed tmux session: ${result.stderr.trim()}`);

  const startedConfig = { ...config, tmuxSession: sessionName };
  const panes = await listPanes(startedConfig);
  const pane = panes.find((candidate) => candidate.sessionName === sessionName);
  if (!pane) throw new Error(`Started tmux session ${sessionName}, but could not find its pane.`);

  await saveConfigPatch({ host: config.host, sshCommand: config.sshCommand, tmuxSession: sessionName, targetPane: pane.paneId });
  console.log(`agent session ready: ${targetLabel(config)}:${sessionName} target ${pane.paneId}`);
  console.log(`attach with: ${attachCommand(config, sessionName)}`);
}

function attachCommand(config: AppConfig, sessionName: string): string {
  return sshDisplayCommand(config, `tmux attach -t ${sessionName}`, ["-t"]);
}
