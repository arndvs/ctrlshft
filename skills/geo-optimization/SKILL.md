---
name: geo-optimization
description: Audit and optimize content for AI search citability. Use when improving chances of being cited by ChatGPT, Perplexity, Claude, or other AI models that retrieve and synthesize web content.
---

# GEO Optimization

Generative Engine Optimization. This skill audits content for AI search citability using the CITE framework and provides specific recommendations to improve the likelihood that AI models will cite your content as a source.

## When to Use This Skill

- Auditing existing content for AI search citability
- Creating new content designed for AI search visibility
- Analyzing why competitors get cited and you don't
- Improving content structure for machine readability
- Evaluating content after AI search testing
- Building a content strategy that serves both Google and AI interfaces

## How AI Models Select Sources

### The Three Layers

**Layer 1: Training Data**
Models learn from the web during training. Content that appears across multiple authoritative sources gets absorbed into model weights. This is a long-term play. Consistent, high-quality publishing builds presence in future training data. Not directly optimizable per-query, but directionally important.

**Layer 2: Retrieval**
Perplexity, ChatGPT with browsing, Claude with web search, and Google AI Overviews all retrieve real-time content. They search, read pages, and select which sources to use. This layer is directly optimizable. What you write and how you structure it determines whether your content gets retrieved and read.

**Layer 3: Citation Selection**
After reading 5-10 sources, the model cites 2-3 in its answer. This is where competition happens. The model has options. It selects based on relevance, specificity, authority, and extractability.

### Citation Selection Patterns

Based on observable behavior across multiple AI search tools:

| Gets Cited | Gets Skipped |
|-----------|-------------|
| Direct, specific answers to the query | Vague overviews that hedge every claim |
| Original data, statistics, research | Repackaged secondary content |
| Clear structure with extractable claims | Walls of text without clear takeaways |
| Named entities and specific details | Generic advice without examples |
| Authoritative domain with expertise signals | Thin content on generic domains |
| Recent, dated content on time-sensitive topics | Undated or clearly stale content |
| Content that commits to a position | Content that lists every option without evaluating |

## The CITE Framework

### C — Citable Structure

Content organized so individual claims can be extracted by a model without requiring full-page context.

**Checklist:**

| Element | Citable | Not Citable |
|---------|---------|-------------|
| Paragraph structure | Each paragraph makes one clear, extractable claim | Paragraphs blend multiple ideas with no clear takeaway |
| Headers | Specific, descriptive ("How to Calculate CAC" ) | Vague or clever ("Getting Started," "The Big Picture") |
| Data presentation | Tables and lists with concrete data points | Data buried inside prose paragraphs |
| Definitions | Clear, direct definitions when introducing terms | Terms used without explanation |
| Answers | Direct answer in first sentence, then elaboration | Answer buried after three paragraphs of context |

**The Inverted Pyramid Test:**
For any section, can you read just the first sentence of each paragraph and get the key claims? If yes, the content is citable. If no, restructure.

**Practical actions:**
- Lead each section with its strongest, most specific claim
- Use headers that contain the keyword or question being answered
- Put data in tables rather than embedding numbers in prose
- Write topic sentences that stand alone as quotable facts
- Break long paragraphs into single-claim paragraphs

### I — Information Density

Every paragraph adds something the reader (or model) couldn't get from a generic source.

**Density scoring:**

| Density Level | What It Looks Like |
|---------------|-------------------|
| High | Original data, specific percentages, named case studies, first-party research, unique analysis |
| Medium | Curated examples, specific recommendations with reasoning, expert attribution with names |
| Low | General advice that applies to everything, "experts say" without naming them, restated common knowledge |
| Zero | Filler paragraphs, throat-clearing intros, conclusion summaries that repeat earlier content |

**Information types that increase density:**
- Specific numbers ("43% of users abandon" vs. "many users abandon")
- Named examples ("Stripe's onboarding flow" vs. "a popular SaaS company")
- Original analysis (your interpretation of data, not restating someone else's)
- Concrete steps ("Set X to Y in Z" vs. "configure your settings appropriately")
- Comparisons with specifics ("Tool A costs $49/mo and includes X; Tool B costs $79/mo but adds Y")
- Timelines and benchmarks ("expect results in 2-4 weeks with 1,000+ monthly visitors")

**The Replacement Test:**
For any paragraph, ask: could this paragraph appear in any article on this topic? If yes, it's generic. Replace with something only you could write based on your data, experience, or analysis.

### T — Topical Authority

Retrieval systems assess whether a source has depth and credibility in the topic area.

**Authority signals:**

| Signal | How to Build It |
|--------|----------------|
| Content depth | Multiple articles covering the same topic from different angles |
| Internal linking | Pieces that reference and link to each other |
| Author expertise | Visible credentials, bio, verifiable experience |
| Publishing consistency | Regular content in the same domain over months/years |
| External validation | Other authoritative sources citing or linking to your content |
| Content freshness | Updated dates, current information, maintained accuracy |

**Topical authority audit questions:**
1. How many pieces do you have on this topic? (1 piece = weak, 5+ = strong)
2. Do pieces link to each other? (Isolated pieces = weak, interconnected = strong)
3. Is author expertise visible on the page? (Anonymous = weak, credentials shown = strong)
4. How recently was content updated? (2+ years old = weak, <6 months = strong)
5. Do other sites reference your content? (No inbound references = weak)

**Building authority over time:**
- Create a pillar page on your core topic
- Build supporting content that covers subtopics in depth
- Link supporting content to and from the pillar page
- Update content when information changes
- Add original data or research when available

### E — Entity Clarity

AI models parse content using entities: named people, companies, products, concepts. Clear entity usage makes content easier for models to understand, categorize, and cite.

**Entity clarity checklist:**
- Use proper nouns consistently (don't alternate between "the company," "the firm," "the organization")
- Define terms when first introduced
- Use the same name for the same entity throughout (pick "Google Analytics 4" or "GA4" and stick with one)
- Include structured data (schema markup) that reinforces entity relationships
- Answer "what is X" directly when introducing a concept
- Name people, companies, and products rather than using vague references

**Schema markup for entity clarity:**
- Article schema with author information
- Organization schema for your business
- FAQ schema for question-and-answer content
- HowTo schema for procedural content

(See `seo-technical` skill for implementation details.)

## AI Search Query Classification

Different query types require different optimization approaches:

| Query Type | Example | What Gets Cited |
|-----------|---------|-----------------|
| Informational | "What is conversion rate optimization?" | Clear definitions, comprehensive explanations, authoritative sources |
| Comparative | "Notion vs. Asana for project management" | Specific feature comparisons, honest tradeoffs, hands-on experience |
| Recommendation | "Best email marketing tool for small business" | Opinionated recommendations with reasoning, specific use cases, pricing details |
| How-to | "How to set up Google Analytics 4" | Step-by-step instructions, specific settings, screenshots/details |
| Current events | "Latest changes to Instagram algorithm" | Dated content, recent publication, specific details about what changed |

**Optimize based on the queries you want to appear in.** Informational queries reward depth and definitions. Comparative queries reward specifics and honest tradeoffs. Recommendation queries reward opinionated, well-reasoned positions.

## Red Flags

Issues that reduce AI search citability:

- [ ] Content summarizes others without adding original insight
- [ ] No specific data, numbers, or named examples in the entire piece
- [ ] Headers are vague ("Introduction," "Overview," "Conclusion," "Key Takeaways")
- [ ] No author attribution or visible expertise signals
- [ ] Content is undated on a time-sensitive topic
- [ ] No single paragraph directly answers a specific question
- [ ] Content hedges every claim ("it depends," "results may vary" as the entire position)
- [ ] Entities referenced vaguely ("a leading company" instead of naming it)
- [ ] Content is thin on a topic competitors cover in depth
- [ ] No internal links to related content on the same topic
- [ ] Page has no schema markup
- [ ] Content reads identically to 10 other articles on the same topic

## Output Format

When auditing content for AI search citability:

```
## GEO Audit: [Content Title/URL]

### CITE Framework Score

| Dimension | Score (1-5) | Key Issues |
|-----------|------------|------------|
| Citable Structure | ___ | [Primary issue] |
| Information Density | ___ | [Primary issue] |
| Topical Authority | ___ | [Primary issue] |
| Entity Clarity | ___ | [Primary issue] |
| **Overall** | **___** | |

### Target Query Analysis
| Query This Should Answer | Would It Get Cited? | Why/Why Not |
|--------------------------|-------------------|-------------|
| [Query 1] | Yes/No/Maybe | [Reason] |
| [Query 2] | Yes/No/Maybe | [Reason] |

### Citable Structure Assessment
- Extractable claims per section: [Assessment]
- Header specificity: [Assessment]
- Inverted pyramid structure: [Present/Missing]
- Key issue: [Most important structural problem]

### Information Density Assessment
- Original data/research: [Present/Missing]
- Named examples: [Count and quality]
- Specific vs. generic ratio: [Assessment]
- Key issue: [Most important density problem]

### Topical Authority Assessment
- Related content on domain: [Count]
- Internal linking: [Present/Missing]
- Author credentials visible: [Yes/No]
- Content freshness: [Date and assessment]
- Key issue: [Most important authority problem]

### Entity Clarity Assessment
- Consistent entity naming: [Yes/No]
- Terms defined: [Yes/No]
- Schema markup: [Present/Missing]
- Key issue: [Most important clarity problem]

### Prioritized Recommendations

| Priority | Recommendation | CITE Dimension | Expected Impact |
|----------|---------------|----------------|-----------------|
| 1 | [Specific action] | [C/I/T/E] | [High/Med/Low] |
| 2 | [Specific action] | [C/I/T/E] | [High/Med/Low] |
| 3 | [Specific action] | [C/I/T/E] | [High/Med/Low] |
| 4 | [Specific action] | [C/I/T/E] | [High/Med/Low] |
| 5 | [Specific action] | [C/I/T/E] | [High/Med/Low] |

### Quick Wins
[Changes that take <1 hour and meaningfully improve citability]

### Structural Improvements
[Changes that require more work but have lasting impact]

### Rewrite Suggestions
[If specific sections need rewriting, provide guidance on what to change]
```

## Testing Your Optimization

After making changes, test effectiveness:

1. **Run AI search queries** that your content should answer
2. **Document** which sources get cited (including yours or not)
3. **Compare** cited sources against your updated content
4. **Re-run** the same queries 1-2 weeks later to track changes
5. **Iterate** based on what you observe

Testing template:

```
QUERY: _______________
MODEL: [ChatGPT / Perplexity / Claude]
DATE: _______________

CITED: [Yes/No]
SOURCES CITED: [List URLs]
WHAT CITED SOURCES HAVE THAT MINE DOESN'T: _______________
ACTION: _______________
```

## Chaining to Other Skills

GEO optimization connects to broader search strategy:

- **Technical issues blocking retrieval** → Chain to `seo-technical` for crawlability and schema
- **Content not ranking on Google either** → Chain to `seo-audit` for on-page optimization
- **Competitors dominating both channels** → Chain to `competitor-seo` for gap analysis
- **Need to build topical authority at scale** → Chain to `programmatic-seo` for content volume

When chaining, pass along: CITE scores, specific gaps identified, AI search test results.
