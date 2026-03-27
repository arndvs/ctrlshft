---
name: programmatic-seo
description: Strategy and execution for building SEO-optimized pages at scale using templates and structured data. Use for comparison pages, location pages, glossaries, or any template-based content program.
---

# Programmatic SEO

Build dozens or hundreds of search-optimized pages from structured data and templates. This skill covers page type selection, template design, data sourcing, quality control, and launch strategy for scalable content programs.

## When to Use This Skill

- Planning a scalable content program
- Designing page templates for a content type
- Building comparison, location, or resource pages at volume
- Evaluating whether programmatic SEO fits your business
- Quality-checking template-generated pages
- Planning launch and indexation strategy for large page sets

## Is Programmatic SEO Right for You?

### Qualification Checklist

Programmatic SEO works when:

- [ ] There's a repeatable page structure (comparison, location, tool, glossary)
- [ ] You have or can get structured data to populate pages
- [ ] Each page targets a different keyword with real search volume
- [ ] Each page can provide genuine unique value (not just variable swaps)
- [ ] The topic area has enough variations to justify the approach
- [ ] You can maintain and update pages over time

Programmatic SEO doesn't work when:
- Every page would say essentially the same thing with different keywords inserted
- There's no structured data to differentiate pages
- The target keywords have zero or negligible search volume
- You can't add unique value beyond what a simple database query would return

## Page Type Selection

### High-Value Programmatic Page Types

| Page Type | Template Logic | Example | Data Source |
|-----------|---------------|---------|-------------|
| **Comparison pages** | "[A] vs [B]" with feature matrix | "Notion vs Asana for project management" | Product feature databases, pricing pages |
| **Alternatives pages** | "Best [A] alternatives" with ranked options | "Best Mailchimp alternatives for small business" | Competitor research, feature comparison |
| **Location pages** | "[Service] in [City]" with local details | "Web design agencies in Austin" | Location data, local business info |
| **Tool/resource pages** | "[Type] tool: [description]" | "ROI calculator for SaaS businesses" | Internal tools, calculators, datasets |
| **Glossary/definition pages** | "What is [term]" with explanation | "What is customer acquisition cost?" | Industry terminology |
| **Best-of pages** | "Best [X] for [Y]" with recommendations | "Best CRM for freelancers" | Product reviews, feature data |
| **Stats/data pages** | "[Topic] statistics [year]" | "Email marketing statistics 2025" | Research, surveys, public data |
| **Integration pages** | "[Product] + [Product] integration" | "Slack + Asana integration guide" | Integration documentation |

### Choosing Your Page Type

**Questions to answer:**

1. What does your audience search for repeatedly with slight variations?
2. What structured data do you have access to (or can build)?
3. Which page type aligns with your product or service?
4. Where are competitors NOT doing this well?

**Volume assessment:**
- List all possible variations (cities, products, terms, comparisons)
- Check search volume for a sample of 10-20 variations
- If 50%+ have meaningful search volume, the program is viable
- If <20% have volume, narrow the scope or choose a different page type

## Template Design

### Template Anatomy

Every programmatic page has three layers:

**Fixed content** (same on every page):
- Page structure and section order
- Methodology explanation
- CTA and navigation elements
- Boilerplate (disclaimers, update notes)

**Variable content** (changes per page, pulled from data):
- Entity names, features, pricing
- Location-specific details
- Comparison data points
- Category-specific information

**Unique content** (generated or written per page):
- Analysis or commentary specific to this combination
- Recommendations based on the specific data
- Context that can't be templated
- Original insight that justifies the page's existence

### The Unique Value Requirement

This is the line between useful programmatic SEO and spam.

**Every page must answer:** "What does this page give the reader that they couldn't get by just looking at a simple list or database?"

| Acceptable Unique Value | Not Enough |
|------------------------|------------|
| Analysis of tradeoffs specific to this comparison | Same two paragraphs with product names swapped |
| Recommendation based on use case | Generic "it depends on your needs" |
| Original data or testing results | Restating feature lists from product websites |
| Context about when each option is better | Identical structure with only names changed |
| Expert commentary on specific strengths/weaknesses | Auto-generated sentences with keyword insertion |

### Template Structure Example

**Comparison page template: "[Product A] vs [Product B]"**

```
1. HEADER
   - H1: "[A] vs [B]: [Specific angle or year]"
   - Quick verdict (2-3 sentences summarizing recommendation)
   - Last updated date

2. QUICK COMPARISON TABLE
   - Key features side by side
   - Pricing
   - Best for [use case]
   [Data: pulled from product database]

3. [PRODUCT A] OVERVIEW
   - What it is and who it's for
   - Key strengths
   - Notable limitations
   [Variable: product-specific data + unique analysis]

4. [PRODUCT B] OVERVIEW
   - Same structure as above
   [Variable: product-specific data + unique analysis]

5. DETAILED COMPARISON
   - Feature-by-feature breakdown
   - Category scores with reasoning
   [Variable: feature data | Unique: analysis per category]

6. USE CASE RECOMMENDATIONS
   - Best for [use case 1]: [Winner] because [reason]
   - Best for [use case 2]: [Winner] because [reason]
   - Best for [use case 3]: [Winner] because [reason]
   [Unique: recommendations require judgment, not just data]

7. VERDICT
   - Overall recommendation with nuance
   - When to choose A, when to choose B
   [Unique: must be specific to this comparison]

8. FAQ
   - 3-5 questions specific to this comparison
   [Variable: some templated | Unique: answers specific to pair]
```

## Data Source Strategy

### Where to Get Data

| Source Type | Examples | Pros | Cons |
|-------------|---------|------|------|
| Public APIs | Government data, financial markets | Accurate, updatable | Limited scope |
| Product websites | Feature pages, pricing pages | Current | Manual collection, changes often |
| Your own research | Surveys, testing, analysis | Unique (major advantage) | Time-intensive |
| Public datasets | Census, industry reports | Large scale | May be outdated |
| Scraping (ethical) | Public pages with permission | Comprehensive | Legal considerations, maintenance |
| Manual curation | Expert review and compilation | High quality | Doesn't scale infinitely |

### Data Quality Requirements

| Requirement | Why |
|-------------|-----|
| Accurate | Wrong data destroys credibility and risks penalties |
| Current | Outdated pricing/features create bad user experience |
| Complete | Missing data creates thin pages |
| Structured | Must be parseable for template population |
| Maintainable | You need a process to keep data updated |

## Quality Control

### Pre-Launch Quality Checklist

**For every page in the set:**
- [ ] Title tag is unique and keyword-targeted
- [ ] Meta description is unique and compelling
- [ ] H1 is unique and matches title
- [ ] Content makes sense when read by a human
- [ ] No placeholder text or template artifacts left in
- [ ] Unique value section actually provides unique analysis
- [ ] All data is accurate and current
- [ ] Internal links to related pages work
- [ ] Page loads properly on mobile

**For the page set as a whole:**
- [ ] No two pages have substantially identical content
- [ ] Internal linking architecture connects related pages
- [ ] Navigation/index page exists for the collection
- [ ] Schema markup consistent across the set
- [ ] Canonical tags properly implemented
- [ ] XML sitemap updated with new pages

### Quality Sampling

Don't check every page manually. Use a sampling strategy:

1. **Check 100%** of the first 10 pages launched
2. **Random sample 10%** of remaining pages
3. **Spot-check** pages with unusual data points
4. **Monitor** Search Console for crawl errors and coverage issues

### Common Quality Failures

| Failure | Symptom | Fix |
|---------|---------|-----|
| Template artifacts | "[PRODUCT_NAME] is a great tool" with brackets visible | Audit template population logic |
| Thin pages | Pages with <200 words of actual content | Add analysis sections, increase unique content |
| Duplicate content | Google showing "duplicate, submitted URL not selected" | Ensure each page has sufficient unique content |
| Keyword cannibalization | Pages competing for same keyword | Differentiate targeting, consolidate if needed |
| Stale data | Prices or features outdated | Build update schedule, automate where possible |

## Internal Linking Architecture

### Hub-and-Spoke Model

```
HUB: Category index page
  ├── SPOKE: Individual page 1
  ├── SPOKE: Individual page 2
  ├── SPOKE: Individual page 3
  └── SPOKE: Individual page 4
      (Each spoke links to hub and 2-3 related spokes)
```

**Implementation:**
- Hub page links to all spokes (or top spokes with "see all")
- Each spoke links back to hub
- Each spoke links to 2-3 most related spokes
- Use descriptive anchor text (not "click here" or "learn more")
- Include breadcrumbs: Home > Category > Page

### Cross-Linking Between Page Sets

If you have multiple programmatic content types (comparisons AND location pages), cross-link where relevant:
- Comparison page mentions a city → link to location page
- Location page mentions a product → link to comparison page

## Launch Strategy

### Staged Launch (Recommended)

Don't publish 200 pages at once. Search engines handle gradual additions better.

| Phase | Pages | Duration | Purpose |
|-------|-------|----------|---------|
| Pilot | 5-10 pages | 1-2 weeks | Test template, verify indexing, check quality |
| Batch 1 | 20-30 pages | 1-2 weeks | Confirm at scale, monitor Search Console |
| Batch 2 | 50-100 pages | 2-4 weeks | Full rollout, ongoing monitoring |
| Remaining | Rest | 2-4 weeks | Complete the set |

**After each phase, check:**
- Are pages being indexed?
- Any crawl errors in Search Console?
- Are pages generating impressions?
- Any quality issues surfacing?

### Post-Launch Monitoring

| Metric | Check Frequency | Where |
|--------|----------------|-------|
| Index coverage | Weekly (first month), then monthly | Search Console > Pages |
| Crawl errors | Weekly (first month), then monthly | Search Console > Pages |
| Impressions/clicks | Weekly | Search Console > Performance |
| Rankings for target keywords | Monthly | Search Console or rank tracker |
| Content quality flags | Monthly | Manual spot-check |

## Red Flags

Issues that commonly kill programmatic SEO programs:

- [ ] Pages are thin with only variable data swapped and no unique analysis
- [ ] No real differentiation between pages beyond keyword/entity insertion
- [ ] Content reads as obviously AI-generated or template-filled
- [ ] No internal linking connecting the page set
- [ ] Targeting keywords with zero or negligible search volume
- [ ] Publishing hundreds of pages simultaneously
- [ ] No plan for keeping data accurate and current
- [ ] Pages exist for search engines but provide no value to humans
- [ ] No quality control process before or after launch
- [ ] Template produces grammatically broken sentences with certain data inputs
- [ ] Duplicate page titles or meta descriptions across the set
- [ ] No index or hub page organizing the collection

## Output Format

When planning a programmatic SEO program:

```
## Programmatic SEO Plan: [Page Type]

### Concept
- Page type: [Comparison / Location / Glossary / etc.]
- Target keyword pattern: "[Pattern]"
- Estimated pages: [Count]
- Data source: [Where data comes from]

### Search Volume Assessment
| Sample Keyword | Monthly Volume | Competition |
|---------------|---------------|-------------|
| [Variation 1] | [Volume] | [High/Med/Low] |
| [Variation 2] | [Volume] | [High/Med/Low] |
| [Variation 3] | [Volume] | [High/Med/Low] |

### Template Design
[Section-by-section breakdown]
- Fixed content: [What stays the same]
- Variable content: [What changes per page]
- Unique content: [What's generated/written per page]

### Unique Value Strategy
[How each page adds value beyond variable data swaps]

### Data Requirements
| Data Field | Source | Update Frequency |
|-----------|--------|-----------------|
| [Field] | [Source] | [Frequency] |

### Internal Linking Plan
- Hub page: [URL/concept]
- Spoke linking: [How pages connect]
- Cross-linking: [Connections to other content]

### Launch Plan
| Phase | Pages | Timeline |
|-------|-------|----------|
| Pilot | [Count] | [Dates] |
| Batch 1 | [Count] | [Dates] |
| Full | [Count] | [Dates] |

### Quality Control Plan
[How you'll check quality at each phase]

### Maintenance Plan
[How data stays current, who checks, how often]
```

## Chaining to Other Skills

Programmatic SEO connects to broader strategy:

- **Template pages need on-page optimization** → Chain to `seo-audit`
- **Technical setup for large page sets** → Chain to `seo-technical` for sitemap, schema, architecture
- **Competitive gap revealed the opportunity** → Chain from `competitor-seo`
- **Pages should also work for AI search** → Chain to `geo-optimization` for CITE framework

When chaining, pass along: page type, template structure, data sources, volume estimate.
