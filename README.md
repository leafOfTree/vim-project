# vim-project

A vim plugin to manager projects and sessions. 

Support 

- Project-related configurations and sessions
- Git branch awareness

> Vim feature`job` and command `tail` are required for branch awareness

## Usage

```vim
set sessionoptions-=options
call project#begin()

" Add '~/repository/project-name'
ProjectBase '~/repository'
Project 'project-name'

ProjectBase '/path/to/vundle/plugins'
Project 'vim-matchtag', { 'note': 'Just for test' }

" Absolute path that starts with '~' or '/' or 'C:'
Project '~/repository/svelte-mode'

" Map custom keys for useful commands
nnoremap <c-e> :ProjectList<cr>
nnoremap ;i    :ProjectInfo<cr>
nnoremap ;q    :ProjectExit<cr>
nnoremap ;h    :ProjectRoot<cr>
nnoremap ;c    :ProjectConfig<cr> 

" You need to type the project name. You can use <tab> for autocompletion
nnoremap ;o    :ProjectOpen 
```

Then you can press <kbd>c-e</kbd> or `:ProjectList` to display the project list and <kbd>Enter</kbd> to open a project. 

[The prompt mapping defautls](#prompt-mapping)

It's recommended but not necessary to `set sessionoptions-=options` to avoid options overload.

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

First of all, `call project#begin()` provides the basic `ProjectBase` and `Project` commands.

| command                     | description                               |
|-----------------------------|-------------------------------------------|
| ProjectBase `<base>`        | Set base directory for following projects |
| Project `<name>[, options]` | Add project                               |
| ProjectList                 | Show projects                             |
| ProjectInfo                 | Show project info                         |
| ProjectExit                 | Exit project                              |
| ProjectRoot                 | Goto project root directory               |
| ProjectConfig               | Goto project config directory             |
| ProjectOpen `<name>`        | Open a project by name                    |

## Configuration

| variable                      | description                                       | default    |
|-------------------------------|---------------------------------------------------|------------|
| g:vim_project_config          | The config directory                              | `'~/.vim'` |
| g:vim_project_open_root       | Open project root regardless of sessions          | 0          |
| g:vim_project_ignore_branch   | Ignore the branch change                          | 0          |
| g:vim_project_ignore_session  | Ignore sessions(No loading and saving)            | 0          |
| g:vim_project_prompt_mapping  | Key mapping for prompt input                      | *see ^*    |
| g:vim_project_debug           | Show debug messages                               | 0          |

<a name="prompt-mapping"></a>
- ^: The key mapping for prompt input is of type `dict` and defaults to 

    ```vim
    let g:vim_project_prompt_mapping = {
      \'open_project': "\<cr>",
      \'close_list': "\<esc>",
      \'clear_char': ["\<bs>", "\<c-a>"],
      \'clear_word': "\<c-w>",
      \'clear_all': "\<c-u>",
      \'prev_item': ["\<c-k>", "\<s-tab>", "\<up>"],
      \'next_item': ["\<c-j>", "\<tab>", "\<down>"],
      \'first_item': ["\<c-h>", "\<left>"],
      \'last_item': ["\<c-l>", "\<right>"],
      \}
    ```

    Note: the cursor in prompt input can't be moved around.

- The config directory is like `~/.vim/vimproject/<project_name>/`, where `init.vim`, `quit.vim`, and `sessions/` files for each project stay.

## Statusline

You can get project info from `g:vim_project`. It's a dict variable, try `echo g:vim_project` after opening a project.

For example, define a function called `GetProjectInfo` and add `[%{GetProjectInfo()}]` to the statusline for showing current project name and branch.

```vim
function! GetProjectInfo()
  if exists('g:vim_project_loaded')
    let name = get(g:vim_project,'name','')
    let branch = g:vim_project_branch
    return empty(name)? '' : name.','.branch
  endif
endfunction
```

## Credits

Thanks to timsofteng for the great idea. It all started with that.

[1]: https://github.com/VundleVim/Vundle.vim
[2]: https://github.com/tpope/vim-pathogen
[3]: https://github.com/junegunn/vim-plug
