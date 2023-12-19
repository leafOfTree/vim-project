<img src="https://raw.githubusercontent.com/leafOfTree/leafOfTree.github.io/master/vim-project.svg" height="60" alt="icon" align="left"/>

# vim-project

<p align="center">
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/project-3.png" width="220" />
</p>

A vim plugin to manage projects and sessions.

**Features**

- Switch between projects

Project-wide

- Search files by name
- Find in files
- Find and replace (**experimental**)
- Run tasks
- Search git log and file history
- Config
- Session (optional)

    You can save session per branch if both vim feature `job` and shell command `tail` are present.

---

<p><b>Add / Open a project</b></p>
<p>
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/project-1.png" width="30%" />
➡️
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/project-2.png" width="30%" />
➡️
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/project-3.png" width="30%" />
</p>

---

<p><b>Search files / Find in files / Find and replace in a project</b></p>
<p>
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/search-files.png" width="380" />
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/find-in-files.png" width="380" />
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/find-and-replace.png" width="380" />
</p>

---

* [Basic Usage](#basic-usage)
* [Installation](#installation)
* [Uninstallation](#uninstallation)
* [Workflow](#workflow)
* [Commands](#commands)
  * [:Project `<path>[, option]`](#project-path-option)
  * [Search files / Find in files](#search-files--find-in-files)
    * [Config for search / find](#config-for-search--find)
  * [Run tasks](#run-tasks)
* [Config and Keymappings](#config-and-keymappings)
  * [Config files](#config-files)
  * [Project local config](#project-local-config)
  * [Switch between files](#switch-between-files)
  * [Session options](#session-options)
  * [Project views](#project-views)
* [Global variables](#global-variables)
* [Statusline](#statusline)
  * [Title](#title)
* [Debug](#debug)
* [Credits](#credits)

## Basic Usage

- `:Project /path/to/project`
- `:ProjectList` 
- `:ProjectSearchFiles`
- `:ProjectFindInFiles`
- `:ProjectRun`
- `:ProjectGitLog`
- `:ProjectFileHistory`

In a list, filter by typing. Select an item by <kbd>c-j</kbd>, <kbd>c-k</kbd> or the arrow keys. Then press <kbd>Enter</kbd> to open it. 

See [Config and Keymappings](#config_keymappings) for details. 


## Installation


- [fd][4]
- [rg][5]/[ag][6]
- this plugin

It's recommended to install [fd][4] and one of [rg][5]/[ag][6] to improve search performance.

You can install this plugin just like others.

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

## Uninstallation

You need to remove this plugin as well as `config_home` (default: `~/.vim/vim-project-config`).

## Workflow

- Add `:Project <path/to/project>`

- Open `:ProjectList` | `:ProjectOpen <name>`

- Quit `:ProjectQuit` | Open another project | Quit vim

- Remove `:ProjectRemove <name>`

## Commands

| command                    | description                              |
|----------------------------|------------------------------------------|
| Project `<path>[, option]` | Add project, then open it                |
| ProjectList                | Show all projects                        |
| ProjectSearchFiles         | Search files by name                     |
| ProjectFindInFiles         | Find given string/regexp (at least 2 chars) in files |
| ProjectRun                 | Run a task defined by `tasks` config     |
| ProjectGitLog              | Show git log                             |
| ProjectFileHistory         | Show file history                        |
| ProjectRoot                | Open project root                        |
| ProjectConfig              | Open project config `init.vim` (effective after save) |
| ProjectAllConfig           | Open all projects config `project.add.vim` |
| ProjectInfo                | Show project brief info                  |
| ProjectAllInfo             | Show project all info                    |
| ProjectOpen `<name>`       | Open a project by name                   |
| ProjectRemove `<name>`     | Remove a project by name                 |
| ProjectRename `<name>` `<new_name>`     | Rename a project of `name` to `new_name`. Its folder's name is renamed, too |
| ProjectQuit                | Quit project                             |
| ProjectIgnore `<path>`     | Ignore project for auto detection        |

> You can try adjusting `wildmenu`, `wildmode` for enhanced command-line completion

### :Project `<path>[, option]`

`path`: If `path` is relative or a project name , it'll search with both current working directory and `g:vim_project_config.project_base` as path base . In addition, you can use <kbd>Tab</kbd> to auto complete the path.

> Relative means path doesn't start with `/`, `~` or `C:/`.

`option`

- `note`: Description shown on project list.

Example
```vim
Project /path/to/demo, { "note": "A demo" }

" Current working directory (:pwd) is /path/to
Project demo
Project ../to

" g:vim_project_config.project_base is set to ['/path/to']
Project demo
```

### Search files / Find in files

- `:ProjectSearchFiles` Under the hood, it tries [[fd][4], `find`, `glob (vim function)`] for the first available one as the search engine.

- `:ProjectFindInFiles` Under the hood, it tries [[rg][5], [ag][6], `grep`, `vimgrep (vim function)`] for the first available one as the search engine.

It's recommended to install one of [[fd][4], `find`] and one of [[rg][5], [ag][6], `grep`]. They have better performance especially for Windows users and large projects. However, none of them will respect `.gitignore` serving as a search engine for consistency.

To enable `:ProjectFindInFiles` on visually selected word, use `noremap` as follows

```vim
noremap <c-f> :ProjectFindInFiles<cr>
```

#### Config for search / find

For consistency, the behaviors are controlled as below no matter which engine is used.

Both `Search files` and `Find in files`

- Include & Exclude

    Check the following options in the [config](#config_keymappings).

    - `include`
    - `exclude`

    The following are specific options to extend the above. The final result is like `include (global + local)` + `search_include (global + local)`.

    - `search_include`
    - `find_in_files_include`
    - `search_exclude`
    - `find_in_files_exclude`

`Find in files`

- Match case

    Prefix your input with `\C`. By default, it's case insensitive.

- Regexp

    Prefix your input with `\E`. By default, it's treated as a literal/fixed string.

`Find and replace` ⚠️

Please note this feature is not fully tested. It may cause unexpected changes to your files. Always remember to commit your changes before running it. Feel free to open an issue if anything goes wrong.

When `Find in files`, you can press <kbd>c-r</kbd> to start to replace, <kbd>c-y</kbd> to confirm. <kbd>c-d</kbd> to dismiss any item on the list.

<a name="config_keymappings"></a>

### Run tasks

`:ProjectRun` run a task defined by `tasks`. A task contains

- `name`: task name
- `cmd`: command to run in terminal through shell
- `cd`: change directory to current project relatively
- `show`, `hide`: both are a list of patterns to fiter task output

For example, with below local config

```vim
let g:vim_project_local_config = {
    \'tasks': [
      \{
        \'name': 'dev',
        \'cmd' : 'npm run dev',
        \'cd'  : 'webapp'
      \},
      \{ 
        \'name': 'build', 
        \'cmd': 'npm build'
        \'show': ['tests run.*in', '^\s\+'],
        \'hide': ['info'],
      \}, 
      \{ 
        \'name': 'terminal', 
        \'cmd': ''
      \}, 
    \],
\}
```

**Run, Rerun, Stop**: 
You can press 

- <kbd>Enter</kbd> to run/rerun the task
- <kbd>c-q</kbd> to stop the task and remove its output.
- <kbd>c-o</kbd> to open the corresponding terminal buffer (not work for nvim)

**Vim terminal**: 
If you set `cmd` to empty string `''`, it'll call `:terminal` to open a new Vim terminal window.

## Config and Keymappings

The config consists of following two parts

- `g:vim_project_config` (global, in `.vimrc`)
- `g:vim_project_local_config` (project local, in project's `init.vim`)

The `g:vim_project_config` should be set in `.vimrc`. Its default value is below. You can copy it as a starting point.

```vim
let g:vim_project_config = {
      \'config_home':                   '~/.vim/vim-project-config',
      \'project_base':                  ['~'],
      \'use_session':                   0,
      \'open_root_when_use_session':    0,
      \'check_branch_when_use_session': 0,
      \'project_root':                  './',
      \'auto_load_on_start':            0,
      \'include':                       ['./'],
      \'exclude':                       ['.git', 'node_modules', '.DS_Store'],
      \'search_include':                [],
      \'find_in_files_include':         [],
      \'search_exclude':                [],
      \'find_in_files_exclude':         [],
      \'auto_detect':                   'no',
      \'auto_detect_file':              ['.git', '.svn'],
      \'project_views':                 [],
      \'file_mappings':                 {},
      \'tasks':                         [],
      \'debug':                         0,
      \}

" Keymappings for list prompt
let g:vim_project_config.list_mappings = {
      \'open':                 "\<cr>",
      \'close_list':           "\<esc>",
      \'clear_char':           ["\<bs>", "\<c-a>"],
      \'clear_word':           "\<c-w>",
      \'clear_all':            "\<c-u>",
      \'prev_item':            ["\<c-k>", "\<up>"],
      \'next_item':            ["\<c-j>", "\<down>"],
      \'first_item':           ["\<c-h>", "\<left>"],
      \'last_item':            ["\<c-l>", "\<right>"],
      \'scroll_up':            "\<c-p>",
      \'scroll_down':          "\<c-n>",
      \'paste':                "\<c-b>",
      \'switch_to_list':       "\<c-o>",
      \}
let g:vim_project_config.list_mappings_projects = {
      \'prev_view':            "\<s-tab>",
      \'next_view':            "\<tab>",
      \}
let g:vim_project_config.list_mappings_search_files = {
      \'open_split':           "\<c-s>",
      \'open_vsplit':          "\<c-v>",
      \'open_tabedit':         "\<c-t>",
      \}
let g:vim_project_config.list_mappings_find_in_files = {
      \'open_split':           "\<c-s>",
      \'open_vsplit':          "\<c-v>",
      \'open_tabedit':         "\<c-t>",
      \'replace_prompt':       "\<c-r>",
      \'replace_dismiss_item': "\<c-d>",
      \'replace_confirm':      "\<c-y>",
      \}
let g:vim_project_config.list_mappings_run_tasks = {
      \'run_task':              "\<cr>",
      \'stop_task':             "\<c-q>",
      \'open_task_terminal':    "\<c-o>",
      \}
```

| Option                        | Description                                                                   |
|-------------------------------|-------------------------------------------------------------------------------|
| config_home                   | The directory for all config files                                            |
| project_base                  | A list of base directories used for path in `:Project path`                   |
| use_session                   | Use session                                                                   |
| open_root_when_use_session    | When session used, always open project root at the beginning                  |
| check_branch_when_use_session | When session used, keep one for each branch                                   |
| project_root                  | Relative directory or file as project root                                    |
| auto_detect                   | Auto detect projects when opening a file. <br>Choose 'always', 'ask', or 'no' |
| auto_detect_file              | File used to detect potential projects                                        |
| auto_load_on_start            | Auto load a project if Vim starts within its directory                        |
| list_mappings                 | Keymappings for list prompt                                                   |
| include                       | Including folders                                                             |
| exclude                       | Excluding folders/files                                                       |
| search_include                | Including folders for search files                                            |
| find_in_files_include         | Including folders for find in files                                           |
| search_exclude                | Excluding folders/files for search files                                      |
| find_in_files_exclude         | Excluding folders/files for find in files                                     |
| file_mappings                 | Keymappings to switch between files quickly                                   |
| tasks                         | tasks to run using vim 'terminal' feature                                     |
| project_views                 | Define project views by `[[show-pattern, hide-pattern?], ...]`                |
| debug                         | Show debug messages                                                           |

### Config files

The config files are located at `~/.vim/vim-project-config/`, where `~/.vim/vim-project-config/<project-name>/` is for each project.

`:ProjectAllConfig` and `:ProjectConfig` will open corresponding config files.

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

`init.vim` will get reloaded once you change and save it.

### Project local config

These options,  **list types can be extended**,  others overridden, via `g:vim_project_local_config` in the project's `init.vim`. E.g. 

```vim
let g:vim_project_local_config = {
  \'include': ['./'],
  \'exclude': ['.git', 'node_modules', '.DS_Store'],
  \'project_root': './',
  \'use_session': 0,
  \'open_root_when_use_session': 0,
  \'check_branch_when_use_session': 0,
  \}
```

For the project local `file_mappings`, see below.

### Switch between files

You can define mappings to frequently changed files in the project's `init.vim`.

For example as below, you can

- Switch to file `autoload/project.vim` by `'a` and so on
- Switch between files `['autoload/project.vim', 'plugin/project.vim']` by `'l`
- Switch between file types such as `*.html` and `*.css` at the same path with `'t`
- Switch to file returned by user-defined function with `'c`
- Switch to file returned by `:h lambda` expression with `'d`

```vim
function! StyleInUpperDir()
  let upper_dir = expand('%:p:h:h')
  let name = expand('%:r')
  return upper_dir.'/'.name.'.css'
endfunction

let g:vim_project_local_config.file_mappings = {
    \'r': 'README.md',
    \'a': 'autoload/project.vim', 
    \'p': 'plugin/project.vim', 
    \'l': ['autoload/project.vim', 'plugin/project.vim'],
    \'t': ['html', 'css'],
    \'c': function('StyleInUpperDir'),
    \'i': {->$vim_project_config.'/init.vim'},
    \'d': {-> expand('%:p:h:h').'/'.expand('%:r').'.css'},
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

See `:h sessionoptions`.

### Project views

In project list, you can switch between different views with <kbd>tab</kbd> and <kbd>s-tab</kbd>. You can set `project_views` to `[[show_pattern, hide_patten?], ...]` like

```vim
let g:vim_project_config.project_views = [
      \['vim', 'plugin'],
      \['^vue'],
      \['^react$'],
      \['.*', 'archived']
      \]
```

## Global variables

- `g:vim_project` *dict*: current project info
- `$vim_project` *string*: current project path
- `$vim_project_config` *string*: current project config path

## Statusline

You can get current project info from `g:vim_project`. Try `echo g:vim_project` after opening a project.

For example, define a function called `GetProjectInfo` and add `%{GetProjectInfo()}` to `statusline` to show current project name and branch.

```vim
function! GetProjectInfo()
  if exists('g:vim_project') && !empty(g:vim_project)
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

### Title

Or you can show project info on window title

```vim
set title titlestring=%{GetTitle()}

function! GetTitle()
  if exists('g:vim_project') && !empty(g:vim_project)
    return g:vim_project.name.' - '.expand('%')
  else
    return expand('%:p').' - '.expand('%')
  endif
endfunction
```

## Debug

If something goes wrong, you can try

- `:ProjectInfo`
- `:ProjectAllInfo`
- `:echo g:vim_project`
- `:let g:vim_project_config.debug = 1`

## Credits

Thanks to timsofteng for the great idea. It all started with that.

[1]: https://github.com/VundleVim/Vundle.vim
[2]: https://github.com/tpope/vim-pathogen
[3]: https://github.com/junegunn/vim-plug
[4]: https://github.com/sharkdp/fd
[5]: https://github.com/BurntSushi/ripgrep
[6]: https://github.com/ggreer/the_silver_searcher
