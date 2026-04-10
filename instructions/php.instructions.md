Output "Read PHP instructions." to chat to acknowledge you read this file.

<php>
- Support modern PHP 8.4+ syntax
- Follow OOP, strongly typed
- Every file starts with `declare(strict_types=1);`
- Use `#[Override]` on all overridden methods (import with `use Override;`)
- Declare fields explicitly at class top
- Use typed class constants
- Enum cases must be UPPER_CASE with underscores: `case HOMEWORK_SUBMITTED = 'homework_submitted';`
- Use `json_validate` instead of `json_last_error`
- Mark methods as `final` unless they are meant to be overridden
- Type `new ClassName()->method()` without parentheses (PHP 8.4)
- Never prefix global PHP classes with `\`. Use bare names (e.g., `RuntimeException` not `\RuntimeException`). Import with `use` if in a namespace
- Do not inline styles in DOM elements
- Never hardcode SVG strings in JavaScript. Render icons server-side. JS should only toggle classes, never swap innerHTML with SVG markup
</php>
