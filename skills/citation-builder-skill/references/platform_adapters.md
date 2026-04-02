# Platform Adapters — Citation Directory Field Mappings

## How to Use This File

Each adapter defines:
- Submission URL pattern
- Account registration requirements
- Form field mappings (NAP field → directory's field name/selector)
- Multi-step form structure
- Verification method
- Known quirks

The agent loads the relevant adapter in Phase 4 to guide form filling.

---

## Generic Form Adapter (fallback)

When no specific adapter exists, use this fallback mapping strategy:

**Field detection priority:**
1. `aria-label` attribute containing NAP keyword
2. `placeholder` attribute containing NAP keyword
3. `name` attribute matching common patterns
4. Label text adjacent to input
5. Surrounding context (fieldset legend, nearby heading)

**Common field name patterns:**
```python
NAME_PATTERNS = ["business_name", "company_name", "name", "biz_name", "listing_name"]
ADDRESS_PATTERNS = ["address", "address1", "street", "street_address", "addr"]
CITY_PATTERNS = ["city", "town", "locality"]
STATE_PATTERNS = ["state", "province", "region", "state_province"]
ZIP_PATTERNS = ["zip", "postal", "postal_code", "zipcode", "postcode"]
PHONE_PATTERNS = ["phone", "telephone", "tel", "contact_phone", "business_phone"]
WEBSITE_PATTERNS = ["website", "url", "web", "site", "homepage", "web_address"]
EMAIL_PATTERNS = ["email", "contact_email", "business_email", "e-mail"]
DESC_PATTERNS = ["description", "about", "bio", "overview", "business_description", "details"]
```

---

## Yelp for Business

**Submission URL:** `https://biz.yelp.com/claim`  
**Account:** Email registration required  
**Verification:** Phone or postcard  
**Auto-publish:** No — review period 1-3 days  
**Difficulty:** Hard  

**Field mappings:**
```
business_name → "Business Name" (input#business-name)
address1 → "Street Address" (input[name="address1"])
city → "City" (input[name="city"])
state → State dropdown (select[name="state"])
zip → "Zip Code" (input[name="zip"])
phone_display → "Business Phone" (input[name="phone"])
website → "Business Website" (input[name="website"])
categories_primary → category typeahead (input#category-search)
description_long → "Business Description" (textarea#description)
```

**Known quirks:**
- Category must be selected from typeahead — type slowly, wait for dropdown
- Phone verification flow: agent receives SMS, must enter code (flag as manual if no SMS access)
- Yelp has aggressive bot detection — use longer delays (10-15s between fields)
- If "This business has already been claimed" → flag as needs_claim

---

## Yellow Pages (YP.com)

**Submission URL:** `https://www.yellowpages.com/free-listing`  
**Account:** Created during submission flow  
**Verification:** Email  
**Auto-publish:** Yes after email verification  
**Difficulty:** Easy  

**Field mappings:**
```
business_name → "Business Name" (input#business-name)
categories_primary → "Business Type" (input#category)
address1 → "Address" (input#address)
city → "City" (input#city)
state_abbr → State dropdown (select#state)
zip → "Zip" (input#zip)
phone_display → "Phone Number" (input#phone)
website → "Website" (input#website)
```

**Known quirks:**
- Simple 2-step form — easy adapter
- Email verification arrives within 5 minutes typically
- After email verify, listing usually live within 1 hour

---

## Better Business Bureau (BBB)

**Submission URL:** `https://www.bbb.org/request/business`  
**Account:** Email registration  
**Verification:** Phone + manual review  
**Auto-publish:** No — manual review by BBB team (1-5 business days)  
**Difficulty:** Medium  

**Notes:**
- Free basic listing available (do not pursue accreditation as part of this automation)
- Review period is long — set next_check_due to +7 days after submission
- BBB may call the listed phone to verify — inform client

---

## Bing Places for Business

**Submission URL:** `https://www.bingplaces.com/`  
**Account:** Microsoft account required  
**Verification:** Postcard or phone  
**Auto-publish:** After verification  
**Difficulty:** Medium  

**Best practice:** If client has Google Business Profile live and verified, use Bing's "Import from Google" feature — much faster than manual form. Check for this option first.

**Import path:** `https://www.bingplaces.com/Dashboard/Import`

---

## Foursquare

**Submission URL:** `https://foursquare.com/add-place`  
**Account:** Foursquare account  
**Verification:** None usually  
**Auto-publish:** Yes  
**Difficulty:** Easy  

**Field mappings:**
```
business_name → "Place Name" (input[placeholder="Place Name"])
categories_primary → "Category" (category picker)
address1 → "Address" (address autocomplete)
city → auto-filled from address
phone_display → "Phone" (input[placeholder="Phone"])
website → "Website" (input[placeholder="Website"])
```

---

## Manta

**Submission URL:** `https://www.manta.com/claim`  
**Account:** Email registration  
**Verification:** Email  
**Auto-publish:** After email verification  
**Difficulty:** Easy  

---

## Hotfrog

**Submission URL:** `https://www.hotfrog.com/AddBusiness.aspx`  
**Account:** Created during flow  
**Verification:** Email  
**Auto-publish:** Yes after email verify  
**Difficulty:** Easy  

**Use for:** Quick wins, low-DA but builds breadth

---

## Apple Maps Connect

**Submission URL:** `https://mapsconnect.apple.com/`  
**Account:** Apple ID required  
**Verification:** Phone  
**Auto-publish:** After review  
**Difficulty:** Medium  
**Special:** Requires Apple ID — check if client has one or needs one created  

**Important:** Apple Maps ToS restricts bulk automated submissions. Flag for manual completion if ToS compliance is a concern.

---

## Yext-Powered Directories (Network Detection)

Many directories run on the Yext publisher network. They share similar form structure.

**How to detect:** Look for Yext branding, `yext.com` in network requests, or `/search` powered by Yext.

**Common Yext-powered directories:**
- ChamberofCommerce.com
- n49.com
- eLocal.com
- ShowMeLocal.com

**Yext adapter field patterns:**
```
name → input[data-field="name"] or input[aria-label*="name" i]
address → input[data-field="address"] or input[aria-label*="address" i]
city → input[data-field="city"]
state → select[data-field="state"] or input[data-field="state"]
zip → input[data-field="zip"]
phone → input[data-field="phone"] or input[type="tel"]
website → input[data-field="url"] or input[type="url"]
```

---

## Do NOT Automate — Manual Only

**Google Business Profile**
- ToS explicitly prohibits automation
- Use official GMB API or manual dashboard
- Agent should skip and add to manual queue with note "GBP: use official API"

**Facebook Business**
- Complex auth flow, 2FA common, ToS concerns
- Flag as manual

**LinkedIn Company Page**
- Professional network, manual process
- Flag as manual

---

## Detecting New/Unknown Platforms

When encountering a new directory with no adapter:

1. Use generic adapter
2. Increase screenshot frequency (capture after each field group)
3. Slow delays (10s between fields)
4. If form structure is ambiguous → flag as `manual_needed` with screenshot
5. After manual completion, add notes to this file for future runs

---

## Platform Detection Heuristics

```python
# Check for Yext
is_yext = "yext.com" in page_source or "yext" in network_requests

# Check for BrightLocal network
is_brightlocal = "brightlocal.com" in network_requests

# Check for Localeze/Neustar
is_localeze = "localeze.com" in page_source

# Check for simple form
is_simple = form_field_count < 10 and no_multi_step

# Check for paid gate
has_paid_gate = any(["upgrade", "premium", "paid", "subscribe", "pricing"] in page_text)
```
