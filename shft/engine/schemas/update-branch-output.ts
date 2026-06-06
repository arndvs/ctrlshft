import { z } from "zod";

export const UpdateBranchOutput = z.object({
  strategy: z.enum(["rebase", "merge"]),
  success: z.boolean(),
  conflictsResolved: z.array(z.string()).default([]),
  conflictsRemaining: z.array(z.string()).default([]),
  commitSha: z.string().optional(),
});

export type UpdateBranchOutput = z.infer<typeof UpdateBranchOutput>;
