#!/usr/bin/env node
/**
 * run-agent.js — Shared agent runner for the MileageTrackeriOS pipeline.
 *
 * Usage: node .github/scripts/run-agent.js <scoping|developer|qa|orchestrator>
 *
 * Reads the corresponding agent prompt from .claude/agents/<name>-agent.md,
 * gathers GitHub context from the triggering event, and calls the Claude API
 * with tool definitions so the agent can act on issues, PRs, and the board.
 */

const { readFileSync } = require("fs");
const { join } = require("path");

const AGENT = process.argv[2];
if (!["scoping", "developer", "qa", "orchestrator"].includes(AGENT)) {
  console.error("Usage: run-agent.js <scoping|developer|qa|orchestrator>");
  process.exit(1);
}

const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const ISSUE_URL = process.env.ISSUE_URL || "";
const PR_URL = process.env.PR_URL || "";

// ── Load agent prompt ────────────────────────────────────────────────
const promptPath = join(__dirname, "..", "..", ".claude", "agents", `${AGENT}-agent.md`);
let SYSTEM_PROMPT;
try {
  SYSTEM_PROMPT = readFileSync(promptPath, "utf8");
} catch {
  console.error(`Missing agent prompt: ${promptPath}`);
  process.exit(1);
}

// ── Helpers ──────────────────────────────────────────────────────────
function ghApi(method, path, body) {
  const opts = {
    method,
    headers: {
      Authorization: `Bearer ${GITHUB_TOKEN}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    },
  };
  if (body) {
    opts.headers["Content-Type"] = "application/json";
    opts.body = JSON.stringify(body);
  }
  return fetch(`https://api.github.com/${path}`, opts).then((r) => {
    if (!r.ok) return r.text().then((t) => { throw new Error(`${method} ${path}: ${r.status} ${t}`); });
    return r.json().catch(() => null);
  });
}

// ── Tool definitions ─────────────────────────────────────────────────
const TOOLS = {
  // GitHub tools
  github_get_issue: {
    description: "Get details of a GitHub issue by URL or owner/repo/issue_number",
    input_schema: {
      type: "object",
      properties: {
        owner: { type: "string" },
        repo: { type: "string" },
        issue_number: { type: "integer" },
      },
      required: ["owner", "repo", "issue_number"],
    },
  },
  github_add_comment: {
    description: "Add a comment to a GitHub issue",
    input_schema: {
      type: "object",
      properties: {
        owner: { type: "string" },
        repo: { type: "string" },
        issue_number: { type: "integer" },
        body: { type: "string", description: "Markdown comment body" },
      },
      required: ["owner", "repo", "issue_number", "body"],
    },
  },
  github_get_pr: {
    description: "Get details (including diff) of a GitHub pull request",
    input_schema: {
      type: "object",
      properties: {
        owner: { type: "string" },
        repo: { type: "string" },
        pull_number: { type: "integer" },
      },
      required: ["owner", "repo", "pull_number"],
    },
  },
  github_create_pr: {
    description: "Create a GitHub pull request",
    input_schema: {
      type: "object",
      properties: {
        owner: { type: "string" },
        repo: { type: "string" },
        title: { type: "string" },
        head: { type: "string", description: "Feature branch name" },
        base: { type: "string", description: "Base branch (usually main)" },
        body: { type: "string", description: "PR description (markdown)" },
      },
      required: ["owner", "repo", "title", "head", "base", "body"],
    },
  },
  github_add_pr_review: {
    description: "Add a review to a pull request (APPROVE, REQUEST_CHANGES, or COMMENT)",
    input_schema: {
      type: "object",
      properties: {
        owner: { type: "string" },
        repo: { type: "string" },
        pull_number: { type: "integer" },
        body: { type: "string", description: "Review comment body" },
        event: { type: "string", enum: ["APPROVE", "REQUEST_CHANGES", "COMMENT"] },
      },
      required: ["owner", "repo", "pull_number", "body", "event"],
    },
  },
  github_merge_pr: {
    description: "Merge a pull request. ONLY the QA agent is authorized to use this.",
    input_schema: {
      type: "object",
      properties: {
        owner: { type: "string" },
        repo: { type: "string" },
        pull_number: { type: "integer" },
        merge_method: { type: "string", enum: ["merge", "squash", "rebase"], default: "squash" },
      },
      required: ["owner", "repo", "pull_number"],
    },
  },
  github_move_project_item: {
    description: "Move a project item to a different column. Columns: Backlog, Refined, Ready to Pick Up, In Progress, In Review, Done",
    input_schema: {
      type: "object",
      properties: {
        project_id: { type: "string" },
        item_id: { type: "string" },
        column: { type: "string", enum: ["Backlog", "Refined", "Ready to Pick Up", "In Progress", "In Review", "Done"] },
      },
      required: ["project_id", "item_id", "column"],
    },
  },
  github_list_project_items: {
    description: "List all items on the project board",
    input_schema: {
      type: "object",
      properties: {
        project_id: { type: "string" },
      },
      required: ["project_id"],
    },
  },
  github_add_issue_label: {
    description: "Add labels to an issue",
    input_schema: {
      type: "object",
      properties: {
        owner: { type: "string" },
        repo: { type: "string" },
        issue_number: { type: "integer" },
        labels: { type: "array", items: { type: "string" } },
      },
      required: ["owner", "repo", "issue_number", "labels"],
    },
  },

  // Code / shell tools (developer + qa)
  shell_run: {
    description: "Run a shell command in the repo root. Returns stdout and stderr.",
    input_schema: {
      type: "object",
      properties: {
        command: { type: "string", description: "Shell command to run" },
      },
      required: ["command"],
    },
  },
  file_read: {
    description: "Read a file from the repository",
    input_schema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Path relative to repo root" },
      },
      required: ["path"],
    },
  },
  file_write: {
    description: "Write content to a file in the repository",
    input_schema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Path relative to repo root" },
        content: { type: "string", description: "File content" },
      },
      required: ["path", "content"],
    },
  },

  // Web research (scoping agent)
  web_search: {
    description: "Search the web for information",
    input_schema: {
      type: "object",
      properties: {
        query: { type: "string" },
      },
      required: ["query"],
    },
  },
  web_fetch: {
    description: "Fetch and extract content from a URL",
    input_schema: {
      type: "object",
      properties: {
        url: { type: "string", format: "uri" },
      },
      required: ["url"],
    },
  },
};

// ── Tool execution ───────────────────────────────────────────────────
const { execSync } = require("child_process");

async function executeTool(name, input) {
  switch (name) {
    // GitHub API
    case "github_get_issue":
      return await ghApi("GET", `repos/${input.owner}/${input.repo}/issues/${input.issue_number}`);
    case "github_add_comment":
      return await ghApi("POST", `repos/${input.owner}/${input.repo}/issues/${input.issue_number}/comments`, { body: input.body });
    case "github_get_pr": {
      const [pr, diff] = await Promise.all([
        ghApi("GET", `repos/${input.owner}/${input.repo}/pulls/${input.pull_number}`),
        ghApi("GET", `repos/${input.owner}/${input.repo}/pulls/${input.pull_number}`).then(async () => {
          // Get the diff via raw media type
          const r = await fetch(
            `https://api.github.com/repos/${input.owner}/${input.repo}/pulls/${input.pull_number}.diff`,
            { headers: { Authorization: `Bearer ${GITHUB_TOKEN}`, Accept: "application/vnd.github.diff" } }
          );
          return r.text();
        }),
      ]);
      return { ...pr, diff };
    }
    case "github_create_pr":
      return await ghApi("POST", `repos/${input.owner}/${input.repo}/pulls`, {
        title: input.title,
        head: input.head,
        base: input.base,
        body: input.body,
      });
    case "github_add_pr_review":
      return await ghApi("POST", `repos/${input.owner}/${input.repo}/pulls/${input.pull_number}/reviews`, {
        body: input.body,
        event: input.event,
      });
    case "github_merge_pr":
      return await ghApi("PUT", `repos/${input.owner}/${input.repo}/pulls/${input.pull_number}/merge`, {
        merge_method: input.merge_method || "squash",
      });
    case "github_add_issue_label":
      return await ghApi("POST", `repos/${input.owner}/${input.repo}/issues/${input.issue_number}/labels`, { labels: input.labels });
    // Project board — these need project IDs, stubbed for now
    case "github_move_project_item":
      console.log(`[project] Move item ${input.item_id} → ${input.column}`);
      return { moved: true, column: input.column };
    case "github_list_project_items":
      console.log("[project] List items (requires project ID)");
      return { items: [] };

    // Shell + file ops
    case "shell_run": {
      try {
        const stdout = execSync(input.command, { cwd: process.env.GITHUB_WORKSPACE || process.cwd(), encoding: "utf8", timeout: 120000 });
        return { stdout, stderr: "" };
      } catch (e) {
        return { stdout: e.stdout || "", stderr: e.stderr || e.message, exitCode: e.status };
      }
    }
    case "file_read": {
      const p = join(process.env.GITHUB_WORKSPACE || process.cwd(), input.path);
      return { content: readFileSync(p, "utf8") };
    }
    case "file_write": {
      const p = join(process.env.GITHUB_WORKSPACE || process.cwd(), input.path);
      const { writeFileSync, mkdirSync } = require("fs");
      const { dirname } = require("path");
      mkdirSync(dirname(p), { recursive: true });
      writeFileSync(p, input.content, "utf8");
      return { written: true, path: input.path };
    }

    // Web research (stubs — real implementation would use a search API)
    case "web_search":
      console.log(`[web-search] ${input.query}`);
      return { results: ["Web search requires a search API key. Use WebSearch/WebFetch via Claude Code for manual scoping."] };
    case "web_fetch":
      console.log(`[web-fetch] ${input.url}`);
      return { content: "Web fetch requires browserless or similar. Use WebFetch via Claude Code for manual scoping." };

    default:
      return { error: `Unknown tool: ${name}` };
  }
}

// ── Claude API call ──────────────────────────────────────────────────
async function callClaude(messages, tools) {
  const body = {
    model: "claude-sonnet-4-6",
    max_tokens: 4096,
    system: SYSTEM_PROMPT,
    messages,
    tools: tools.map((t) => ({ name: t.name, description: t.description, input_schema: t.input_schema })),
  };

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Claude API error ${res.status}: ${err}`);
  }
  return res.json();
}

// ── Main agent loop ──────────────────────────────────────────────────
const REPO_OWNER = process.env.GITHUB_REPOSITORY?.split("/")[0] || "justharryjust";
const REPO_NAME = process.env.GITHUB_REPOSITORY?.split("/")[1] || "MileageTrackeriOS";

function parseIssueUrl(url) {
  if (!url) return null;
  const m = url.match(/github\.com\/([^/]+)\/([^/]+)\/issues\/(\d+)/);
  return m ? { owner: m[1], repo: m[2], issue_number: parseInt(m[3]) } : null;
}
function parsePrUrl(url) {
  if (!url) return null;
  const m = url.match(/github\.com\/([^/]+)\/([^/]+)\/pull\/(\d+)/);
  return m ? { owner: m[1], repo: m[2], pull_number: parseInt(m[3]) } : null;
}

async function main() {
  console.log(`Running ${AGENT} agent...`);

  // Build context message based on agent type
  let contextMessage;
  const issue = parseIssueUrl(ISSUE_URL || process.env.ISSUE_URL);
  const pr = parsePrUrl(PR_URL || process.env.PR_URL);

  switch (AGENT) {
    case "scoping": {
      const issueData = issue
        ? await ghApi("GET", `repos/${issue.owner}/${issue.repo}/issues/${issue.issue_number}`)
        : null;
      contextMessage = {
        role: "user",
        content: `Scoping request. Repository: ${REPO_OWNER}/${REPO_NAME}.\n\nIssue: ${issueData ? JSON.stringify(issueData, null, 2) : ISSUE_URL || "No issue URL provided. Ask for it."}\n\nResearch this ticket, write acceptance criteria in the format:\n## Acceptance Criteria\n1. Given [context], when [action], then [expected result]\n\nPost your research and ACs as a comment on the issue, then move the project item from "Backlog" to "Refined".`,
      };
      break;
    }
    case "developer": {
      const issueData = issue
        ? await ghApi("GET", `repos/${issue.owner}/${issue.repo}/issues/${issue.issue_number}`)
        : null;
      contextMessage = {
        role: "user",
        content: `Implementation request. Repository: ${REPO_OWNER}/${REPO_NAME}.\n\nTicket: ${issueData ? JSON.stringify(issueData, null, 2) : ISSUE_URL || "No issue URL. Ask for it."}\n\nRead the ticket and ACs, create a feature branch, implement the changes, write tests, build with xcodebuild, and open a PR. Move the card to "In Review" when done.`,
      };
      break;
    }
    case "qa": {
      let prData = null;
      if (pr) {
        const [details, diff] = await Promise.all([
          ghApi("GET", `repos/${pr.owner}/${pr.repo}/pulls/${pr.pull_number}`),
          fetch(`https://api.github.com/repos/${pr.owner}/${pr.repo}/pulls/${pr.pull_number}.diff`, {
            headers: { Authorization: `Bearer ${GITHUB_TOKEN}`, Accept: "application/vnd.github.diff" },
          }).then((r) => r.text()),
        ]);
        prData = { ...details, diff };
      }
      contextMessage = {
        role: "user",
        content: `QA review request. Repository: ${REPO_OWNER}/${REPO_NAME}.\n\nPR: ${prData ? JSON.stringify(prData, null, 2) : PR_URL || "No PR URL. Ask for it."}\n\nReview the PR diff, match against the linked issue's ACs, run xcodebuild and tests. If everything passes, approve and merge (squash). If issues found, leave a REQUEST_CHANGES review.`,
      };
      break;
    }
    case "orchestrator": {
      contextMessage = {
        role: "user",
        content: `Orchestration check. Repository: ${REPO_OWNER}/${REPO_NAME}.\n\nCheck the project board for items that need attention and dispatch the appropriate agent if a trigger condition is met. Refer to your instructions in the orchestrator agent prompt.`,
      };
      break;
    }
  }

  // Determine which tools are relevant for this agent
  const agentTools = {
    scoping: ["github_get_issue", "github_add_comment", "github_move_project_item", "web_search", "web_fetch"],
    developer: ["github_get_issue", "github_create_pr", "github_move_project_item", "shell_run", "file_read", "file_write"],
    qa: ["github_get_pr", "github_add_pr_review", "github_merge_pr", "github_move_project_item", "shell_run", "file_read"],
    orchestrator: ["github_list_project_items", "github_get_issue", "github_get_pr", "github_move_project_item"],
  };

  const tools = (agentTools[AGENT] || []).map((name) => ({
    name,
    ...TOOLS[name],
  }));

  // Agent loop
  const messages = [contextMessage];
  let turn = 0;
  const MAX_TURNS = 10;

  while (turn < MAX_TURNS) {
    console.log(`\n--- Turn ${turn + 1} ---`);
    const response = await callClaude(messages, tools);

    // Collect text and tool_use blocks
    const textBlocks = response.content.filter((b) => b.type === "text");
    const toolBlocks = response.content.filter((b) => b.type === "tool_use");

    for (const t of textBlocks) {
      console.log(`[${AGENT}] ${t.text}`);
    }

    if (toolBlocks.length === 0) {
      console.log("Agent finished.");
      break;
    }

    // Add assistant response to messages
    messages.push({ role: "assistant", content: response.content });

    // Execute tools and collect results
    const toolResults = [];
    for (const tool of toolBlocks) {
      console.log(`[tool] ${tool.name}(${JSON.stringify(tool.input)})`);
      try {
        const result = await executeTool(tool.name, tool.input);
        toolResults.push({
          type: "tool_result",
          tool_use_id: tool.id,
          content: typeof result === "string" ? result : JSON.stringify(result, null, 2),
        });
      } catch (e) {
        toolResults.push({
          type: "tool_result",
          tool_use_id: tool.id,
          content: `Error: ${e.message}`,
          is_error: true,
        });
      }
    }

    messages.push({ role: "user", content: toolResults });
    turn++;
  }

  if (turn >= MAX_TURNS) {
    console.log("Max turns reached — agent did not finish.");
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
