<img src="https://raw.githubusercontent.com/leafOfTree/leafOfTree.github.io/master/vim-project.svg" height="60" alt="icon" align="left"/>

# vim-project

A vim plugin to manage projects

**Add / Open a project**
<p align="center">
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/project-1.png" width="180" />
➡️
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/project-2.png" width="180" />
➡️
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/project-3.png" width="180" />
➡️
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/project-4.png" width="180" />
</p>

**Search files / Find in files / Find and replace in a project**

<p align="center">
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/search-files.png" width="380" />
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/find-in-files.png" width="380" />
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/find-and-replace.png" width="380" />
</p>


**Features**

- Switch between projects

Project wide

- Search files by name
- Find in files
- Find and replace (**experimental**)
- Config
- Session (optional)

    You can save session per branch if both vim feature `job` and shell command `tail` are preset

## Basic Usage

- `:Project </path/to/project>`
- `:ProjectList` 
- `:ProjectSearchFiles`
- `:ProjectFindInFiles`

In a list, filter and select an item by <kbd>Up</kbd> <kbd>Down</kbd>. Then press <kbd>Enter</kbd> to open it. 

> For other keymaps, see [Keymaps](#config_keymaps)

## Installation

You could install it just like other plugins.

<details>
<summary><a>How to install</a></summary>

- [VundleVim][1]

        Plugin 'leafOfTree/vim-project'

- [vim-pathogen][2]

        cd ~/.vim/bundle
        git clone https://github.com/leafOfTree/vim-project --depth 1

- [vim-plug][3]

        Plug 'leafOfTree/vim-project'

- Or manually, clone this plugin to `path/to/this_plugin`, and add it to `rtp` in vimrc

        set rtp+=path/to/this_plugin

<br />
</details>


## Workflow

- Add: `:Project <path/to/project>`

- Open: `:ProjectList` | `:ProjectOpen <name>`

- Quit: `:ProjectQuit` | Open another project | Quit vim

- Remove: `:ProjectRemove <name>`

## Config files

The config files are located at `~/.vim/vim-project-config/`, where `<project-name>/` is for each project

`:ProjectAllConfig` and `:ProjectConfig` will open the two paths

```
~/.vim/vim-project-config/
     | project.add.vim            " Added projects
     | project.igonre.vim         " Ignored projects
     | <project-name>/
         | init.vim               
         | quit.vim               
         | sessions/              " session for each branch
             | master.vim
             | dev.vim

```

Open 

- Load session
- Source project's `init.vim`

Quit

- Save session
- Source project's `quit.vim`


## Commands

| command                    | description                       |
|----------------------------|-----------------------------------|
| Project `<path>[, option]` | Add project                       |
| ProjectOpen `<name>`       | Open a project by name            |
| ProjectRemove `<name>`     | Remove a project by name          |
| ProjectList                | Show all projects                 |
| ProjectSearchFiles         | Search files by name              |
| ProjectFindInFiles         | Find given string/regexp in files |
| ProjectInfo                | Show project info                 |
| ProjectQuit                | Quit project                      |
| ProjectEntry               | Open project entry                |
| ProjectConfig              | Open project config directory     |
| ProjectAllConfig           | Open all config directory         |
| ProjectIgnore `<path>`     | Ignore project for auto detection |

> You can try to adjust `wildmenu`, `wildmode` for enhanced command-line completion

### :Project `<path>[, option]`

`path`: If `path` is relative or just a project name which doesn't start with `/`, `~` or `C:`, it'll try any of `g:vim_project_config.project_base` as its base which defaults to `[~]`. You can use <kbd>Tab</kbd> to auto complete the path

`note`: Description shown in project list (optional)

Example
```vim
Project /path/to/demo, { note: 'A demo' }

" When g:vim_project_config.project_base is set to ['/path/to']
Project demo
```

### Project search files / find in files

- `:ProjectSearchFiles` Under the hood, it tries [[fd][4], `find`, `glob (vim function)`] for the first available one as the search engine.

- `:ProjectFindInFiles` Under the hood, it tries [[rg][5], [ag][6], `grep`, `vimgrep (vim function)`] for the first available one as the search engine.

It's recommended to install one of [[fd][4], `find`] and one of [[rg][5], [ag][6], `grep`]. They have better performance especially for Windows users and large projects.

#### Config

For consistency, the behaviors are supposed to be controlled as below no matter which engine is actually used.

- Include & Exclude

    Check below options in the [config](#config_keymaps) 

    - `search_include`
    - `search_exclude`
    - `find_in_files_include`
    - `find_in_files_exclude`

Only for `find in files`

- Match case

    Prefix your input with `\C`. By default it's case insensitive.

- Regexp

    Prefix your input with `\E`. By default it's treated as literal/fixed string.

<a name="config_keymaps"></a>

## Config and Keymaps

- `g:vim_project_config` (global)
- `g:vim_project_local_config` (project local)

The `g:vim_project_config` should be set at `.vimrc`. Its default value is below. You can copy it as a starting point

```vim
let g:vim_project_config = {
      \'config_home':                   '~/.vim/vim-project-config',
      \'project_base':                  ['~'],
      \'use_session':                   0,
      \'open_entry_when_use_session':   0,
      \'check_branch_when_use_session': 0,
      \'project_entry':                 './',
      \'auto_load_on_start':            0,
      \'search_include':                ['./'],
      \'search_exclude':                ['.git', 'node_modules'],
      \'find_in_files_include':         ['./'],
      \'find_in_files_exclude':         ['.git', 'node_modules'],
      \'auto_detect':                   'no',
      \'auto_detect_file':              ['.git', '.svn'],
      \'project_views':                 [],
      \'file_map':                      {},
      \'debug':                         0,
      \}

" Keymaps for list prompt
let g:vim_project_config.list_map = {
      \'open':             "\<cr>",
      \'open_split':       "\<c-s>",
      \'open_vsplit':      "\<c-v>",
      \'open_tabedit':     "\<c-t>",
      \'close_list':       "\<esc>",
      \'clear_char':       ["\<bs>", "\<c-a>"],
      \'clear_word':       "\<c-w>",
      \'clear_all':        "\<c-u>",
      \'prev_item':        ["\<c-k>", "\<up>"],
      \'next_item':        ["\<c-j>", "\<down>"],
      \'first_item':       ["\<c-h>", "\<left>"],
      \'last_item':        ["\<c-l>", "\<right>"],
      \'scroll_up':        "\<c-p>",
      \'scroll_down':      "\<c-n>",
      \'prev_view':        "\<s-tab>",
      \'next_view':        "\<tab>",
      \'replace_prompt':   "\<c-r>",
      \'replace_dismiss':  "\<c-d>",
      \'replace_confirm':  "\<c-y>",
      \'switch_to_list':   "\<c-o>",
      \}
```

| Option                        | Description                                                                   |
|-------------------------------|-------------------------------------------------------------------------------|
| config_home                   | The directory for all config files                                            |
| project_base                  | The base directory for relative path                                          |
| use_session                   | Use session                                                                   |
| open_entry_when_use_session   | When session used, always open project entry at the beginning                 |
| check_branch_when_use_session | When session used, keep one for each branch                                   |
| project_entry                 | Relative directory or file as project entry                                   |
| auto_detect                   | Auto detect projects when opening a file. <br>Choose 'always', 'ask', or 'no' |
| auto_detect_file              | File used to detect potential projects                                        |
| auto_load_on_start            | Auto load a project if Vim starts within its directory                        |
| list_map                      | KeyMaps for list prompt                                                       |
| search_include                | List of including folders for search files                                    |
| search_exclude                | List of excluding folders for search files                                    |
| find_in_files_include         | List of including folders for find in files                                   |
| find_in_files_exclude         | List of excluding folders for find in files                                   |
| file_map                      | Define keymaps to siwtch between files quickly                                |
| project_views                 | Define project views by `[[show-pattern, hide-pattern?], ...]`                |
| debug                         | Show debug messages                                                           |

### Project local config

Those config options can be overridden by `g:vim_project_local_config` in the project's `init.vim`. For example

```
let g:vim_project_local_config = {
  \'use_session': 0,
  \'open_entry_when_use_session': 0,
  \'check_branch_when_use_session': 0,
  \'search_include': ['./'],
  \'search_exclude': ['.git', 'node_modules'],
  \'find_in_files_include': [],
  \'find_in_files_exclude': ['.git', 'node_modules'],
  \'project_entry': './src',
  \}
```

For project local file map, see below.

### Switch between files

You can define mappings to frequently changed files in project's `init.vim`

For example, with below example, you can

- Switch to `autoload/project.vim` by `'a` and so on

- Switch between `['autoload/project.vim', 'plugin/project.vim']` by `'l`

- Switch to file returned by user-defined function by `'c`

```vim
function! StyleFromUpperDir()
  let upper_dir = expand('%:p:h:h')
  let name = expand('%:r')
  return upper_dir.'/'.name.'.css'
endfunction

let g:vim_project_local_config.file_map = {
      \'direct': {
      \   'file': ['autoload/project.vim', 'plugin/project.vim', $vim_project_config.'/init.vim', 'README.md'],
      \   'key': ['a', 'p', 'i', 'r'],
      \},
      \'link': {
      \   'file': ['autoload/project.vim', 'plugin/project.vim'],
      \   'key': 'l',
      \},
      \'custom': {
      \   'file': function('StyleFromUpperDir'),
      \   'key': 'c',
      \},
      \}
```

Another example where you can

- Switch between linked file type such as `*.html` and `*.css` at the same path
- Switch to file returned by `:h lambda` expression

```vim
let g:vim_project_local_config.file_map = {
      \'link': {
      \   'file': ['html', 'css'],
      \   'key': 'l',
      \},
      \'custom': {
      \   'file': {->expand('%:p:h:h').'/'.expand('%:r').'.css'},
      \   'key': 'c',
      \},
      \}
```

With `file_open_types`, you can use `'a`, `'va`, `'sa`, `'ta'` to edit file in different ways
```vim
let g:vim_project_config.file_open_types = {
      \'':  'edit',
      \'v': 'vsplit',
      \'s': 'split',
      \'t': 'tabedit',
      \}
```

### Session options

See `:h sessionoptions`

### Project views

In project list, you can switch between different views with <kbd>tab</kbd> and <kbd>s-tab</kbd>. You can set `project_views` to `[[show_pattern, hide_patten?], ...]` like

```vim
let g:vim_project_config.project_views = [
      \['vim', 'plugin'],
      \['^vue'],
      \['^react'],
      \]
```

## Global variables

- `g:vim_project` *dict*: current project info
- `$vim_project` *string*: current project path
- `$vim_project_config` *string*: current project config path

## Statusline

You can get current project info from `g:vim_project`. Try `echo g:vim_project` after opening a project

For example, define a function called `GetProjectInfo` and add `%{GetProjectInfo()}` to `statusline` to show current project name and branch

```vim
function! GetProjectInfo()
  if exists('g:vim_project_loaded') && !empty(g:vim_project)
     let name = g:vim_project.name
     let branch = g:vim_project.branch
     if empty(branch)
       return '['.name.']'
     else
       return '['.name.', '.branch.']'
     endif
   else
     return ''
  endif
endfunction

set statusline=%<%t%m\ %y\ %=%{GetProjectInfo()}
```

## Credits

Thanks to timsofteng for the great idea. It all started with that

[1]: https://github.com/VundleVim/Vundle.vim
[2]: https://github.com/tpope/vim-pathogen
[3]: https://github.com/junegunn/vim-plug
[4]: https://github.com/sharkdp/fd
[5]: https://github.com/BurntSushi/ripgrep
[6]: https://github.com/ggreer/the_silver_searcher
