import { describe, expect, it } from "vitest";
import { AppConfig, resolveAgentCommand } from "../src/config.js";

const config = {
  agents: {
    codex: { command: "codex" },
    claude: { command: "claude --model sonnet" },
  },
} as AppConfig;

describe("resolveAgentCommand", () => {
  it("resolves configured agent profiles", () => {
    expect(resolveAgentCommand(config, "claude")).toBe("claude --model sonnet");
  });

  it("treats unknown agents as commands", () => {
    expect(resolveAgentCommand(config, "my-agent")).toBe("my-agent");
  });
});

