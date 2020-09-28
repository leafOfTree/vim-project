# vim-project

A vim plugin to manager projects and sessions. 

Support 

- Project-related configurations and sessions
- Git branch awareness

> Vim feature`job` and command `tail` are required for branch awareness

## usage

```vim
set sessionoptions-=options
call project#begin()

ProjectBase '~/repository'
Project 'tmp', { 'note': 'Just for test' }

ProjectBase '~/repository/vundle/plugins'
Project 'vim-matchtag'

" Absolute path that starts with '~' or '/' or 'C:'
Project '~/repository/svelte-mode'

" Map custom keys for useful commands
nnoremap <c-e> :ProjectList<cr>
nnoremap ;i    :ProjectInfo<cr>
nnoremap ;q    :ProjectExit<cr>
nnoremap ;h    :ProjectHome<cr>
nnoremap ;c    :ProjectConfig<cr> 

" You need to type the project name. You can use <tab> for autocompletion
nnoremap ;o    :ProjectOpen 
```

Then you can press <kbd>c-e</kbd>(:ProjectList) to open a project from the list.

It's recommended to `set sessionoptions-=options` and only set it back when you require it.

## Installation

<details>
<summary><a>How to install</a></summary>

- [VundleVim][1]

        Plugin 'leafOfTree/vim-matchtag'

- [vim-pathogen][2]

        cd ~/.vim/bundle && \
        git clone https://github.com/leafOfTree/vim-matchtag --depth 1

- [vim-plug][3]

        Plug 'leafOfTree/vim-matchtag'

- Or manually, clone this plugin to `path/to/this_plugin`, and add it to `rtp` in vimrc

        set rtp+=path/to/this_plugin

<br />
</details>

## Workflow

- Add projects

    `:Project <project-name>[, options]`

- Open a project

    `:ProjectList`

    `:ProjectOpen <project-name>`

    - Load the session
    - Source `init.vim` if exists

- Edit files

- Exit the project (Also when Open another project / Quit vim)
    
    `:ProjectExit`

    - Save the session
    - Source `quit.vim` if exists

## Commands

| command            | description                   |
|--------------------|-------------------------------|
| ProjectList        | Show projects                 |
| ProjectInfo        | Show project info             |
| ProjectExit        | Exit project                  |
| ProjectHome        | Goto project home directory   |
| ProjectConfig      | Goto project config directory |
| ProjectOpen <name> | Open a project by name        |

## Configuration

| variable                      | description                                       | default    |
|-------------------------------|---------------------------------------------------|------------|
| g:vim_project_config          | The config directory                              | `'~/.vim'` |
| g:vim_project_start_from_home | Open project home on start regardless of sessions | 0          |
| g:vim_project_ignore_branch   | Ignore the branch change                          | 0          |
| g:vim_project_ignore_session  | Ignore sessions(No loading and saving)            | 0          |
| g:vim_project_prompt_mapping  | Key mapping for prompt input                      | *see ^*    |
| g:vim_project_debug           | Show debug messages                               | 0          |

- ^: The key mapping for prompt input is of type `dict` and defaults to

    ```vim
    let g:vim_project_prompt_mapping = {
          \'closeList': "\<Esc>",
          \'clearChar': ["\<bs>", "\<c-a>"],
          \'clearWord': "\<c-w>",
          \'clearAllInput': "\<c-u>",
          \'prevItem': "\<c-k>",
          \'nextItem': "\<c-j>",
          \'firstItem': "\<c-h>",
          \'lastItem': "\<c-l>",
          \'openProject': "\<cr>",
          \}
    ```

    Note: the cursor in prompt input can't be moved around.

- The config directory is like `~/.vim/vimproject/<project_name>/`, where `init.vim`, `quit.vim`, and `sessions/` files for each project stay.

## Statusline

You can get project info from `g:vim_project`. It's a dict variable, try `echo g:vim_project` after opening a project.

For example, define a function called `GetProjectInfo` and add `[%{GetProjectInfo()}]` to the statusline for showing current project name and branch.

```vim
function! GetProjectInfo()
  let name = get(g:vim_project,'name','')
  let branch = g:vim_project_branch
  return empty(name)? '' : name.','.branch
endfunction
```

## Credits

Thanks to timsofteng for the great idea. It all started with that.
