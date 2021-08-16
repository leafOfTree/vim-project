<img src="https://raw.githubusercontent.com/leafOfTree/leafOfTree.github.io/master/vim-project.svg" height="60" alt="icon" align="left"/>

# vim-project

### Add / Open a project
<p align="center">
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/project-1.png" width="180" />
➡️
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/project-2.png" width="180" />
➡️
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/project-3.png" width="180" />
➡️
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/project-4.png" width="180" />
</p>

### Search files / Find in files in a project

A vim plugin to manage projects

**Features**

- Switch between projects
- Config per project 
- Session per project and per branch

    Branch requires both vim feature `job` and shell command `tail` 

## Usage

- `:Project </path/to/project>`
- `:ProjectList` 

    It shows all projects that have been added. Navigate to target project and then press <kbd>Enter</kbd> to open it

## Installation

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


## Adding projects

### Manually

`:Project </path/to/project>`

### Auto

When opening a file in a new project, `vim-project` will automatically add it if its directory contains `.git, .svn, package.json, pom.xml, Gemfile`. You can adjust related options at [Config](#config)

### Projects cache

You can find and directly modify cached projects in these files in `~/.vim/vim-project-config/`

- Projects added are saved to `project.add.vim`
- Projects ignored to `project.ignore.vim`

## Workflow

- Add projects

    `:Project <path/to/project>` | Open a file in a project

- Open a project

    `:ProjectList` | `:ProjectOpen <name>`
    - Load session
    - Source project `init.vim`

- Quit the project

    `:ProjectQuit` | Open another project | Quit vim
    - Save session
    - Source project `quit.vim`

- Remove a project

    `:ProjectRemove <name>`

## Commands

| command                             | description                               |
|-------------------------------------|-------------------------------------------|
| Project `<path>[, option]`          | Add project                               |
| ProjectList                         | Show projects                             |
| ProjectOpen `<name>`                | Open a project by name                    |
| ProjectRemove `<name>`              | Remove a project by name                  |
| ProjectInfo                         | Show project info                         |
| ProjectQuit                         | Quit project                              |
| ProjectEntry                        | Open project entry directory or file      |
| ProjectConfig                       | Open project config directory             |
| ProjectAllConfig                    | Open all config directory                 |
| ProjectIgnore `<path>`              | Ignore project for auto detection         |

> You can try adjust `wildmenu`, `wildmode` for enhanced command-line completion

### :Project `<path>[, option]`

Example

```vim
Project '/path/to/demo', { 'entry': 'src', 'note': 'A demo' }
```

#### Path

If `path` is a relative path which doesn't start with `/`, `~` or `C:`, it'll try any of `g:vim_project_config.project_base` as relative base which defaults to `[~]`.

#### option

- `entry`: directory or file used as project entry
- `note`: text description shown on project list

## Config
There is only one config `g:vim_project_config`. Its default value is below. You can copy it as a starting point

```vim
let g:vim_project_config = {
      \'config_home': '~/.vim/vim-project-config',
      \'use_session': 0,
      \'check_branch_when_use_session': 0,
      \'open_entry_when_use_session': 0,
      \'auto_detect': 'always',
      \'auto_detect_file': '.git, .svn, package.json, pom.xml, Gemfile',
      \'auto_load_on_start': 0,
      \'project_base': ['~'],
      \'views': [],
      \'debug': 0,
      \}

let g:vim_project_config.file_open_types = {
      \'': 'edit',
      \'v': 'vsplit',
      \'s': 'split',
      \'t': 'tabedit',
      \}

let g:vim_project_config.project_list_mapping = {
      \'open_project': "\<cr>",
      \'close_list':   "\<esc>",
      \'clear_char':   ["\<bs>", "\<c-a>"],
      \'clear_word':   "\<c-w>",
      \'clear_all':    "\<c-u>",
      \'prev_item':    ["\<c-k>", "\<up>"],
      \'next_item':    ["\<c-j>", "\<down>"],
      \'first_item':   ["\<c-h>", "\<left>"],
      \'last_item':    ["\<c-l>", "\<right>"],
      \'prev_view':    "\<s-tab>",
      \'next_view':    "\<tab>",
      \}
```

| Option               | Description                                                                   | Type    |
|----------------------|-------------------------------------------------------------------------------|---------|
| config_home                 | The directory where all config files stay                                     | string  |
| use_session              | Use session                                                                | boolean |
| check_branch_when_use_session               | When session used, keep one for each branch                                | boolean |
| open_entry_when_use_session           | When session used, always open project entry                               | boolean |
| auto_detect          | Auto detect projects when opening a file. <br>Choose 'always', 'ask', or 'no' | string  |
| auto_detect_file     | File used to detect potential projects                                        | string  |
| auto_load_on_start   | Auto load a project if Vim starts from its directory                          | boolean |
| project_list_mapping | Mapping for project list prompt                                               | dict    |
| project_base         | The base directory for relative project path                                  | string  |
| views                | Define views by [[show-pattern, hide-pattern?], ...]                          | list    |
| debug                | Show debug messages                                                           | boolean |

### Config files structure

The config files for each project is located at `~/.vim/vim-project-config/<project-name>/`

```
~/.vim/vim-project-config/
                         | project.add.vim                        " Added projects
                         | project.igonre.vim                     " Ignored projects
                         | <project-name>/
                                         | init.vim               " Run after loading session
                                         | quit.vim               " Run after saving session
                                         | sessions/              " session for each branch
                                                   | master.vim
                                                   | branch-1.vim
                                                   | branch-2.vim
```

### Switch between files

You can define mappings to frequently changed files in `~/.vim/vim-project-config/<project-name>/init.vim`

For example, with below example, you can

- Switch to `autoload/project.vim` by `'a` and so on.

- Switch between `['autoload/project.vim', 'plugin/project.vim']` by `'l`

- Switch to file returned by user-defined function by `'c`

```vim
function! UpperStyle()
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
      \   'file': function('UpperStyle'),
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
      \'': 'edit',
      \'v': 'vsplit',
      \'s': 'split',
      \'t': 'tabedit',
      \}
```

### Session options

See `:h sessionoptions`

### Project views

On project list, you can switch between different views with <kbd>tab</kbd> and <kbd>s-tab</kbd>. You can define views by setting `g:vim_project_config.views` to `[[show_pattern, hide_patten], ...]` like below

```vim
let g:vim_project_config.views = [
      \['vim', 'plugin'],
      \['^vue'],
      \['^react'],
      \]
```

## Global variables

- `g:vim_project` *dict*. Current project info
- `$vim_project` *string*. Current project path
- `$vim_project_config` *string*. Current project config path

## Statusline

You can get current project info from `g:vim_project`. Try `echo g:vim_project` after opening a project

For example, define a function called `GetProjectInfo` and add `%{GetProjectInfo()}` to `statusline` to show current project name and branch.

```vim
function! GetProjectInfo()
  if exists('g:vim_project_loaded') && !empty(g:vim_project)
     let name = g:vim_project.name
     let branch = g:vim_project.branch
     return '['.name.','.branch.']'
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
