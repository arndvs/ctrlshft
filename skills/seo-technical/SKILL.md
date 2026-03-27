---
name: seo-technical
description: Technical SEO analysis including schema markup, site speed, crawlability, indexation, and structured data. Use for diagnosing infrastructure issues that prevent content from ranking.
---

# SEO Technical

Technical SEO analysis covering the infrastructure layer that determines whether good content gets found. This skill evaluates crawlability, indexation, site speed, schema markup, structured data, and site architecture.

## When to Use This Skill

- Checking site technical health
- Implementing or fixing schema markup
- Diagnosing indexation or crawl issues
- Evaluating Core Web Vitals performance
- Auditing site architecture and URL hierarchy
- Troubleshooting ranking drops that aren't content-related
- Setting up a new site for search

## Technical Health Checklist

### Crawlability

| Element | What to Check | How to Check |
|---------|--------------|--------------|
| robots.txt | Not blocking important pages | Visit yourdomain.com/robots.txt |
| XML sitemap | Exists, current, submitted to Search Console | Visit yourdomain.com/sitemap.xml |
| Crawl errors | No critical pages returning errors | Google Search Console > Pages |
| Internal links | All pages reachable within 3 clicks | Manual spot-check or crawl tool |
| Redirect chains | No chains of 3+ redirects | Check key URLs for redirect hops |

**robots.txt audit:**
- Verify it's not blocking CSS/JS files (prevents rendering)
- Verify it's not blocking key directories unintentionally
- Verify sitemap location is declared
- Check for conflicting rules

**XML sitemap audit:**
- All important pages included
- No 404, redirect, or noindex pages in sitemap
- Last modified dates are accurate
- Sitemap submitted in Google Search Console
- Sitemap size under 50MB / 50,000 URLs (split if needed)

### Indexation

| Check | What to Look For |
|-------|-----------------|
| Index coverage | All important pages indexed (Search Console > Pages) |
| Noindex tags | Only present on pages you intentionally exclude |
| Canonical tags | Every page has a self-referencing canonical (or points to correct canonical) |
| Duplicate content | No two pages with substantially identical content without canonicalization |
| Thin pages | No indexed pages with little or no content |

**Canonical tag rules:**
- Every page should have a canonical tag
- Self-referencing canonical on unique pages (`<link rel="canonical" href="[this page's URL]">`)
- Canonical pointing to preferred version on duplicate/similar pages
- HTTPS version canonical, not HTTP
- Consistent trailing slash usage

### Site Speed and Core Web Vitals

| Metric | Good | Needs Work | Poor |
|--------|------|------------|------|
| LCP (Largest Contentful Paint) | ≤2.5s | 2.5-4.0s | >4.0s |
| INP (Interaction to Next Paint) | ≤200ms | 200-500ms | >500ms |
| CLS (Cumulative Layout Shift) | ≤0.1 | 0.1-0.25 | >0.25 |

**Common speed issues and fixes:**

| Issue | Impact | Fix |
|-------|--------|-----|
| Uncompressed images | Slow LCP | Convert to WebP, compress, lazy load below-fold |
| Render-blocking JS/CSS | Slow LCP | Defer non-critical scripts, inline critical CSS |
| No browser caching | Slow repeat loads | Set cache headers for static assets |
| Large DOM size | Slow INP | Simplify page structure, reduce elements |
| Unoptimized fonts | Layout shifts | Preload fonts, use font-display: swap |
| No image dimensions | CLS | Set explicit width/height on all images |
| Dynamic ad/embed injection | CLS | Reserve space for dynamic elements |

**How to test:**
- Google PageSpeed Insights (pagespeed.web.dev)
- Core Web Vitals report in Search Console
- Chrome DevTools > Lighthouse

### Mobile-First Indexing

Google indexes the mobile version of your site. If mobile is broken, rankings suffer everywhere.

| Check | Requirement |
|-------|-------------|
| Viewport meta tag | `<meta name="viewport" content="width=device-width, initial-scale=1">` present |
| Content parity | Same content on mobile and desktop (not hidden or reduced) |
| Tap targets | Buttons/links at least 48x48px with adequate spacing |
| Font size | Minimum 16px base font |
| No horizontal scroll | Content fits viewport width |
| Mobile page speed | Passes Core Web Vitals on mobile connection |

### HTTPS

| Check | Requirement |
|-------|-------------|
| SSL certificate | Valid, not expired |
| All pages HTTPS | No mixed content (HTTP resources on HTTPS page) |
| HTTP redirects | All HTTP URLs redirect to HTTPS |
| Canonical tags | Point to HTTPS versions |
| Internal links | Use HTTPS URLs |

### Site Architecture

| Principle | Implementation |
|-----------|---------------|
| Flat hierarchy | Most pages within 3 clicks of homepage |
| Logical grouping | Related content in same directory/section |
| Clear URL structure | URLs reflect hierarchy (`/blog/category/post-title`) |
| Breadcrumbs | Present for navigation and search (with schema) |
| Pagination | Proper rel="next"/rel="prev" or load-more patterns |

## Schema Markup

### Why Schema Matters

Schema markup tells search engines exactly what your content represents. It enables rich snippets (star ratings, FAQs, how-to steps, pricing) in search results, which increase click-through rates. It also reinforces entity relationships for AI model comprehension.

### Schema Type Selection

| Page Type | Recommended Schema | Rich Snippet Potential |
|-----------|-------------------|----------------------|
| Blog post / Article | Article, Author, BreadcrumbList | Date, author, breadcrumbs |
| Product page | Product, Offer, AggregateRating | Price, availability, stars |
| FAQ page | FAQPage, Question, Answer | Expandable FAQ in SERPs |
| How-to guide | HowTo, Step | Step-by-step in SERPs |
| Local business | LocalBusiness, PostalAddress | Map pack, hours, reviews |
| Organization/About | Organization, ContactPoint | Knowledge panel |
| Event | Event, Place | Event listing in SERPs |
| Recipe | Recipe, NutritionInformation | Recipe card in SERPs |
| Review | Review, Rating | Star ratings |
| Video | VideoObject | Video thumbnail in SERPs |
| Course | Course, CourseInstance | Course listing |
| Software/SaaS | SoftwareApplication | App details |

### JSON-LD Implementation

Always use JSON-LD format (Google's preferred method). Place in `<head>` or at end of `<body>`.

**Article example:**
```json
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "Your Article Title",
  "author": {
    "@type": "Person",
    "name": "Author Name",
    "url": "https://yoursite.com/about"
  },
  "publisher": {
    "@type": "Organization",
    "name": "Your Site Name",
    "logo": {
      "@type": "ImageObject",
      "url": "https://yoursite.com/logo.png"
    }
  },
  "datePublished": "2025-01-15",
  "dateModified": "2025-03-20",
  "description": "Brief description of the article",
  "mainEntityOfPage": "https://yoursite.com/article-url"
}
```

**FAQ example:**
```json
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Your question here?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Your answer here."
      }
    }
  ]
}
```

**Product example:**
```json
{
  "@context": "https://schema.org",
  "@type": "Product",
  "name": "Product Name",
  "description": "Product description",
  "offers": {
    "@type": "Offer",
    "price": "49.00",
    "priceCurrency": "USD",
    "availability": "https://schema.org/InStock"
  }
}
```

**HowTo example:**
```json
{
  "@context": "https://schema.org",
  "@type": "HowTo",
  "name": "How to Do the Thing",
  "step": [
    {
      "@type": "HowToStep",
      "name": "Step 1 name",
      "text": "Step 1 instructions"
    },
    {
      "@type": "HowToStep",
      "name": "Step 2 name",
      "text": "Step 2 instructions"
    }
  ]
}
```

### Schema Validation

**Always test before deploying:**
1. Google Rich Results Test (search.google.com/test/rich-results)
2. Schema Markup Validator (validator.schema.org)
3. Check Search Console for structured data errors after deployment

**Common schema mistakes:**
- Missing required fields for the schema type
- Using schema for content not visible on the page (cloaking)
- Incorrect nesting of schema objects
- Wrong schema type for the page content
- Duplicate schema blocks on the same page
- Markup that contradicts visible page content

## Red Flags

Technical issues that commonly hurt search performance:

- [ ] No XML sitemap or sitemap not submitted to Search Console
- [ ] Important pages blocked by robots.txt
- [ ] Missing or incorrect canonical tags
- [ ] No schema markup on key page types
- [ ] Core Web Vitals failing (LCP >2.5s, CLS >0.1)
- [ ] No HTTPS or mixed content warnings
- [ ] Broken internal links or redirect chains (3+ hops)
- [ ] Duplicate content without canonicalization
- [ ] Mobile rendering issues or missing viewport tag
- [ ] Pages more than 3 clicks from homepage
- [ ] No breadcrumb navigation
- [ ] Images not compressed or lacking dimensions
- [ ] Render-blocking resources slowing page load
- [ ] 404 pages in XML sitemap
- [ ] HTTP versions not redirecting to HTTPS

## Output Format

When performing a technical SEO audit:

```
## Technical SEO Audit: [Domain]

### Site Overview
- Platform: [WordPress/Shopify/Custom/etc.]
- Pages indexed: [Count if known]
- Domain age: [If known]

### Crawlability Assessment

| Element | Status | Issue | Fix |
|---------|--------|-------|-----|
| robots.txt | OK/Issue | [Detail] | [Action] |
| XML sitemap | OK/Issue | [Detail] | [Action] |
| Internal links | OK/Issue | [Detail] | [Action] |
| Redirect chains | OK/Issue | [Detail] | [Action] |

### Indexation Assessment

| Element | Status | Issue | Fix |
|---------|--------|-------|-----|
| Index coverage | OK/Issue | [Detail] | [Action] |
| Canonical tags | OK/Issue | [Detail] | [Action] |
| Duplicate content | OK/Issue | [Detail] | [Action] |
| Noindex tags | OK/Issue | [Detail] | [Action] |

### Core Web Vitals

| Metric | Score | Status | Fix |
|--------|-------|--------|-----|
| LCP | [Value] | Good/Needs Work/Poor | [Action] |
| INP | [Value] | Good/Needs Work/Poor | [Action] |
| CLS | [Value] | Good/Needs Work/Poor | [Action] |

### Mobile Assessment
- Viewport tag: [Present/Missing]
- Content parity: [Yes/No]
- Tap targets: [Adequate/Too small]
- Font size: [Adequate/Too small]

### HTTPS Assessment
- SSL valid: [Yes/No]
- Mixed content: [Yes/No]
- HTTP redirects: [Working/Broken]

### Schema Markup Assessment

| Page Type | Schema Present | Schema Type | Valid | Recommendation |
|-----------|---------------|-------------|-------|----------------|
| [Page type] | Yes/No | [Type] | Yes/No | [Action] |

### Schema Implementation Recommendations
[Specific JSON-LD templates for pages that need schema]

### Site Architecture Assessment
- Max click depth: [Number]
- Orphan pages: [Count]
- Breadcrumbs: [Present/Missing]

### Prioritized Recommendations

| Priority | Issue | Category | Fix | Expected Impact |
|----------|-------|----------|-----|-----------------|
| 1 | [Issue] | [Crawl/Index/Speed/Schema/Mobile] | [Fix] | [High/Med/Low] |
| 2 | [Issue] | [Category] | [Fix] | [High/Med/Low] |
| 3 | [Issue] | [Category] | [Fix] | [High/Med/Low] |

### Quick Wins
[Technical fixes that take <30 minutes]

### Requires Development
[Fixes that need developer involvement]
```

## Chaining to Other Skills

Technical issues often connect to broader search strategy:

- **On-page content needs optimization** → Chain to `seo-audit`
- **Content not being cited by AI models** → Chain to `geo-optimization`
- **Building pages at scale** → Chain to `programmatic-seo` for template architecture
- **Competitors outranking despite weaker content** → Chain to `competitor-seo` (may be technical advantage)

When chaining, pass along: technical issues found, schema status, speed metrics, indexation data.
