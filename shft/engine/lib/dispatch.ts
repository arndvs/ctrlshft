import type { WorkflowRunner, DispatchContext } from "./types.js";

const registry = new Map<string, WorkflowRunner>();

export function registerWorkflow(name: string, runner: WorkflowRunner): void {
  if (registry.has(name)) {
    throw new Error(`Workflow already registered: ${name}`);
  }
  registry.set(name, runner);
}

export function getWorkflow(name: string): WorkflowRunner {
  const runner = registry.get(name);
  if (!runner) {
    const available = [...registry.keys()].sort().join(", ");
    throw new Error(`Unknown workflow: ${name}. Available: ${available}`);
  }
  return runner;
}

export function listWorkflows(): string[] {
  return [...registry.keys()].sort();
}

export async function dispatch(ctx: DispatchContext): Promise<void> {
  const runner = getWorkflow(ctx.workflow);
  await runner(ctx);
}

export function clearRegistry(): void {
  registry.clear();
}
