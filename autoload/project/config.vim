" Configuration: the defaults, the global g:vim_project_config and the
" project local g:vim_project_local_config (set by a project's init.vim).
"
" project#config#Init()      load the global config over the defaults
" project#config#ReadLocal() extend it with the local config of a project
" project#config#Adjust()    derive the search and find include/exclude
" project#config#Get(key)    read one option
" project#config#All()       all options, as currently in effect

let s:config = {}

let s:default = {
      \'config_home':                   '~/.vim/vim-project-config',
      \'project_base':                  ['~'],
      \'use_session':                   0,
      \'use_viminfo':                   0,
      \'open_root_when_use_session':    0,
      \'check_branch_when_use_session': 0,
      \'project_root':                 './',
      \'auto_load_on_start':            0,
      \'include':                       [],
      \'search_include':                [],
      \'find_in_files_include':         [],
      \'exclude':                       ['.git', 'node_modules', '.DS_Store', '.github', '.next'],
      \'search_exclude':                [],
      \'find_in_files_exclude':         [],
      \'auto_detect':                   'no',
      \'auto_detect_file':              ['.git', '.svn'],
      \'ask_create_directory':          'no',
      \'project_views':                 [],
      \'file_mappings':                 {},
      \'file_mappings_prefix':          "'",
      \'tasks':                         [],
      \'new_tasks':                     [
        \{ 'name': 'git', 'cmd': 'git clone', 'args': 'url' },
        \{ 'name': 'empty', 'cmd': 'mkdir' },
      \],
      \'new_project_base':              '',
      \'new_tasks_post_cmd':            '',
      \'commit_message':                '',
      \'find_replace_separator':        ' => ',
      \'debug':                         0,
      \}

let s:default.list_mappings = {
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
let s:default.list_mappings_projects = {
      \'prev_view':            "\<s-tab>",
      \'next_view':            "\<tab>",
      \}
let s:default.list_mappings_search_files = {
      \'open_split':           "\<c-s>",
      \'open_vsplit':          "\<c-v>",
      \'open_tabedit':         "\<c-t>",
      \}
let s:default.list_mappings_find_in_files = {
      \'open_split':           "\<c-s>",
      \'open_vsplit':          "\<c-v>",
      \'open_tabedit':         "\<c-t>",
      \'replace_prompt':       "\<c-r>",
      \'replace_dismiss_item': "\<c-d>",
      \'replace_confirm':      "\<c-y>",
      \}
let s:default.list_mappings_run_tasks = {
      \'run_task':              "\<cr>",
      \'stop_task':             "\<c-q>",
      \'open_task_terminal':    "\<c-o>",
      \}
let s:default.list_mappings_git = {
      \'checkout_revision':     "\<c-o>",
      \}
let s:default.list_mappings_git_branch = {
      \'merge_branch':     "\<c-o>",
      \}
let s:default.git_diff_mappings = {
      \'jump_to_source': "\<cr>",
      \}
let s:default.git_changes_mappings = {
      \'open_file': "\<cr>",
      \}
let s:default.git_local_changes_mappings = {
      \'open_changelist_or_file': "\<cr>",
      \'delete_changelist': 'd',
      \'rename_changelist': 'r',
      \'new_changelist': 'a',
      \'rollback_file': 'R',
      \'commit': 'c',
      \'move_to_changelist': 'm',
      \'pull': 'u',
      \'push': 'p',
      \'pull_and_push': 'P',
      \'force_push': '<NOP>',
      \'shelf': 's',
      \'unshelf': 'S',
      \}
let s:default.file_open_types = {
      \'':  'edit',
      \'s': 'split',
      \'v': 'vsplit',
      \'t': 'tabedit',
      \}

" Dict options whose keys are merged with the defaults instead of replaced
let s:merge_keys = [
      \'file_open_types',
      \'list_mappings',
      \'list_mappings_projects',
      \'list_mappings_search_files',
      \'list_mappings_find_in_files',
      \'list_mappings_run_tasks',
      \'list_mappings_git',
      \'list_mappings_git_branch',
      \'git_diff_mappings',
      \'git_changes_mappings',
      \'git_local_changes_mappings',
      \]

" Options a project's init.vim may set. Lists and dicts extend the global
" value, others override it
let s:local_config_keys = [
      \'include',
      \'search_include',
      \'find_in_files_include',
      \'exclude',
      \'search_exclude',
      \'find_in_files_exclude',
      \'project_root',
      \'file_mappings',
      \'tasks',
      \'use_session',
      \'use_viminfo',
      \'open_root_when_use_session',
      \'check_branch_when_use_session',
      \'commit_message',
      \]

function! project#config#Init()
  let user = exists('g:vim_project_config') ? g:vim_project_config : {}
  let s:config = deepcopy(s:MergeUserConfigIntoDefault(user, s:default))
  let s:config.project_base = s:RemoveListTrailingSlash(s:config.project_base)
endfunction

function! project#config#Get(key)
  return s:config[a:key]
endfunction

function! project#config#All()
  return s:config
endfunction

" Default keys are kept, user keys override them. Unknown keys are dropped
function! s:MergeUserConfigIntoDefault(user, default)
  let result = copy(a:default)

  for key in keys(a:default)
    if !has_key(a:user, key)
      continue
    endif

    if index(s:merge_keys, key) != -1
      let result[key] = s:MergeUserConfigIntoDefault(a:user[key], a:default[key])
    else
      let result[key] = a:user[key]
    endif
  endfor

  return result
endfunction

function! project#config#ResetLocal()
  let g:vim_project_local_config = {}
endfunction

function! project#config#ReadLocal()
  let local_config = exists('g:vim_project_local_config') ? g:vim_project_local_config : {}
  if empty(local_config)
    return
  endif

  for key in s:local_config_keys
    if has_key(local_config, key)
      let key_type = type(local_config[key])
      if key_type == v:t_list || key_type == v:t_dict
        let s:config[key] = extend(copy(s:config[key]), local_config[key])
      else
        let s:config[key] = local_config[key]
      endif
    endif
  endfor
endfunction

function! project#config#Adjust()
  call s:ExtendUniqueItems(s:config.search_include, s:config.include)
  call s:ExtendUniqueItems(s:config.find_in_files_include, s:config.include)
  call s:ExtendUniqueItems(s:config.search_exclude, s:config.exclude)
  call s:ExtendUniqueItems(s:config.find_in_files_exclude, s:config.exclude)

  let s:config.search_include = s:AdjustIncludeExcludePath(s:config.search_include, ['.'])
  let s:config.find_in_files_include =
        \s:AdjustIncludeExcludePath(s:config.find_in_files_include, ['.'])

  let s:config.search_exclude = s:AdjustIncludeExcludePath(s:config.search_exclude, [])
  let s:config.find_in_files_exclude =
        \s:AdjustIncludeExcludePath(s:config.find_in_files_exclude, [])
endfunction

function! s:ExtendUniqueItems(list1, list2)
  for item in a:list2
    if count(a:list1, item) == 0
      call add(a:list1, item)
    endif
  endfor
endfunction

function! s:AdjustIncludeExcludePath(paths, default)
  let paths = a:paths
  if empty(paths)
    let paths = a:default
  endif
  call s:RemoveListTrailingSlash(paths)
  return paths
endfunction

function! s:RemoveListTrailingSlash(list)
  call map(a:list, {_, val -> substitute(val, '[\/\\]$', '', '')})
  return a:list
endfunction
