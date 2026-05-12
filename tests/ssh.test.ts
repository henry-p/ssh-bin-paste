import { describe, expect, it } from "vitest";
import { remotePathExpr, shellQuote } from "../src/ssh.js";

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

