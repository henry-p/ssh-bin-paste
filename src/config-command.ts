import { spawn } from "node:child_process";
import { configPath, ensureConfigFile } from "./config.js";
import { parseShellWords, runLocal } from "./ssh.js";

export interface ConfigCommandOptions {
  path?: boolean;
  editor?: string;
}

export async function runConfigCommand(options: ConfigCommandOptions): Promise<void> {
  if (options.path) {
    console.log(configPath());
    return;
  }

  const path = await ensureConfigFile();
  const editorCommand = options.editor ?? process.env.VISUAL ?? process.env.EDITOR;
  if (editorCommand && editorCommand.trim().length > 0) {
    await runEditor(editorCommand, path);
    return;
  }

  if (process.platform === "darwin") {
    const result = await runLocal("open", ["-t", path]);
    if (result.exitCode !== 0) throw new Error(result.stderr.trim() || `Failed to open ${path}`);
    console.log(`opened ${path}`);
    return;
  }

  console.log(path);
}

async function runEditor(editorCommand: string, path: string): Promise<void> {
  const parts = parseShellWords(editorCommand);
  if (parts.length === 0) throw new Error("Editor command is empty");
  await new Promise<void>((resolve, reject) => {
    const child = spawn(parts[0], [...parts.slice(1), path], { stdio: "inherit" });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`Editor exited with code ${code ?? 1}`));
    });
  });
}
