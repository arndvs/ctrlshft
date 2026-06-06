import { z } from "zod";
import { InlineCommentSchema, ThreadReplySchema } from "./shared.js";

export const ReviewOutput = z.object({
  summary: z.string().min(1),
  inlineComments: z.array(InlineCommentSchema).default([]),
  replies: z.array(ThreadReplySchema).default([]),
});

export type ReviewOutput = z.infer<typeof ReviewOutput>;
