import { describe, it, expect } from "vitest";
import { Semaphore } from "./semaphore.js";

describe("Semaphore", () => {
  it("allows up to maxConcurrent tasks", async () => {
    const sem = new Semaphore(2);
    let running = 0;
    let maxRunning = 0;

    const task = () => sem.run(async () => {
      running++;
      maxRunning = Math.max(maxRunning, running);
      await new Promise((r) => setTimeout(r, 50));
      running--;
    });

    await Promise.all([task(), task(), task(), task()]);
    expect(maxRunning).toBe(2);
  });

  it("runs tasks sequentially with concurrency 1", async () => {
    const sem = new Semaphore(1);
    const order: number[] = [];

    const task = (id: number) => sem.run(async () => {
      order.push(id);
      await new Promise((r) => setTimeout(r, 10));
    });

    await Promise.all([task(1), task(2), task(3)]);
    expect(order).toEqual([1, 2, 3]);
  });

  it("propagates errors from tasks", async () => {
    const sem = new Semaphore(2);
    await expect(sem.run(async () => { throw new Error("boom"); })).rejects.toThrow("boom");
  });

  it("releases slot even when task throws", async () => {
    const sem = new Semaphore(1);
    await sem.run(async () => { throw new Error("fail"); }).catch(() => {});
    // Should be able to run another task after the failure
    const result = await sem.run(async () => "ok");
    expect(result).toBe("ok");
  });
});
