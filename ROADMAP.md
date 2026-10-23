# Roadmap

## Spaces

A space is a named source of notes. Today there is one: everything is stored
locally and every note is written with `space = "personal"` in `index.json`.
The plan is to let scholia work with several spaces and switch between them.

| Space             | Where notes live            | Who sees them              |
| ----------------- | --------------------------- | -------------------------- |
| Local personal    | `stdpath("data")/scholia`   | you, on this machine       |
| Remote personal   | your self-hosted server     | you, on every machine      |
| Team              | a self-hosted server        | members of the team        |
| Company           | a self-hosted server        | people in the company      |

Every remote space is a server that you, your team or your company run.
scholia will not depend on a third-party cloud.

### What it should feel like

- Switch the active space with a command or a key; the column shows notes of
  that space.
- A personal space on your own server syncs notes between machines and stays
  private.
- A team or company space shares notes about the code without putting comments
  into it: onboarding hints, known pitfalls, review remarks, links to tickets.
- Notes stay plain Markdown and keep working offline from a local copy.

### Open questions

- Showing notes of several spaces at once, with a color per space.
- Moving or copying a note from a personal space to a shared one.
- Authentication and access rights per space.
- Conflicts when the same note is edited on two machines.
- The server protocol and a reference server implementation.

## Diff-based anchoring

Today a note follows its code through extmarks while the buffer is open, and
through a text search on the first, last and surrounding lines when it is
loaded again. Edits made outside Neovim (`git pull`, rebase, another editor)
and small changes to the first line are enough to lose the anchor.

The plan is to map the old range onto the new file with a diff, the same way
Gerrit and GitHub move review comments between revisions.

- Keep a snapshot of every file that has notes, refreshed on each save.
- On load, diff the snapshot against the current file with `vim.diff` and map
  every note range through the hunks. No git and no commits required.
- Store the anchored code itself; when the diff says the range was deleted,
  search for that code elsewhere in the file to follow moved blocks.
- A note whose code is really gone becomes an orphan and shows the code it was
  attached to, so it is clear what to do with it.
- No commands and no confirmations: the note just follows the code.

### What it should feel like

| Change                                       | Result                       |
| -------------------------------------------- | ---------------------------- |
| Lines added or removed above the note        | note moves with the code     |
| Lines changed inside the annotated range     | range grows or shrinks       |
| Changes made outside Neovim                  | note moves with the code     |
| Block moved elsewhere in the file            | found by the stored code     |
| Block deleted                                | orphan, with the old code    |

### Open questions

- Following file renames, likely through `git diff -M` when a repository is
  available.
- Where snapshots are stored and when they are cleaned up.

## Render mode

Notes are Markdown and get treesitter highlighting, including fenced code
blocks. The plan is a render mode that shows a note the way Obsidian does and
can be toggled on the fly with a key.

- Rendered Markdown: headings, emphasis, lists, tables and links without the
  raw markup.
- Fenced code blocks with syntax highlighting and a clear frame.
- Mermaid diagrams and images drawn inside the note.
- One key switches between the raw text and the rendered view; editing always
  happens in the raw text.

### Open questions

- Building on render-markdown.nvim or markview.nvim versus a built-in
  renderer.
- Images need a terminal with a graphics protocol (kitty, WezTerm, Ghostty);
  a fallback for other terminals, such as a preview in the browser.
- Rendering Mermaid through `mmdc` and caching the result.

## Smaller items

- Release through luarocks.
- Windows paths.
