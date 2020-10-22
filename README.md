# vim-project

A vim plugin to manage projects and sessions. 

Support 

- Project-related configurations and sessions
- Git branch awareness

    Vim feature `job` and shell command `tail` are required for branch awareness

## Usage

First, add plugin configs and then call the entry function **AFTER** configs in `vimrc`

```vim
let g:vim_project_config = '~/.vim'

call project#begin()
```

Next, you can open any file under a project to trigger auto detection as described below.

### Auto detect projects

By default, `vim-project` automatically detect a new project when opening any file under it.

The record is saved to either `~/.vim/vim-project/_add.vim` or `~/vim/vim-project/_ignore.vim`. You can manually add or modify projects in these files later.

`vim-project` will find projects which contain files like `.git,.svn,package.json`.

```vim
let g:vim_project_config = '~/.vim'

" options: 'ask'(default), 'always', 'no'
let g:vim_project_auto_detect = 'ask'

call project#begin()
```

### Manually add proejcts

Or manually add projects by specifying their path **AFTER** entry function in `vimrc`. 
```vim
call project#begin()

" Add '~/repository/project-name'
ProjectBase '~/repository'
Project 'project-name'

ProjectBase '/path/to/vundle/plugins'
Project 'vim-matchtag', { 'note': 'Just for test' }

" Absolute path that starts with '~' or '/' or '\w:'
Project '~/repository/svelte-mode'
```

### Show projects

You can type `:ProjectList` to display the project list and press <kbd>Enter</kbd> to open a selected project. 

Ref: [The prompt mapping](#prompt-mapping).

## Installation

<details>
<summary><a>How to install</a></summary>

- [VundleVim][1]

        Plugin 'leafOfTree/vim-project'

- [vim-pathogen][2]

        cd ~/.vim/bundle && \
        git clone https://github.com/leafOfTree/vim-project --depth 1

- [vim-plug][3]

        Plug 'leafOfTree/vim-project'

- Or manually, clone this plugin to `path/to/this_plugin`, and add it to `rtp` in vimrc

        set rtp+=path/to/this_plugin

<br />
</details>

## Workflow

- Add projects
    - Auto

        Open any file under a project with auto detection enabled 

    - Manually 

        `:Project <project-name>[, options]` in `vimrc`

- Open a project

    `:ProjectList` or `:ProjectOpen <project-name>`

    - Load the session

    - Source project's `init.vim` if exists

- Edit files

- Exit the project(`:ProjectExit`) / Open another project / Quit vim

    - Save the session

    - Source project's `quit.vim` if exists

## Commands

First of all, `call project#begin()` to get the basic `ProjectBase` and `Project` commands.

| command                             | description                               |
|-------------------------------------|-------------------------------------------|
| ProjectBase `<base>`                | Set base directory for following projects |
| Project `<name or path>[, option]`  | Add project                               |
| ProjectIgnore `<path>`              | Ignore project for auto detection         |
| ProjectList                         | Show projects                             |
| ProjectInfo                         | Show project info                         |
| ProjectExit                         | Exit project                              |
| ProjectRoot                         | Goto project root directory               |
| ProjectConfig                       | Goto project config directory             |
| ProjectPluginConfig                 | Goto plugin config directory              |
| ProjectOpen `<name>`                | Open a project by name                    |

### Project option

```vim
Project 'demo', { 'note': 'Just for demo', 'root': 'src' }
```

- `note`: note shown on project list.
- `root`: root used when opening project root.

### Custom mapping for commands

You can add custom mappings for some useful commands as needed
```vim
nnoremap ;p    :ProjectList<cr>
nnoremap ;i    :ProjectInfo<cr>
nnoremap ;e    :ProjectExit<cr>
nnoremap ;r    :ProjectRoot<cr>
nnoremap ;c    :ProjectConfig<cr> 
nnoremap ;h    :ProjectPluginConfig<cr> 

" You need to type the project name. You can use <tab> for autocompletion
nnoremap ;o    :ProjectOpen 
```

## Configuration

| variable                       | description                                                 | default                  |
|--------------------------------|-------------------------------------------------------------|--------------------------|
| g:vim_project_config           | The config directory                                        | `'~/.vim'`               |
| g:vim_project_open_root        | Open project root regardless of sessions                    | 0                        |
| g:vim_project_ignore_branch    | Ignore the branch change                                    | 0                        |
| g:vim_project_ignore_session   | Ignore sessions. Thus no loading and saving                 | 0                        |
| g:vim_project_prompt_mapping   | Mapping for prompt                                    | *see ^*                  |
| g:vim_project_auto_detect      | Whether auto detect potential projects when opening a file. <br> Options are 'always', 'ask', or 'no'| `'ask'`                    |
| g:vim_project_auto_detect_sign | Sign for auto detecting potential projects                  | `'.git,.svn,package.json'` |
| g:vim_project_auto_indicator   | Indicator for auto added projects in project list           | `''`                       |
| g:vim_project_views            | Project views config with shape [[show, hide], ...]         | []                       |
| g:vim_project_debug            | Show debug messages                                         | 0                        |

<a name="prompt-mapping"></a>
**^**: The key mapping for prompt defaults to 

```vim
let g:vim_project_prompt_mapping = {
  \'open_project': "\<cr>",
  \'close_list':   "\<esc>",
  \'clear_char':   ["\<bs>", "\<c-a>"],
  \'clear_word':   "\<c-w>",
  \'clear_all':    "\<c-u>",
  \'prev_item':    ["\<c-k>", "\<up>"],
  \'next_item':    ["\<c-j>", "\<down>"],
  \'first_item':   ["\<c-h>", "\<left>"],
  \'last_item':    ["\<c-l>", "\<right>"],
  \'next_view':    "\<tab>",
  \'prev_view':    "\<s-tab>",
  \}
```

Note: Moving around the cursor in the prompt is not supported.

### Plugin config files hierarchy

The config directory for each project is like `~/.vim/vim-project/<project-name>/`.

```
~/.vim/vim-project/
                 | _add.vim    " auto added projects
                 | _igonre.vim " auto ignored projects (including added ones)
                 | <project-name>/
                                 | init.vim  " after loading session
                                 | quit.vim  " after saving session
                                 | sessions/ " session for each branch
                                           | master.vim
                                           | branch-1.vim
                                           | branch-2.vim
```

### Session options

Please see `:h sessionoptions`. It's recommended to `set sessionoptions-=options`.

### Project views

On project list, you can switch between different views with mapping <kbd>tab</kbd> and <kbd>s-tab</kbd>. You can define views by setting `g:vim_project_views` to `[[show_pattern, hide_patten], ...]` like below.

```vim
let g:vim_project_views = [
      \['vim', 'plugin'],
      \['^vue'],
      \['^react'],
      \]
```

## Statusline

You can get current project info from `g:vim_project` which is a dict variable. Try `echo g:vim_project` after opening a project.

For example, define a function called `GetProjectInfo` and add `[%{GetProjectInfo()}]` to the statusline for showing current project name and branch.

```vim
function! GetProjectInfo()
  if exists('g:vim_project_loaded')
    let name = get(g:vim_project,'name','')
    let branch = g:vim_project_branch
    return empty(name) ? '' : name.','.branch
  endif
endfunction
```

## Credits

Thanks to timsofteng for the great idea. It all started with that.

[1]: https://github.com/VundleVim/Vundle.vim
[2]: https://github.com/tpope/vim-pathogen
[3]: https://github.com/junegunn/vim-plug
