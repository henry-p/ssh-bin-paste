#!/usr/bin/env node
import { Command } from "commander";
import { loadConfig, resolveAgentCommand } from "./config.js";
import { runDoctor } from "./doctor.js";
import { installRemoteHelper } from "./remote-install.js";
import { cleanupRemoteImages, remoteCleanupDaemon } from "./remote-cache.js";
import { listPanes, printPanes, selectAndSavePane } from "./panes.js";
import { pasteClipboardImage } from "./paste.js";
import { startManagedAgent } from "./start.js";
import { runDaemon } from "./daemon.js";

const program = new Command();

interface RemoteOptions {
  host: string;
  ssh?: string;
}

function withRemoteOptions(command: Command): Command {
  return command
    .option("--host <host>", "SSH host alias", "vibeps")
    .option("--ssh <command>", "Full SSH command, for example: ssh -i ~/.ssh/key user@host");
}

async function loadRemoteConfig(options: RemoteOptions) {
  return loadConfig({ host: options.host, sshCommand: options.ssh });
}

program
  .name("ssh-bin-paste")
  .description("Paste local clipboard images into remote terminal agents over SSH.")
  .version("0.1.0");

withRemoteOptions(program.command("doctor"))
  .description("Check local and remote prerequisites.")
  .option("--agent <agent>", "Agent profile or command", "codex")
  .action(async (options: RemoteOptions & { agent: string }) => {
    const config = await loadRemoteConfig(options);
    const agentCommand = resolveAgentCommand(config, options.agent);
    const ok = await runDoctor(config, agentCommand);
    process.exitCode = ok ? 0 : 1;
  });

withRemoteOptions(program.command("install-remote"))
  .description("Install or update the remote helper.")
  .option("--no-cleanup-daemon", "Do not start the remote cleanup daemon")
  .option("--cleanup-max-age-seconds <seconds>", "Remote image retention", "86400")
  .option("--cleanup-interval-seconds <seconds>", "Remote cleanup interval", "300")
  .action(async (options: RemoteOptions & { cleanupDaemon?: boolean; cleanupMaxAgeSeconds: string; cleanupIntervalSeconds: string }) => {
    const config = await loadRemoteConfig(options);
    await installRemoteHelper(config, {
      cleanupDaemon: options.cleanupDaemon,
      cleanupMaxAgeSeconds: Number.parseInt(options.cleanupMaxAgeSeconds, 10),
      cleanupIntervalSeconds: Number.parseInt(options.cleanupIntervalSeconds, 10),
    });
  });

withRemoteOptions(program.command("start"))
  .description("Start an agent inside a managed tmux session.")
  .requiredOption("--agent <agent>", "Agent profile or command")
  .option("--session <name>", "Managed tmux session name")
  .action(async (options: RemoteOptions & { agent: string; session?: string }) => {
    const config = await loadRemoteConfig(options);
    await startManagedAgent(config, options.agent, options.session);
  });

withRemoteOptions(program.command("panes"))
  .description("List remote tmux panes that may contain agents.")
  .option("--select", "Interactively save the target pane")
  .option("--target <pane>", "Save this target pane")
  .action(async (options: RemoteOptions & { select?: boolean; target?: string }) => {
    const config = await loadRemoteConfig(options);
    const panes = await listPanes(config);
    if (options.target) {
      await selectAndSavePane(config, panes, options.target);
      return;
    }
    if (options.select) {
      await selectAndSavePane(config, panes);
      return;
    }
    printPanes(panes);
  });

withRemoteOptions(program.command("paste"))
  .description("Paste the local clipboard image into a remote agent pane.")
  .option("--target <pane>", "tmux target pane id")
  .action(async (options: RemoteOptions & { target?: string }) => {
    const config = await loadRemoteConfig(options);
    await pasteClipboardImage(config, options.target);
  });

withRemoteOptions(program.command("cleanup"))
  .description("Remove old staged remote images.")
  .option("--max-age-seconds <seconds>", "Delete images older than this many seconds", "86400")
  .action(async (options: RemoteOptions & { maxAgeSeconds: string }) => {
    const config = await loadRemoteConfig(options);
    await cleanupRemoteImages(config, Number.parseInt(options.maxAgeSeconds, 10));
  });

withRemoteOptions(program.command("cleanup-daemon"))
  .description("Manage the remote cache cleanup daemon.")
  .argument("<action>", "start, stop, or status")
  .action(async (action: string, options: RemoteOptions) => {
    if (!["start", "stop", "status"].includes(action)) throw new Error("cleanup-daemon action must be start, stop, or status");
    const config = await loadRemoteConfig(options);
    await remoteCleanupDaemon(config, action as "start" | "stop" | "status");
  });

withRemoteOptions(program.command("daemon"))
  .description("Run the optional macOS hotkey daemon.")
  .option("--hijack-paste", "Intercept normal paste in allowlisted terminal apps")
  .action(async (options: RemoteOptions & { hijackPaste?: boolean }) => {
    const config = await loadRemoteConfig(options);
    await runDaemon(config, { hijackPaste: options.hijackPaste ?? config.daemon.hijackPaste });
  });

program.parseAsync().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
