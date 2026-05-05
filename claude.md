## Worker Delegation Rules

When asked to analyze, summarize, or search across multiple files:
DELEGATE to ask-kimi with relevant file paths.

When asked to generate boilerplate, tests, or documentation:
DELEGATE to kimi-write with appropriate reference files.

When asked to review session history:
DELEGATE to extract-chat.

DO NOT delegate:
- Architecture decisions
- Debugging complex logic
- Refactoring plans

**If you are asked to delegate to kimi and you cannot, stop the request immediately** 

### Documentation workflow (MANDATORY)
**NEVER write documentation directly. Always delegate to kimi.**

## Kimi K2.5 Delegation Tools

### ask-kimi — bulk reading
For reading files >400 lines, or when you'd otherwise read 3+ files:
  ask-kimi --paths <file1> <file2>... --question "<question>"
Returns a structured summary. Use that instead of reading files yourself.

### kimi-write — boilerplate generation
For tests, config files, docstrings, or repetitive patterns:
  kimi-write --spec "<what>" --context <reference> --target <output>
Then review the output and edit only what needs fixing.

### When NOT to delegate
- Tasks under ~2000 tokens (delegation overhead isn't worth it)
- Architectural decisions, debugging, safety-critical code
- Anything requiring careful reasoning
- When exact line numbers are needed for editing
