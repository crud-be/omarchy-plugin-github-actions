# GitHub Actions for Omarchy

A native [Omarchy](https://omarchy.org/) bar widget for the GitHub Actions workflows of every repository and organization you can access. See what is running, check the last result, jump to runs on GitHub, and trigger workflows with their inputs. Follows your desktop theme.

## Install

```sh
omarchy plugin add https://github.com/crud-be/omarchy-plugin-github-actions.git --enable
```

Requires Omarchy 4.0 or newer with the Quickshell-based shell, Python 3 with PyYAML (`python-yaml`), and the [GitHub CLI](https://cli.github.com) signed in with `gh auth login`. No tokens to paste: the plugin uses `gh auth token`, so it sees every repository `gh` can, including organizations.

## Use

- Click the GitHub icon in the bar. It turns amber while workflows are running.
- Workflows are grouped per repository. Click a repository to expand or collapse it; its header shows the combined status (running, failed, or passing).
- Each workflow shows its last run status, branch, trigger event, and age. Click it to open the last run on GitHub, or the workflow page when it never ran.
- Press ▶ on a workflow to run it. The form shows a branch or tag field (default branch prefilled) and a field for each `workflow_dispatch` input: a switch for booleans, a dropdown for choices, and a text field otherwise. GitHub validates required inputs and errors are shown in the form.
- Open settings (gear) to choose which workflows are shown. The choice is stored in `~/.config/github-actions/hidden.json`.

Workflows refresh every 5 minutes by default (configurable in the widget settings), every 15 seconds while the panel is open and something is running, and a few seconds after you trigger a run.

| Key | Action |
| --- | --- |
| `r` | Refresh |
| Escape | Go back or close |
| Tab | Switch to the next bar panel |

IPC target `bvr.github-actions` provides `open`, `close`, `toggle`, and `refresh`:

```sh
qs ipc -p /usr/share/omarchy/shell call bvr.github-actions refresh
```

## Update or remove

```sh
omarchy plugin update bvr.github-actions
omarchy plugin remove bvr.github-actions
```

If the shell keeps showing old components after an update, run `omarchy restart shell`.

## Implementation

A short-lived Python helper (`github_actions.py`) talks to the GitHub REST API with the token from `gh auth token`. Archived repositories are skipped, as are repositories where Actions are disabled or inaccessible. Per repository it reads the workflows and the 100 most recent runs, falling back to one request per workflow whose last run is older. Repositories are fetched in parallel; a refresh across ~40 repositories takes around 15 seconds and costs a few requests per repository against your 5,000/hour API limit.

Dynamic workflows (such as Pages or Dependabot) and workflows disabled on GitHub cannot be triggered. Workflow inputs are read from the workflow file on the selected branch when you open the run form.

## Development

```sh
ln -s "$PWD" ~/.config/omarchy/plugins/bvr.github-actions
omarchy-shell shell rescanPlugins
omarchy plugin enable bvr.github-actions
omarchy plugin validate .
python3 -m unittest discover -s tests
```

Saved changes under `~/.config/omarchy/plugins/` reload automatically.

## License

MIT
