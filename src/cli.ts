#!/usr/bin/env node
import { Command } from "commander";
import { loadConfig, resolveAgentCommand } from "./config.js";
import { runDoctor } from "./doctor.js";

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
  .action((options: { host: string }) => {
    console.log(`install-remote placeholder for ${options.host}`);
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
  .action(async (options: { host: string }) => {
    await loadConfig({ host: options.host });
    console.log(`panes placeholder for ${options.host}`);
  });

program
  .command("paste")
  .description("Paste the local clipboard image into a remote agent pane.")
  .option("--host <host>", "SSH host alias", "vibeps")
  .action(async (options: { host: string }) => {
    await loadConfig({ host: options.host });
    console.log(`paste placeholder for ${options.host}`);
  });

program
  .command("cleanup")
  .description("Remove old staged remote images.")
  .option("--host <host>", "SSH host alias", "vibeps")
  .action(async (options: { host: string }) => {
    await loadConfig({ host: options.host });
    console.log(`cleanup placeholder for ${options.host}`);
  });

program
  .command("daemon")
  .description("Run the optional macOS hotkey daemon.")
  .action(() => {
    console.log("daemon placeholder");
  });

program.parse();
