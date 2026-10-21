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

## Smaller items

- Release through luarocks.
- Windows paths.
