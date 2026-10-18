" Tests for autoload/project/util.vim and the git lists using its filter.
runtime autoload/project/util.vim
runtime autoload/project/git_branch.vim
runtime autoload/project/git_tag.vim

function! s:Matches(texts, input)
  let pattern = project#util#GetRegexpFilter(a:input)
  return filter(copy(a:texts), {_, text -> project#util#Match(text, pattern)})
endfunction

function! Test_GetRegexpFilter_matches_words_in_order()
  let texts = ['fix the bug', 'bug fix', 'fixed a small bug']
  call assert_equal(['fix the bug', 'fixed a small bug'], s:Matches(texts, 'fix bug'))
endfunction

" Regression: '~' raised E33 and '.', '*', '[' were used as regexp
function! Test_GetRegexpFilter_matches_typed_chars_literally()
  let texts = ['a.b', 'axb', 'c[1]', 'star*', 'rx', 'x~y', 'back\slash']
  call assert_equal(['x~y'], s:Matches(texts, '~'))
  call assert_equal(['a.b'], s:Matches(texts, 'a.b'))
  call assert_equal(['c[1]'], s:Matches(texts, '[1'))
  call assert_equal(['star*'], s:Matches(texts, 'r*'))
  call assert_equal(['back\slash'], s:Matches(texts, 'k\s'))
  call assert_equal(['star*'], s:Matches(texts, 's *'))
endfunction

function! Test_FilterBranches_and_FilterTags_match_literally()
  let branches = [{'name': 'v1.0'}, {'name': 'v100'}, {'name': 'feat~x'}]
  let result = Helper_Call('autoload/project/git_branch.vim', 'FilterBranches', [branches, '1.0'])
  call assert_equal([{'name': 'v1.0'}], result)
  let result = Helper_Call('autoload/project/git_branch.vim', 'FilterBranches', [branches, '~'])
  call assert_equal([{'name': 'feat~x'}], result)

  let tags = [{'name': 'v1.0', 'message': 'a'}, {'name': 'v100', 'message': '[wip]'}]
  let result = Helper_Call('autoload/project/git_tag.vim', 'FilterTags', [tags, '[w'])
  call assert_equal([tags[1]], result)
  let result = Helper_Call('autoload/project/git_tag.vim', 'FilterTags', [tags, '~'])
  call assert_equal([], result)
endfunction
