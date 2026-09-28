# GitHub Actions for Omarchy

A native [Omarchy](https://omarchy.org/) bar widget to trigger GitHub Actions workflows, with their inputs, for the repositories you add. Select a workflow to see its last three runs. Follows your desktop theme.

## Install

```sh
omarchy plugin add https://github.com/crud-be/omarchy-plugin-github-actions.git --enable
```

Requires Omarchy 4.0 or newer with the Quickshell-based shell, Python 3 with PyYAML (`python-yaml`), and the [GitHub CLI](https://cli.github.com) signed in with `gh auth login`. No tokens to paste: the plugin uses `gh auth token`, so you can add any repository `gh` can access, including organizations.

## Use

- Click the GitHub icon in the bar. It turns amber while workflows are running.
- Add repositories with **Add repository** (or `+` in settings). Search the repositories you have access to, or type any `owner/name` and press Enter. They are stored in `~/.config/github-actions/repos.json`.
- Workflows are grouped per repository, most recently run first. Click a repository to expand or collapse it.
- Press ▶ on a workflow to run it. The form has the branch or tag (default branch prefilled) and a field for each `workflow_dispatch` input: a switch for booleans, buttons for choices, and a text field otherwise. Pick several values of a choice (say both `prd` and `stg`) to run the workflow once per value, back to back. GitHub validates required inputs and errors are shown in the form.
- Click a workflow to select it and see its last three runs. Click a run to open it on GitHub.
- Open settings (gear) to add or remove repositories and to choose which workflows are shown. Search to filter workflows. The choice is stored in `~/.config/github-actions/hidden.json`.

Workflows refresh every 5 minutes by default (configurable in the widget settings), every 15 seconds while the panel is open and something is running, and a few seconds after you trigger a run.

| Key | Action |
| --- | --- |
| `r` | Refresh |
| Escape | Go back or close |
| Tab | Switch to the next bar panel |

IPC target `crud.github-actions` provides `open`, `close`, `toggle`, and `refresh`:

```sh
qs ipc -p /usr/share/omarchy/shell call crud.github-actions refresh
```

## Update or remove

```sh
omarchy plugin update crud.github-actions
omarchy plugin remove crud.github-actions
```

If the shell keeps showing old components after an update, run `omarchy restart shell`.

## Implementation

A short-lived Python helper (`github_actions.py`) talks to the GitHub REST API with the token from `gh auth token`. A refresh only reads the repositories you added: per repository it reads the repository, its workflows, and its 100 most recent runs to see what is running and to order workflows by their last run, in parallel. The list of repositories you can access is only loaded when you open **Add repository**, and a workflow's last runs only when you select it.

Dynamic workflows (such as Pages or Dependabot) and workflows disabled on GitHub cannot be triggered. Workflow inputs are read from the workflow file on the selected branch when you open the run form.

## Development

```sh
ln -s "$PWD" ~/.config/omarchy/plugins/crud.github-actions
omarchy-shell shell rescanPlugins
omarchy plugin enable crud.github-actions
omarchy plugin validate .
python3 -m unittest discover -s tests
```

Saved changes under `~/.config/omarchy/plugins/` reload automatically.

## License

MIT
