import { z } from "zod";
import { InlineCommentSchema, ThreadReplySchema } from "./shared.js";

export const ImplementPrOutput = z.object({
  threadReplies: z.array(ThreadReplySchema).default([]),
  newInlineComments: z.array(InlineCommentSchema).default([]),
  topLevelComments: z
    .array(
      z.object({
        body: z.string().min(1),
      }),
    )
    .default([]),
});

export type ImplementPrOutput = z.infer<typeof ImplementPrOutput>;
