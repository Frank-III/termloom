# DiffScope

A compact fullscreen Git diff browser built as a separate `termloom` example package. It is intentionally a viewer, not a complete Git client: the example concentrates on large selectable collections, responsive panes, async detail loading, styled diffs, filtering, scrolling, overlays, mouse actions, and alternate-screen lifecycle.

By default it opens a metadata-shaped demonstration of [oven-sh/bun#30412](https://github.com/oven-sh/bun/pull/30412), a 2,188-file pull request. Patches are synthesized so the example is instant, deterministic, and does not bundle or download the million-line pull request.

```sh
cd Examples/DiffScope
swift run termloom-diffscope
```

Inspect changes in a local repository instead:

```sh
swift run termloom-diffscope --repo /path/to/repository
# A positional path works too:
swift run termloom-diffscope /path/to/repository

# Compare a checked-out pull-request head with its exact base commit:
swift run termloom-diffscope --repo /path/to/repository --base BASE_SHA
```

The live adapter invokes the installed `git` executable and remains read-only. Without `--base`, it compares the index and working tree with `HEAD`; untracked text files are shown as additions. With `--base`, it indexes `BASE_SHA..HEAD` using names and statuses only, then loads the selected file patch lazily. This keeps enormous pull requests responsive and avoids fetching every changed blob up front in a partial clone.

## Keys

- `Tab`, `1`, `2`: switch between file list and diff
- `j`/`k`, arrows, Page Up/Down, `g`/`G`: navigate
- `/`: filter paths; `x`: clear filter
- `h`/`l`, `0`: horizontal diff scrolling
- Mouse click: select a visible file
- `?`: help
- `q`: quit
