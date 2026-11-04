# Meeting window

Date: 2026-11-03
Status: approved

Published as Ada Note, `opendream/ada-note`.

A small always-on-top Mac window that does the job of the noomz `meeting-secretary` skill. The user picks one backend for the meeting: Claude Code, Codex, Antigravity (`agy`), or Ollama. The window records, shows the live transcript and the secretary lines, and on Stop writes a fact-checked `summary.md`.

The skill this borrows from is `noomz-claude-skills/skills/meeting-secretary`. v1 does not modify that skill. It runs the skill's `scripts/meeting.py` as-is.

## Decisions

- The window drives one backend per meeting. The user picks it at the start. The last choice is remembered.
- v1 does both jobs: live secretary lines, and a fact-checked note when the meeting stops.
- Audio is the system mic, plus the other side of a call when the user names a call app. One mic device only. `meeting.py` refuses two live mics.
- The recorder stays `meeting.py` and `meeting-capture.swift`. The window does not capture audio itself.
- One warm secretary conversation lasts the meeting. Claude and Antigravity stay open on a stream. Codex resumes the same thread. Ollama keeps one local chat.
- Claude, Codex, and Antigravity may read the chosen project. Ollama cannot, so it gets a context pack loaded at the start.
- The model returns text. The window writes `live-notes.md` and `summary.md`.
- Silence is shown and does not call the model. Speech is one turn at a time. A question typed in the window goes first.
- Language sent to the recognizer defaults to `th` (Thai with English terms). The note is English. Quotes stay as spoken.
- Recording starts only after the user confirms that everyone in the meeting knows it is being recorded.
- Audio stays on the Mac, under `<project>/.meetings/`. Transcript text goes to the backend that was picked. Claude, Codex, and Antigravity send it off the machine. Ollama talks only to `127.0.0.1:11434`.

## Out of v1

- Screen recording, `screen.mp4`, and frames.
- Posting the note to Slack, email, or an issue tracker.
- Editing the project, memory, or plans. Proposed follow-ups stay in the note.
- Generating `<project>/.claude/meeting-vocab.txt`. The window reads that file when it exists and can write this meeting's `vocab-extra.txt`.
- A second recorder, a second meeting, or a second model turn at the same time.
- Any change to `noomz-claude-skills`.

## Pieces

1. **Window.** The Ada Note SwiftUI app. Always on top. It picks the project, the meeting name, the backend, the language, and the audio, then shows the transcript and the secretary lines.
2. **Recorder.** `python3 <skill>/scripts/meeting.py`, with its working directory set to the project folder the user picked. `meeting.py` resolves that directory to the git top level when there is one, and writes `<project>/.meetings/`. The capture helper is the one `meeting.py` already builds at `~/.local/share/meeting-secretary/bin/meeting-capture`.
3. **Secretary.** One conversation per meeting, owned by the window. See Sessions.
4. **Note pass.** On Stop, the same backend returns the note. The window saves the file. See Stop.

The skill directory used at runtime comes from `ADA_NOTE_RECORDER`, a Claude marketplace install of meeting-secretary, or a `noomz-claude-skills` checkout next to this repository. The app does not ship `meeting.py`.

Prompt text lives in the app, copied from that skill's `reference/live.md`, `reference/wrap-up.md`, and `assets/note-template.md`. The app does not read those markdown files at runtime.

## Start gate

The Start button stays off until all of these are true:

- A project folder is chosen.
- The meeting name matches `meeting.py`: letters, digits, `-`, `_`, `.`. Default `YYYY-MM-DD-` plus an editable slug. Today's date is the date on the Mac.
- A backend is chosen and its preflight passed (see Failures).
- The recognizer preflight passed. `transcribe-cli`, `Qwen3-ASR-1.7B-Q8_0.gguf`, and `silero-vad-v6.2-F32.gguf` exist under `TCPP_HOME` or `~/.local/share/transcribe.cpp`. `ffmpeg` and `swiftc` are on `PATH`.
- The consent box is checked. Everyone in the meeting knows it is being recorded.

Fields:

- **Project folder.** Required. This is the working directory for every `meeting.py` command and the only tree the cloud backends may read.
- **Backend.** Claude Code, Codex, Antigravity, or Ollama.
- **Language.** Default `th`. Any other code the user types (`en`, `ja`, and so on) is passed as `--lang`.
- **Audio.** Mic, or mic plus a call app. The mic is `default`, or `$MEETING_DEVICE` when that is set. The call app is a text field. Placeholder examples are `zoom.us` and `Microsoft Teams`. `--tap-app` receives that string. Google Meet running inside Chrome is the Chrome process, so the tap is Chrome's audio, not one tab. The window says that next to the field.
- **Topic terms.** Optional. One term per line. Written to `<meeting>/vocab-extra.txt` before `start`, so the recognizer sees them. Blank lines and `#` comments are skipped, same as the skill.

On Start the window:

1. Refuses when `meeting.py status` reports a meeting already recording. It offers Attach or Stop for that meeting.
2. Refuses when `<meeting>/transcript-live.md` already exists, and asks for a new name.
3. Writes `vocab-extra.txt` when the user entered topic terms.
4. For Ollama, builds the context pack.
5. Opens the secretary conversation with the live rules.
6. Runs `meeting.py start <name> --device <mic> --lang <lang> [--tap-app <app>]`. No `--screen`, no `--app`, no second `--device`.
7. Tails `<meeting>/transcript-live.md` and `<meeting>/recorder.log`.

`start` prints JSON with `transcript` and `log` and returns while the recorder keeps running (`start_new_session`). The first transcript line can take about 40 seconds. Until then the status is "recording, waiting for the first line."

A one-line privacy notice is shown once per meeting, before the first model call. For a cloud backend it says transcript text leaves the Mac. For Ollama it says transcript text stays on this Mac.

## Live meeting

Transcript lines look like `[HH:MM:SS] text`. A silent chunk is `[HH:MM:SS] (silence)`. A vocab-prompt echo is `(silence — prompt echo)`. The recorder writes `[END]` when it stops cleanly.

- Speech lines appear in the window as soon as they are on disk.
- Silence and prompt-echo lines show as a quiet mark. They do not start a model turn.
- `[END]` ends the live loop. The status tells the user to press Stop.

One model turn at a time. Speech that arrives during a turn is sent together when that turn returns. A question typed in the window is the next prompt, ahead of queued transcript lines. The transcript keeps growing while a question is in flight.

The model returns only secretary lines. The window appends every line that starts with ❓ ⚠️ ✅ 📌 📎 or 🔎 to `<meeting>/live-notes.md` as `- [HH:MM:SS] <emoji> <text>`. A gist line that starts with `·` stays on screen and is not logged.

Reply rules, first match, combined when a batch holds several:

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

### Context pack

Built once at start. Missing files are skipped. The pack is cut at 3000 characters, and the system message says so when it was cut.

- `CLAUDE.md` and `AGENTS.md` at the project root, whichever exist.
- The start of `README` or `README.md`, inside the same cap.
- Plan and handoff files under `.planning/`, `plans/`, and `docs/` whose names contain a topic term the user typed. When there are no topic terms, those trees are not scanned.
- The recognizer term list from the skill's `assets/vocab.txt`, `<project>/.claude/meeting-vocab.txt`, and this meeting's `vocab-extra.txt`. Terms only, not the whole files.

### Sessions

**Claude Code.** One process for the live meeting:

`claude -p --input-format stream-json --output-format stream-json --permission-mode dontAsk --restricted --allowedTools "Read,Grep,Glob" --disallowedTools "Bash,Edit,Write"`

`--restricted` drops command and web tools. The live system prompt is the reply rules, the project path, and the tool boundary. Each speech batch or typed question is one user message on that stream. The process stays up until Stop.

**Antigravity.** One process, same shape:

`agy --print --input-format stream-json --output-format stream-json --mode plan`

`--mode plan` so it does not edit. The working directory is the project folder. Each line of stream input is one turn.

**Codex.** A thread, resumed each turn. The first turn is `codex exec -C <project> --sandbox read-only` with the brief on stdin. Later turns are `codex exec resume <id> -C <project> --sandbox read-only` with the new text on stdin. `read-only` is the sandbox mode. If this Codex build uses a different spelling, implementation takes the read-only value from `codex exec --help` and does not use `--dangerously-bypass-approvals-and-sandbox`. `--skip-git-repo-check` is passed only when the folder is not a git repo.

**Ollama.** `POST http://127.0.0.1:11434/api/chat` with model `qwen3.8` and `num_ctx` 8192. The window keeps the message list. No tools. The system message stays. Older turns are dropped so the system message plus the kept turns stay within 7000 characters.

## Stop

1. Live turns end. Speech still queued goes into the note, not a last live reply. The live process is closed.
2. The window runs `meeting.py stop` in the project folder. If the JSON says `"stopped": false`, it runs `stop` once more. If that still fails, it shows the pid and waits for the user to confirm a kill. `meeting.py final` runs only after stop reports the recorder has exited.
3. The window runs `meeting.py final <name>`. That joins the chunks into `full.wav` and re-transcribes speech, with silence removed. The window shows that this is running. On this Mac it is about four seconds per minute of audio. While it runs, a cloud note session may work through `🔎` items by reading the project. Ollama waits for the file.
4. One note turn. The model returns only the markdown note.
5. The window writes `<meeting>/summary.md`. If that file exists, it writes `summary-v2.md`, then `summary-v3.md`, and so on. It shows the path, the meeting length, the counts of decisions, action items, and open questions, every contradicts line, the proposed follow-ups, and the audio path and size. Follow-ups are not applied. The session closes.

The note session resumes the live conversation. The window stores the session id the live CLI prints. Claude uses `--resume` with that id. Antigravity uses `--conversation` with that id. Codex uses `codex exec resume <id>`. The note process is separate from the live process so its tool list can add read-only `gh`. It may run `gh pr view`, `gh issue view`, and `gh issue list` when the user is already logged in. It may not edit, comment, push, or post. If resume is rejected, the note turn is a new conversation and the prompt includes the path to `live-notes.md` plus the transcript paths.

Claude's note command adds `Bash(gh *)` to the live allowlist and still denies Edit and Write. Antigravity's note command stays in `--mode plan`. Codex stays on `--sandbox read-only`. If that mode cannot run `gh`, those claims are tagged `[meeting only]` and the readout says GitHub was not checked. Ollama receives the file contents in the prompt. No backend is given a bypass-permissions flag.

Note inputs:

- `transcript-final.md`, `transcript-live.md`, and `live-notes.md` in the meeting folder. Cloud backends are told to read them by path. Ollama is given their contents.
- The note template from the skill. Sections are summary, decisions, rules and figures, action items, waiting on others, open questions, corrections, and proposed follow-ups. Empty sections say "none heard".
- Where the two transcripts disagree on a number, name, date, id, or issue number, the figure is `(?)` and both wordings are quoted. ASR does not identify speakers. A statement is attributed only when the speaker is named or obvious. Otherwise the note says "someone asked".
- A Thai spelling of an English word is normalized in the note and left as heard inside a quote.
- Each status, money, or data claim is tagged `[doc: confirmed path:line]`, `[doc: contradicts path:line]`, or `[meeting only]`. A database-only figure is `[meeting only]`.
- v1 records no screen, so the note has no frames and does not mention `screen.mp4`.

For Ollama, silence lines are dropped. The pack, the template, and the speech lines together stop at 7000 characters. When the transcript was cut, the note says it was shortened. The first line lists the pack files that were included.

If `meeting.py final` fails, the window writes the note from `transcript-live.md` and the first line says the note is live-only. If the note turn fails, the transcripts stay and the window offers Retry. Closing the window while the note runs asks first. If nothing is recording, the window can write a note for the newest meeting in that project's `.meetings` that has `meta.json` and no `summary*.md`.

A normal quit during recording asks first. On confirm the window runs `meeting.py stop`. A crash or force-quit cannot do that. The next launch recovers it, as Failures describes.

## Failures

The recorder is detached. A crash or force-quit leaves it running. On launch the window runs `meeting.py status` for the last project folder. When a meeting is active it offers Attach or Stop. Attach tails the existing transcript, opens a new secretary conversation, and feeds it `live-notes.md` plus the last 20 transcript lines. Attach does not start a second recorder.

The window maps recorder log lines to one status each:

| Log line | What the window says |
|---|---|
| `ERROR recorder exited by itself` | Microphone permission. Recording has stopped, and audio from here on is not kept. Offer System Settings. |
| `ERROR no audio for N s — capture stalled` | Capture stalled, shown once. Clear it when `audio resumed` arrives. |
| `process tap failed` or `System Audio Recording` | System Audio Recording permission for the app or the capture helper, whichever the system prompt names. |
| `WARNING: no running app named` for `--tap-app` | That app is not running. Mic only, and the helper keeps rescanning. Shown once. |
| `ERROR vad`, `ERROR window`, `ERROR chunk` | That slice was not transcribed. Recording continues. |

`meeting.py start` exits with `missing:` when the recognizer files are absent. The window shows that text and a Setup action. Setup runs the install steps the script already prints. It clones and builds transcribe.cpp into `~/.local/share/transcribe.cpp` when the checkout is missing, curls the two models (the ASR model is about 2.2 GB), and lets `meeting.py` build `meeting-capture` with `swiftc`. Setup does not start a meeting. A missing `ffmpeg` is reported with `brew install ffmpeg`. A missing `swiftc` is reported with `xcode-select --install`.

Backend preflight, before Start:

- The CLI is on `PATH`: `claude`, `codex`, `agy`, or `ollama`.
- Ollama answers on `127.0.0.1:11434` and `ollama list` contains `qwen3.8`. Otherwise the window says to start Ollama or pull that model, and Start stays off.
- A cloud CLI that fails a one-line read-only ping ("reply ok") is shown as not signed in. The ping runs when the user selects the backend, not on every chunk.

When a live turn fails, or 30 seconds pass with no reply, the status says the backend is waiting or dead. The tail continues. Reconnect opens a new conversation with `live-notes.md` and the last 20 transcript lines. The recording is left running.

`already recording` and `refuse: … transcript-live.md exists` are the start-gate cases above. A kill of the recorder happens only after the second `stop` failed and the user confirmed.

macOS may attach Microphone and System Audio Recording to the window app or to `meeting-capture`. The window does not click through those dialogs. It quotes the log line and names the binary in it.

## Testing

Automated tests are Swift tests. They do not call a live CLI, the microphone, or the network. A fake session records the prompts it was given and returns a canned line.

- Start-command builder: the working directory is the project, one `--device`, optional `--tap-app`, `--lang`, and never `--screen`, `--app`, or a second device.
- Transcript parser: speech, `(silence)`, `(silence — prompt echo)`, `[END]`.
- Turn queue: a second speech line waits and joins the next prompt. A typed question is the next prompt ahead of queued speech.
- `live-notes` writer: emoji lines are appended in the `- [stamp]` form. Gist lines are not.
- Summary filenames advance `summary.md`, `summary-v2.md`, `summary-v3.md`.
- Log classifier maps each row in the table above to the right status.
- Context pack: existing files are included, missing files are skipped, output stops at 3000 characters.
- Ollama note prompt: over the 7000-character budget, silence lines are gone, and the shortened marker is present.
- Fake session: a canned `📌` line is appended to `live-notes.md`. A failing fake sets the reconnect status and does not stop the tail.

`python3 -m unittest test_meeting` in the skill's `scripts/` is run once to confirm this app did not change the recorder. New recorder tests are not added there.

A developer menu item, Replay a recording…, calls `meeting.py start <name> --replay <wav>`. That is the manual path for a meeting with no microphone. One manual pass uses that replay with Ollama. One manual pass uses it with a single cloud backend. A real call tap is checked by hand. `recorder.log` shows `meeting-capture: levels` with both mic and tap moving. Permission dialogs are checked by hand on a fresh grant.

## Success

- Start is impossible until consent is checked and both preflights pass.
- A meeting shows transcript lines, and silence does not call the model.
- Speech produces secretary lines from the backend that was picked, and actionable lines land in `live-notes.md`.
- Stop writes `summary.md` in the meeting folder, using the template headings, without overwriting an older note.
- After a crash or a force-quit, the next launch can attach to the recorder that is still running.
- A missing permission or a dead backend is a status line. The transcript file keeps growing until the recorder itself exits.
