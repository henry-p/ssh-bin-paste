import { describe, expect, it } from "vitest";
import { parseShellWords, remotePathExpr, shellQuote, sshArgs } from "../src/ssh.js";

describe("shellQuote", () => {
  it("quotes single quotes safely", () => {
    expect(shellQuote("a'b")).toBe("'a'\\''b'");
  });
});

describe("remotePathExpr", () => {
  it("expands home-relative paths on the remote shell", () => {
    expect(remotePathExpr("~/.cache/x")).toBe("\"$HOME/.cache/x\"");
  });

  it("single-quotes non-home paths", () => {
    expect(remotePathExpr("/tmp/x")).toBe("'/tmp/x'");
  });
});

describe("parseShellWords", () => {
  it("parses quoted ssh commands", () => {
    expect(parseShellWords("ssh -i ~/.ssh/example_ed25519 root@203.0.113.10")).toEqual([
      "ssh",
      "-i",
      "~/.ssh/example_ed25519",
      "root@203.0.113.10",
    ]);
    expect(parseShellWords("ssh -o 'ProxyJump jump host' user@example")).toEqual(["ssh", "-o", "ProxyJump jump host", "user@example"]);
  });
});

describe("sshArgs", () => {
  it("uses host aliases directly", () => {
    expect(sshArgs("vibeps", "printf ok")).toEqual(["ssh", "vibeps", "printf ok"]);
  });

  it("appends remote command to full ssh commands", () => {
    const args = sshArgs({ host: "ignored", sshCommand: "ssh -i ~/.ssh/example_ed25519 root@203.0.113.10" }, "printf ok");
    expect(args[0]).toBe("ssh");
    expect(args.at(-1)).toBe("printf ok");
    expect(args).toContain("root@203.0.113.10");
    expect(args.find((arg) => arg.endsWith("/.ssh/example_ed25519"))).toBeTruthy();
  });
});
