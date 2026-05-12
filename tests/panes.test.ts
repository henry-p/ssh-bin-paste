import { describe, expect, it } from "vitest";
import { parsePaneLine } from "../src/panes.js";

describe("parsePaneLine", () => {
  it("parses tmux pane format and scores likely agents", () => {
    const pane = parsePaneLine("agent\t0.0\t%4\t1234\tnode\t/root\tcodex");
    expect(pane.sessionName).toBe("agent");
    expect(pane.windowPane).toBe("0.0");
    expect(pane.paneId).toBe("%4");
    expect(pane.score).toBeGreaterThan(0);
  });
});

