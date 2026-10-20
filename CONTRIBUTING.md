# Contributing

```sh
bash test/run.sh                                # tests with every editor found (or: nvim, vim)
VIM_PROJECT_TEST_CASES=perf bash test/run.sh    # time budgets of the code run on every key
vint --error plugin autoload
docs/demo/render.sh                             # re-record the README animations with VHS
```

## Tests

Tests are `Test_*` functions in `test/cases/*.vim`, run headlessly by `test/runner.vim`. Helpers shared by the cases are in `test/helpers.vim`.

CI runs them with Vim and Neovim, each with and without rg, ag and fd, and with the oldest supported Vim 8.2.3591 and Neovim 0.5.1. Editors that can't read script variables by `getscriptinfo()` load the plugin from a temporary copy, where each script ends with a function returning its `s:` dict.

Vim runs the tests in Ex mode (`-es`), where a list waiting for a key reads stdin when no keys are typed ahead, and exits. Feed the keys a test types with `feedkeys()` before opening the list, rather than from a timer.

## Time budgets

`test/perf/` holds time budgets for the code that runs on every key typed in a list, on generated projects of 40k files and 20k commits. Change that code with them in mind.

## Demos

The README animations come from the VHS tapes in `docs/demo/`: `setup.sh` builds the demo projects, `vimrc` is the editor config, and `render.sh` records every tape (or the ones named) into `docs/images/`. Record them again when the plugin changes what they show. Needs [VHS](https://github.com/charmbracelet/vhs), nvim, git and fd or find.
