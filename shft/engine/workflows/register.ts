import { registerWorkflow } from "../lib/dispatch.js";
import { runAddressReview } from "./address-review.js";
import { runArchitectureReview } from "./architecture-review.js";
import { runImplementIssue } from "./implement-issue.js";
import { runImplementPr } from "./implement-pr.js";
import { runImplementPrd } from "./implement-prd.js";
import { runParallel } from "./parallel.js";
import { runReview } from "./review.js";
import { runReviewIssue } from "./review-issue.js";
import { runToIssuesPrd } from "./to-issues-prd.js";
import { runUpdateBranch } from "./update-branch.js";
import { runWritePr } from "./write-pr.js";

export function registerAllWorkflows(): void {
  registerWorkflow("address-review", runAddressReview);
  registerWorkflow("architecture-review", runArchitectureReview);
  registerWorkflow("implement-issue", runImplementIssue);
  registerWorkflow("implement-pr", runImplementPr);
  registerWorkflow("implement-prd", runImplementPrd);
  registerWorkflow("parallel", runParallel);
  registerWorkflow("review", runReview);
  registerWorkflow("review-issue", runReviewIssue);
  registerWorkflow("to-issues-prd", runToIssuesPrd);
  registerWorkflow("update-branch", runUpdateBranch);
  registerWorkflow("write-pr", runWritePr);
}
