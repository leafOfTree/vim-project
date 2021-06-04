# vim-project

<p align="center">
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/project-1.png" width="240" />
➡️
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/project-2.png" width="240" />
➡️
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/project-3.png" width="240" />
➡️
<img alt="screenshot" src="https://github.com/leafOfTree/leafOfTree.github.io/raw/master/project-4.png" width="240" />
</p>

A vim plugin to manage projects

**Features**

- Switch between projects
- Configs per project 
- Sessions per project and per branch

    To notice branch, it requires both vim feature `job` and shell command `tail` 

## Usage

- `:ProjectAdd </path/to/project>`
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

`:ProjectAdd </path/to/project>`

### Auto

When opening a file in a new project, `vim-project` will automatically add it if its directory contains `.git, .svn, package.json, pom.xml, Gemfile`. You can adjust related options at [Config](#config)

### Projects cache

You can find and directly modify recorded projects in these files in `~/.vim/vim-project-config/`

- Projects added are saved to `project.add.vim`
- Projects ignored to `project.ignore.vim`

## Workflow

- Add projects

    `:ProjectAdd <path/to/project>` | Open a file in a project

- Open a project

    `:ProjectList` | `:ProjectOpen <name>`
    - Load session
    - Source project `init.vim`

- Edit files

- Exit the project

    `:ProjectExit` | Open another project | Quit vim
    - Save session
    - Source project `quit.vim`

## Commands

| command                             | description                               |
|-------------------------------------|-------------------------------------------|
| ProjectBase `<base>`                | Set base directory for following projects |
| ProjectAdd `<path>[, option]`       | Add project                               |
| ProjectList                         | Show projects                             |
| ProjectOpen `<name>`                | Open a project by name                    |
| ProjectInfo                         | Show project info                         |
| ProjectExit                         | Exit project                              |
| ProjectEntry                        | Open project entry directory              |
| ProjectConfig                       | Open project config directory             |
| ProjectTotalConfig                  | Open total config directory               |
| ProjectIgnore `<path>`              | Ignore project for auto detection         |

#### `:ProjectAdd` option

```vim
ProjectAdd '/path/to/demo', { 'entry': 'src', 'note': 'A demo' }
```

- `entry`: directory or file used as project entry
- `note`: text description shown on project list

## Config
There is only one config `g:vim_project_config`. Its default value is below. You can copy it as a starting point

```vim
let g:vim_project_config = {
      \'config_path': '~/.vim',
      \'session': 0,
      \'branch': 0,
      \'entry': 0,
      \'auto_detect': 'always',
      \'auto_detect_file': '.git, .svn, package.json',
      \'auto_load_on_start': 0,
      \'views': [],
      \'debug': 1,
      \}

let g:vim_project_config.prompt_mapping = {
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
| config_path          | The config directory                                                          | string  |
| session              | Enable session                                                                | boolean |
| branch               | When session enabled, keep one for each branch                                | boolean |
| entry                | When session enabled, always open project entry                               | boolean |
| auto_detect          | Auto detect projects when opening a file. <br>Choose 'always', 'ask', or 'no' | string  |
| auto_detect_file     | File used to detect potential projects                                        | string  |
| auto_load_on_start   | Auto load a project if Vim starts from its directory                          | boolean |
| prompt_mapping       | Mapping for prompt                                                            | dict    |
| views                | Define views by [[show-pattern, hide-pattern?], ...]                          | list    |
| debug                | Show debug messages                                                           | boolean |

### Config files structure

The config files for each project is located at `~/.vim/vim-project-config/<project-name>/`

```
~/.vim/vim-project-config/
                 | project.add.vim           " Added projects
                 | project.igonre.vim        " Ignored projects
                 | <project-name>/
                                 | init.vim  " Run after loading session
                                 | quit.vim  " Run after saving session
                                 | sessions/ " session for each branch
                                           | master.vim
                                           | branch-1.vim
                                           | branch-2.vim
```

### Session options

See `:h sessionoptions`. It's recommended to `set sessionoptions-=options` to avoid potential bugs

### Project views

On project list, you can switch between different views with <kbd>tab</kbd> and <kbd>s-tab</kbd>. You can define views by setting `g:vim_project_config.views` to `[[show_pattern, hide_patten], ...]` like below.

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
  if exists('g:vim_project_loaded')
    let name = get(g:vim_project,'name','')
    let branch = get(g:vim_project,'branch','')
    return empty(name) ? '' : '['.name.','.branch.']'
  endif
endfunction

set statusline=%<%t%m\ %y\ %=%{GetProjectInfo()}
```

## Credits

Thanks to timsofteng for the great idea. It all started with that

[1]: https://github.com/VundleVim/Vundle.vim
[2]: https://github.com/tpope/vim-pathogen
[3]: https://github.com/junegunn/vim-plug
