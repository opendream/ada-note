# Ada Note

A Mac window that transcribes a meeting and writes a note.

The window stays above other windows. It records the microphone, and the other side of a call when you name the call app. You pick one backend at the start. That backend writes live secretary lines. Stop writes an English summary.

Backends are Claude Code, Codex, Antigravity (`agy`), and Ollama on this Mac.

## Privacy

Audio stays on the Mac, under `<project>/.meetings/`. Transcript text goes to the backend you picked. Claude, Codex, and Antigravity send that text off the Mac. Ollama talks only to `127.0.0.1:11434`.

Recording starts after you confirm that everyone in the meeting knows it is being recorded.

## Requirements

- macOS 14 or later
- Swift 5.9, from the Xcode command line tools
- Python 3
- The meeting-secretary recorder from [noomz/noomz-claude-skills](https://github.com/noomz/noomz-claude-skills)
- [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp), plus the Qwen3-ASR and Silero VAD models. The Setup button lists the install commands. It does not start a meeting.
- One of `claude`, `codex`, `agy`, or `ollama` with the `qwen3.8` model

## Build

```sh
git clone https://github.com/opendream/ada-note.git
cd ada-note
swift test
./scripts/bundle-app.sh
open "Ada Note.app"
```

`swift test` does not call a live CLI, the microphone, or the network. `scripts/bundle-app.sh` builds `Ada Note.app`. The binary inside the bundle is still named `MeetingWindow`.

## Recorder

Ada Note does not capture audio itself. It runs `meeting.py` from the meeting-secretary skill, with the working directory set to the project you picked.

The Recorder field is filled in this order:

1. `ADA_NOTE_RECORDER`, when it names a `meeting.py` path
2. A saved path from the Recorder field
3. `~/.claude/plugins/marketplaces/noomz-claude-skills/skills/meeting-secretary/scripts/meeting.py` when that file exists
4. `meeting.py` in a `noomz-claude-skills` checkout next to this repository
5. The Claude marketplace path above, even when the file is not there yet

Paste another path into the Recorder field if you keep the skill somewhere else. The window remembers that path.

Vocab terms come from `assets/vocab.txt` next to that script when the file exists, from `<project>/.claude/meeting-vocab.txt`, and from this meeting's `vocab-extra.txt`.

## Backends

The live session may read files in the project. It does not edit them. On Claude, the note pass may run `gh pr view`, `gh issue view`, and `gh issue list`. The other backends say GitHub was not checked.

Ollama uses the model `qwen3.8` at `http://127.0.0.1:11434`.

## Layout

`Sources/MeetingCore` holds the rules that can be tested without a microphone or a live CLI. `Sources/MeetingWindow` is the SwiftUI panel. Design notes from the first build are in `docs/superpowers/`.

## Known limits

A long Ollama note can be written from the live notes only. `NotePrompt` packs `live-notes.md` before the transcripts and stops once the budget is full, so both transcript files can be left out.

This release has not been checked with a replayed recording, a real call, or a denied microphone. The window does not record the screen, post the note, or edit the project.

## License

Ada Note is licensed under the [MIT License](LICENSE). Copyright 2026 Opendream and contributors.

The meeting recorder and the speech models stay in their own projects and keep their own licenses.
