import { spawnSync } from "node:child_process";
import { describe, expect, it } from "vitest";

describe("remote helper", () => {
  it("exposes cleanup daemon commands in usage", () => {
    const result = spawnSync("bash", ["remote/ssh-bin-paste-remote.sh"], {
      encoding: "utf8",
    });
    expect(result.status).toBe(2);
    expect(result.stderr).toContain("daemon-start");
  });
});
