---
name: seo-audit
description: On-page SEO analysis for any URL or content piece. Use for auditing search performance, diagnosing ranking issues, checking keyword targeting, or optimizing content before publishing.
---

# SEO Audit

Comprehensive on-page SEO analysis. This skill evaluates title tags, meta descriptions, header structure, keyword usage, content quality, internal linking, and search intent alignment to identify why pages underperform and what to fix first.

## When to Use This Skill

- Auditing existing pages for search performance
- Optimizing content before publishing
- Diagnosing why a page isn't ranking for target keywords
- Checking keyword targeting and intent alignment
- Reviewing content quality signals
- Comparing your page against ranking competitors

## On-Page Element Checklist

### Title Tag

| Criteria | Pass | Fail |
|----------|------|------|
| Contains target keyword | Keyword present, preferably near the front | Keyword missing or buried at the end |
| Length | 50-60 characters | Under 30 or over 60 (truncated in SERPs) |
| Unique | Different from all other page titles on site | Duplicates another page's title |
| Compelling | Gives reason to click over competitors | Generic or purely descriptive |
| Brand | Brand name included (usually at end) | Missing when brand has recognition |

### Meta Description

| Criteria | Pass | Fail |
|----------|------|------|
| Contains target keyword | Keyword present naturally | Keyword missing (won't be bolded in SERPs) |
| Length | 120-155 characters | Under 70 or over 155 (truncated) |
| Includes CTA or value prop | Gives searcher reason to click | Purely descriptive without motivation |
| Unique | Different from all other meta descriptions | Duplicates another page or is auto-generated |
| Matches intent | Aligns with what the searcher wants | Promises something the page doesn't deliver |

### Header Structure

| Element | Best Practice |
|---------|---------------|
| H1 | Exactly one per page, contains target keyword, matches page topic |
| H2s | Logical subsections, include related keywords naturally |
| H3s | Sub-subsections where needed, not used for styling |
| Hierarchy | H1 → H2 → H3 (never skip levels) |
| Keyword placement | Primary keyword in H1, secondary/related keywords in H2s |

### URL Structure

| Criteria | Good | Bad |
|----------|------|-----|
| Length | Short, descriptive | Long, parameter-heavy |
| Keywords | Contains target keyword | No keyword relevance |
| Format | Lowercase, hyphens | Underscores, mixed case, special characters |
| Hierarchy | Reflects site structure | Flat with no logical path |
| Example | `/blog/conversion-rate-optimization` | `/p?id=4827&cat=3` |

### Image Optimization

| Element | Requirement |
|---------|-------------|
| Alt text | Descriptive, includes keyword where natural, under 125 characters |
| File name | Descriptive with hyphens (`conversion-funnel-diagram.png`) |
| File size | Compressed for web (use WebP where supported) |
| Dimensions | Sized appropriately (not relying on CSS to resize large images) |
| Lazy loading | Implemented for below-fold images |

## Search Intent Analysis

Every keyword has intent. Content must match it.

### Intent Types

| Intent | What Searcher Wants | Content Format |
|--------|-------------------|----------------|
| Informational | Learn or understand something | Guides, tutorials, explanations, definitions |
| Navigational | Find a specific page or site | Brand pages, login pages, specific product pages |
| Commercial | Research before buying | Comparisons, reviews, "best of" lists, vs. pages |
| Transactional | Complete an action or purchase | Product pages, pricing pages, signup pages |

### Intent Alignment Check

1. Search your target keyword in Google
2. Look at the top 5 results
3. What content type dominates? (Guides? Lists? Product pages? Videos?)
4. What format are they? (Long-form? Short? With images? With tools?)
5. Does your content match this pattern?

If the top results are all comparison articles and you've written a single-product review, you have an intent mismatch. The content format matters as much as the content quality.

## Content Quality Signals

### E-E-A-T Assessment

| Signal | What to Check |
|--------|---------------|
| Experience | Does the content show first-hand experience with the topic? |
| Expertise | Is the author qualified? Are credentials visible? |
| Authoritativeness | Is the site recognized in this topic area? |
| Trustworthiness | Is information accurate, sourced, and current? |

**Practical E-E-A-T improvements:**
- Add author bio with relevant credentials
- Include first-person experience ("We tested this..." "In our experience...")
- Cite sources for claims and statistics
- Show date published and date last updated
- Include original images, screenshots, or data

### Content Depth Analysis

| Indicator | Sufficient | Insufficient |
|-----------|-----------|-------------|
| Word count vs. competitors | Comparable or deeper | Significantly thinner |
| Subtopics covered | All major subtopics addressed | Key subtopics missing |
| Questions answered | Covers "People Also Ask" queries | Leaves common questions unanswered |
| Original value | Adds perspective, data, or insight | Restates what's already ranking |
| Freshness | Information is current | Contains outdated information |

### Internal Linking

| Check | What to Look For |
|-------|-----------------|
| Links to this page | Other relevant pages on your site link to this one |
| Links from this page | This page links to related content on your site |
| Anchor text | Descriptive, keyword-relevant (not "click here") |
| Link depth | Page is reachable within 3 clicks from homepage |
| Broken links | No links pointing to 404s or redirects |

## Keyword Analysis

### Primary Keyword Assessment

| Factor | Evaluation |
|--------|-----------|
| Placement | Present in title, H1, first 100 words, URL, meta description |
| Density | Natural usage (typically 0.5-2%), not forced |
| Variations | Synonyms and related terms used naturally |
| LSI keywords | Related concepts and terminology included |

### Keyword Cannibalization Check

Multiple pages targeting the same keyword compete against each other.

**How to check:**
1. Search `site:yourdomain.com "target keyword"` in Google
2. If multiple pages appear, you have cannibalization
3. Solution: Consolidate content, differentiate targeting, or use canonical tags

## Red Flags

Issues that commonly hurt search performance:

- [ ] Title tag missing target keyword or over 60 characters
- [ ] Meta description missing, duplicate, or over 155 characters
- [ ] No H1 tag, or multiple H1 tags on one page
- [ ] H1 doesn't contain or relate to target keyword
- [ ] Content doesn't match search intent (format mismatch)
- [ ] Thin content compared to ranking competitors
- [ ] Keyword stuffed (unnatural, forced repetition)
- [ ] No internal links to or from the page
- [ ] Images missing alt text
- [ ] Content is outdated with no "last updated" date
- [ ] No author attribution or expertise signals
- [ ] Key subtopics covered by competitors are missing
- [ ] Page is more than 3 clicks from homepage
- [ ] URL is non-descriptive or contains parameters
- [ ] No external citations or sources for claims

## Output Format

When auditing a page:

```
## SEO Audit: [Page Title / URL]

### Page Overview
- Target keyword: [Primary keyword]
- Secondary keywords: [List]
- Search intent: [Informational / Commercial / Transactional / Navigational]
- Current ranking: [Position if known]
- Current traffic: [Monthly organic visits if known]

### On-Page Elements

| Element | Current | Status | Recommendation |
|---------|---------|--------|----------------|
| Title tag | "[Current title]" | Pass/Fail | [Fix if needed] |
| Meta description | "[Current meta]" | Pass/Fail | [Fix if needed] |
| H1 | "[Current H1]" | Pass/Fail | [Fix if needed] |
| URL | [Current URL] | Pass/Fail | [Fix if needed] |
| Images | [Alt text status] | Pass/Fail | [Fix if needed] |

### Header Structure
[H1 → H2 → H3 hierarchy assessment]

### Search Intent Alignment
- Target keyword intent: [Type]
- Top SERP format: [What's ranking]
- Content format match: [Yes/No/Partial]
- Recommendation: [If mismatch, what to change]

### Content Quality Assessment
- Word count: [Count] vs. competitor average [Count]
- E-E-A-T signals: [Present/Missing]
- Original value: [Assessment]
- Subtopics covered: [Covered/Missing]
- Freshness: [Current/Outdated]

### Keyword Analysis
- Primary keyword placement: [Where it appears]
- Density: [Percentage and assessment]
- Related keywords: [Present/Missing]
- Cannibalization risk: [Yes/No]

### Internal Linking
- Links to this page: [Count and quality]
- Links from this page: [Count and quality]
- Broken links: [Count]

### Red Flags
1. [Issue with specific evidence]
2. [Issue with specific evidence]
3. [Issue with specific evidence]

### Prioritized Recommendations

| Priority | Issue | Recommendation | Expected Impact |
|----------|-------|----------------|-----------------|
| 1 | [Issue] | [Specific fix] | [High/Med/Low] |
| 2 | [Issue] | [Specific fix] | [High/Med/Low] |
| 3 | [Issue] | [Specific fix] | [High/Med/Low] |

### Title Tag Alternatives
[If title needs rewriting, provide 2-3 options]

### Meta Description Alternatives
[If meta needs rewriting, provide 2-3 options]

### Content Recommendations
[Specific sections to add, expand, or restructure]

### Next Steps
1. [Immediate fix]
2. [Secondary fix]
3. [Longer-term improvement]
```

## Chaining to Other Skills

SEO audits often reveal issues requiring deeper analysis:

- **Technical problems (speed, schema, indexing)** → Chain to `seo-technical`
- **Competitor content outranking you** → Chain to `competitor-seo` for gap analysis
- **Content not being cited by AI models** → Chain to `geo-optimization` for CITE framework audit
- **Need to scale content for multiple keywords** → Chain to `programmatic-seo`

When chaining, pass along: target keywords, current rankings, content quality assessment, specific gaps identified.
