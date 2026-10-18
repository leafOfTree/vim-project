" Shared helpers used by the core and the feature modules

" Warn and return 0 when no project is open, otherwise return 1
function! project#util#RequireProject()
  if project#ProjectExist()
    return 1
  endif

  call project#Warn('Open a project first')
  return 0
endfunction

function! project#util#Match(string, pattern)
  return match(a:string, a:pattern) != -1
endfunction

" 'foo bar' -> 'foo.*bar', so words match in order anywhere in the text
function! project#util#GetRegexpFilter(input)
  return join(split(a:input, ' '), '.*')
endfunction

function! project#util#HasArgs(task)
  return has_key(a:task, 'args')
endfunction

" Return the first candidate that is executable, or the fallback
function! project#util#PickExecutable(candidates, fallback = '')
  for name in a:candidates
    if executable(name)
      return name
    endif
  endfor
  return a:fallback
endfunction

" Fuzzy filter and rank items by input, trying fields one by one.
"
" Each character of input may be separated by anything ('ab' matches 'a_b').
" An item takes the type of the first field it matches. Items are never
" modified; a new list of the matched items is returned.
"
" fields: list, in the order they are tried. Each field is either
"   - a string: the item key, also used as the type
"   - a dict: { 'type': label, 'key': item key } or
"             { 'type': label, 'Get': {item -> text} }
"   A missing key, or a Get returning v:null, skips that field.
"   For the first field, a match that is not an exact substring gets a
"   penalty of 10 on its index so exact matches rank first.
"
" opts (optional):
"   'priority': types, best first, used for sorting. Default: fields order
"   'prefer':   types. If any item matched one of them, only those are kept
"   'sort':     0 to keep the original order. Default: 1
"   'tiebreak': item key. Among equal type and index, the shorter wins
"
" The sort puts the best item last, as the list is shown bottom-up.
function! project#util#FuzzyScore(items, input, fields, opts = {})
  let regexp = join(split(a:input, '\zs'), '.*')
  let scored = []

  for item in a:items
    let field_idx = 0
    for field in a:fields
      let text = s:GetFieldText(item, field)
      if text is v:null
        let field_idx += 1
        continue
      endif

      let index = match(text, regexp)
      if index != -1
        " Prefer exact match. If not, add 10 to index
        if field_idx == 0 && len(a:input) > 1 && count(tolower(text), a:input) == 0
          let index += 10
        endif
        call add(scored, {
              \'item': item,
              \'type': s:GetFieldType(field),
              \'index': index,
              \})
        break
      endif
      let field_idx += 1
    endfor
  endfor

  let prefer = get(a:opts, 'prefer', [])
  if !empty(prefer)
    let preferred = filter(copy(scored), {_, val -> index(prefer, val.type) != -1})
    if !empty(preferred)
      let scored = preferred
    endif
  endif

  if get(a:opts, 'sort', 1)
    let priority = get(a:opts, 'priority', map(copy(a:fields), {_, val -> s:GetFieldType(val)}))
    let tiebreak = get(a:opts, 'tiebreak', '')
    call sort(scored, function('s:Compare', [priority, tiebreak]))
  endif

  return map(scored, {_, val -> val.item})
endfunction

function! s:GetFieldType(field)
  return type(a:field) == v:t_string ? a:field : a:field.type
endfunction

function! s:GetFieldText(item, field)
  if type(a:field) == v:t_string
    return has_key(a:item, a:field) ? a:item[a:field] : v:null
  endif

  if has_key(a:field, 'Get')
    return a:field.Get(a:item)
  endif
  return has_key(a:item, a:field.key) ? a:item[a:field.key] : v:null
endfunction

" Return > 0 when a1 is better than a2, so the best goes last
function! s:Compare(priority, tiebreak, a1, a2)
  if a:a1.type != a:a2.type
    let rank1 = index(a:priority, a:a1.type)
    let rank2 = index(a:priority, a:a2.type)
    return rank1 < rank2 ? 1 : -1
  endif

  if a:a1.index != a:a2.index
    return a:a2.index - a:a1.index
  endif

  if !empty(a:tiebreak)
    return len(a:a2.item[a:tiebreak]) - len(a:a1.item[a:tiebreak])
  endif
  return 0
endfunction
