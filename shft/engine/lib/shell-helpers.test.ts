import { describe, it, expect, vi, beforeEach } from "vitest";
import * as childProcess from "node:child_process";
import { sh, trySh, getOwnerRepo } from "./shell-helpers.js";

vi.mock("node:child_process", () => ({
  execFileSync: vi.fn(),
}));

const mockExecFileSync = vi.mocked(childProcess.execFileSync);

describe("sh", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("calls execFileSync with correct args", () => {
    mockExecFileSync.mockReturnValue("output\n");
    const result = sh({ cmd: "echo", args: ["hello"] });
    expect(result).toBe("output");
    expect(mockExecFileSync).toHaveBeenCalledWith("echo", ["hello"], expect.objectContaining({ encoding: "utf8" }));
  });

  it("passes cwd when provided", () => {
    mockExecFileSync.mockReturnValue("ok\n");
    sh({ cmd: "ls", args: [], cwd: "/tmp" });
    expect(mockExecFileSync).toHaveBeenCalledWith("ls", [], expect.objectContaining({ cwd: "/tmp" }));
  });

  it("throws on command failure", () => {
    mockExecFileSync.mockImplementation(() => { throw new Error("command failed"); });
    expect(() => sh({ cmd: "false", args: [] })).toThrow("command failed");
  });
});

describe("trySh", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns ok:true on success", () => {
    mockExecFileSync.mockReturnValue("output\n");
    const result = trySh({ cmd: "echo", args: ["hi"] });
    expect(result.ok).toBe(true);
    expect(result.stdout).toBe("output");
  });

  it("returns ok:false on failure", () => {
    mockExecFileSync.mockImplementation(() => { throw new Error("fail"); });
    const result = trySh({ cmd: "false", args: [] });
    expect(result.ok).toBe(false);
    expect(result.stdout).toBe("");
  });
});

describe("getOwnerRepo", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("parses owner/repo from gh output", () => {
    mockExecFileSync.mockReturnValue("octocat/hello-world\n");
    const result = getOwnerRepo({ cwd: "/tmp" });
    expect(result).toEqual({ owner: "octocat", repo: "hello-world" });
  });

  it("throws on unexpected format", () => {
    mockExecFileSync.mockReturnValue("invalid\n");
    expect(() => getOwnerRepo({ cwd: "/tmp" })).toThrow(/Cannot parse owner\/repo/);
  });
});
