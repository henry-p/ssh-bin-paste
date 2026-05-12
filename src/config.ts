import { mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

export interface AgentProfile {
  command: string;
}

export interface AppConfig {
  host: string;
  tmuxSession: string;
  remoteCacheDir: string;
  remoteHelperPath: string;
  targetPane?: string;
  agents: Record<string, AgentProfile>;
  daemon: {
    shortcut: string;
    hijackPaste: boolean;
    allowlistedApps: string[];
  };
}

export interface ConfigOverrides {
  host?: string;
}

const DEFAULT_CONFIG: AppConfig = {
  host: "vibeps",
  tmuxSession: "agent",
  remoteCacheDir: "~/.cache/ssh-bin-paste/images",
  remoteHelperPath: "~/.local/bin/ssh-bin-paste-remote",
  agents: {
    codex: { command: "codex" },
    claude: { command: "claude" },
  },
  daemon: {
    shortcut: "cmd+shift+v",
    hijackPaste: false,
    allowlistedApps: [
      "com.googlecode.iterm2",
      "com.apple.Terminal",
      "com.github.wez.wezterm",
      "com.mitchellh.ghostty",
      "com.termius-dmg.mac",
    ],
  },
};

export function configPath(): string {
  const xdg = process.env.XDG_CONFIG_HOME;
  return join(xdg && xdg.length > 0 ? xdg : join(homedir(), ".config"), "ssh-bin-paste", "config.json");
}

export async function loadConfig(overrides: ConfigOverrides = {}): Promise<AppConfig> {
  const fromDisk = await readConfigFile();
  const merged: AppConfig = {
    ...DEFAULT_CONFIG,
    ...fromDisk,
    agents: {
      ...DEFAULT_CONFIG.agents,
      ...(fromDisk?.agents ?? {}),
    },
    daemon: {
      ...DEFAULT_CONFIG.daemon,
      ...(fromDisk?.daemon ?? {}),
    },
  };
  return {
    ...merged,
    ...overrides,
  };
}

export async function saveConfigPatch(patch: Partial<AppConfig>): Promise<AppConfig> {
  const existing = await readConfigFile();
  const next = {
    ...(existing ?? {}),
    ...patch,
    agents: {
      ...(existing?.agents ?? {}),
      ...(patch.agents ?? {}),
    },
    daemon: {
      ...(existing?.daemon ?? {}),
      ...(patch.daemon ?? {}),
    },
  };
  await mkdir(dirname(configPath()), { recursive: true });
  await writeFile(configPath(), `${JSON.stringify(next, null, 2)}\n`, "utf8");
  return loadConfig();
}

export function resolveAgentCommand(config: AppConfig, agent: string): string {
  return config.agents[agent]?.command ?? agent;
}

async function readConfigFile(): Promise<Partial<AppConfig> | null> {
  try {
    return JSON.parse(await readFile(configPath(), "utf8")) as Partial<AppConfig>;
  } catch (error) {
    if (isMissingFile(error)) return null;
    throw new Error(`Failed to read ${configPath()}: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function isMissingFile(error: unknown): boolean {
  return typeof error === "object" && error !== null && "code" in error && error.code === "ENOENT";
}
