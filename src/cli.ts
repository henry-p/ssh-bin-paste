#!/usr/bin/env node
import { Command } from "commander";
import { loadConfig, resolveAgentCommand } from "./config.js";
import { runDoctor } from "./doctor.js";
import { installRemoteHelper } from "./remote-install.js";
import { cleanupRemoteImages } from "./remote-cache.js";
import { listPanes, printPanes, selectAndSavePane } from "./panes.js";
import { pasteClipboardImage } from "./paste.js";

const program = new Command();

program
  .name("ssh-bin-paste")
  .description("Paste local clipboard images into remote terminal agents over SSH.")
  .version("0.1.0");

program
  .command("doctor")
  .description("Check local and remote prerequisites.")
  .option("--host <host>", "SSH host alias", "vibeps")
  .option("--agent <agent>", "Agent profile or command", "codex")
  .action(async (options: { host: string; agent: string }) => {
    const config = await loadConfig({ host: options.host });
    const agentCommand = resolveAgentCommand(config, options.agent);
    const ok = await runDoctor(config, agentCommand);
    process.exitCode = ok ? 0 : 1;
  });

program
  .command("install-remote")
  .description("Install or update the remote helper.")
  .option("--host <host>", "SSH host alias", "vibeps")
  .action(async (options: { host: string }) => {
    const config = await loadConfig({ host: options.host });
    await installRemoteHelper(config);
  });

program
  .command("start")
  .description("Start an agent inside a managed tmux session.")
  .requiredOption("--agent <agent>", "Agent profile or command")
  .option("--host <host>", "SSH host alias", "vibeps")
  .action(async (options: { agent: string; host: string }) => {
    await loadConfig({ host: options.host });
    console.log(`start placeholder for ${options.agent} on ${options.host}`);
  });

program
  .command("panes")
  .description("List remote tmux panes that may contain agents.")
  .option("--host <host>", "SSH host alias", "vibeps")
  .option("--select", "Interactively save the target pane")
  .option("--target <pane>", "Save this target pane")
  .action(async (options: { host: string; select?: boolean; target?: string }) => {
    const config = await loadConfig({ host: options.host });
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

program
  .command("paste")
  .description("Paste the local clipboard image into a remote agent pane.")
  .option("--host <host>", "SSH host alias", "vibeps")
  .option("--target <pane>", "tmux target pane id")
  .action(async (options: { host: string; target?: string }) => {
    const config = await loadConfig({ host: options.host });
    await pasteClipboardImage(config, options.target);
  });

program
  .command("cleanup")
  .description("Remove old staged remote images.")
  .option("--host <host>", "SSH host alias", "vibeps")
  .option("--max-age-seconds <seconds>", "Delete images older than this many seconds", "86400")
  .action(async (options: { host: string; maxAgeSeconds: string }) => {
    const config = await loadConfig({ host: options.host });
    await cleanupRemoteImages(config, Number.parseInt(options.maxAgeSeconds, 10));
  });

program
  .command("daemon")
  .description("Run the optional macOS hotkey daemon.")
  .action(() => {
    console.log("daemon placeholder");
  });

program.parse();
