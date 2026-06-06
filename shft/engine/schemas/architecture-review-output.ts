import { z } from "zod";

export const ArchitectureReviewOutput = z.object({
  findings: z.array(
    z.object({
      area: z.string().min(1),
      severity: z.enum(["critical", "warning", "info"]),
      description: z.string().min(1),
      recommendation: z.string().min(1),
    }),
  ).default([]),
  prdSuggestions: z.array(
    z.object({
      title: z.string().min(1),
      description: z.string().min(1),
    }),
  ).default([]),
  summary: z.string().min(1),
});

export type ArchitectureReviewOutput = z.infer<typeof ArchitectureReviewOutput>;
