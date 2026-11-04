import Foundation

public enum Prompts {
    public static func live(project: String) -> String {
        "Project folder: " + project + "\n" + boundary + "\n\n" + rules
    }

    public static let noteTemplate = """
    Return only the markdown.
    Write the note in English.

    ## Summary
    none heard

    ## Decisions
    none heard

    ## Rules and figures learned
    none heard

    ## Action items
    none heard

    ## Waiting on others
    none heard

    ## Open questions
    none heard

    ## Corrections vs. what was said
    none heard

    ## Proposed follow-ups
    none heard

    Empty sections say "none heard".
    Tag claims with [doc: confirmed path:line], [doc: contradicts path:line], or [meeting only].
    Mark a single heard figure (?).
    Where the two transcripts disagree on a number, name, date, id, or issue number, the figure is (?) and both wordings are quoted.
    Leave quotes as spoken.
    Limit gh to `gh pr view`, `gh issue view`, and `gh issue list`. It must not comment, push, or post.
    """

    private static let boundary = "Read files inside the project folder only. No shell, no network, no edits."

    private static let rules = """
    Reply rules, first match, combined when a batch holds several.

    | Heard | Reply |
    |---|---|
    | A question the project can answer, even if nobody asked the assistant | `❓ <question> → <answer>` plus `path:line` |
    | A status, figure, date, or decision that contradicts a known source | `⚠️ heard "<quote>" — <source> says <X>` plus `path:line`. Say when it may be a mishearing |
    | A status, figure, or rule a source confirms | `✅ <claim> — <path:line>` |
    | A new decision, action item, owner, or deadline | `📌 <who> → <what> (<when>)` |
    | A document, PR, issue, or runbook the repo has | `📎 <what> — <path or repo#N and title>` |
    | Nothing actionable | `· HH:MM <gist in 12 words or fewer>` |
    | A check that needs more than about 30 seconds | `🔎 queued: <claim>` |

    Ground truth, in this order: code on the default branch and release tags, deploy and release records, reference docs and ADRs, plans and handoffs, then an earlier meeting note. Counts and amounts that live only in a database are always `🔎 queued` during the meeting and `[meeting only]` in the note. A flag that rests on one heard number or name says it may be ASR. Names in the vocab files are the known people.

    Live tool boundary for Claude, Codex, and Antigravity: read files inside the project folder only. No shell, no network, no edits. The live prompt repeats that. `🔎 queued` is how a slow check survives until the note.

    If a turn has produced no reply for 30 seconds, those lines stay marked queued, the transcript keeps moving, and a second turn does not start. See Failures for a dead backend.

    Ollama uses the context pack and nothing else. If the pack does not contain the answer, the reply is `🔎 queued`.
    """
}
