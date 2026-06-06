import { z } from "zod";

export const WritePrOutput = z.object({
  title: z.string().min(1).max(256),
  body: z.string().min(1),
  labels: z.array(z.string()).default([]),
});

export type WritePrOutput = z.infer<typeof WritePrOutput>;
