let s:last_modified = 0
let s:json_file_content = []

function! coverage#start() abort
  if exists('s:timer')
    call timer_stop(s:timer)
  endif
  let s:timer = timer_start(g:coverage_interval, 'coverage#process_buffer', {'repeat': -1})
endfunction

function! coverage#process_buffer(...) abort
  let l:bufnr = bufnr('')
  call coverage#utility#set_buffer(l:bufnr)
  let buffer_modified = coverage#utility#has_unsaved_changes()
  if !buffer_modified
    let file = expand('#' . l:bufnr . ':p')
    let modified_lines = coverage#get_coverage_lines(file)

    if g:coverage_show_covered
      call coverage#sign#update_signs(get(modified_lines, 'covered', []), 'covered')
    endif
    if g:coverage_show_uncovered
      call coverage#sign#update_signs(get(modified_lines, 'uncovered', []), 'uncovered')
    endif
  endif
endfunction

function! coverage#get_coverage_lines(file_name) abort
  let coverage_json_full_path = coverage#find_coverage_json()
  let coverage_go_full_path = coverage#find_coverage_go()

  if !filereadable(coverage_json_full_path) && !filereadable(coverage_go_full_path)
    return {}
  endif

  if filereadable(coverage_json_full_path)
      return coverage#process_json_coverage(a:file_name, coverage_json_full_path)
  elseif filereadable(coverage_go_full_path)
      return coverage#process_go_coverage(a:file_name, coverage_go_full_path)
  endif
endfunction

function! coverage#process_json_coverage(file_name, coverage_json_full_path)
  let lines = {}
  let lines_map = {}

  let current_last_modified = getftime(a:coverage_json_full_path)

  " Only read file when file has changed
  if current_last_modified > s:last_modified
    let s:json_file_content = readfile(a:coverage_json_full_path)
    let s:last_modified = current_last_modified
  endif

  try
    let json = json_decode(join(s:json_file_content))
    if has_key(json, a:file_name)
      let current_file_json = get(json, a:file_name)

      if has_key(current_file_json, 'l')
        let lines_map = get(current_file_json, 'l')
      else
        let lines_map = coverage#calc_line_from_statementsMap(current_file_json)
      endif
      let lines['covered'] = coverage#get_covered_lines(lines_map)
      let lines['uncovered'] = coverage#get_uncovered_lines(lines_map)
    endif
  catch
    echoerr v:exception
  endtry
  return lines
endfunction

function! coverage#process_go_coverage(file_name, coverage_go_full_path)
  let lines = {}
  let lines['covered'] = []
  let lines['uncovered'] = []

  let current_last_modified = getftime(a:coverage_go_full_path)
  let current_file = fnamemodify(a:file_name, ':t')

  " Only read file when file has changed
  if current_last_modified > s:last_modified
    let s:go_file_content = readfile(a:coverage_go_full_path)
    let s:last_modified = current_last_modified
  endif

  try
    for line in s:go_file_content
        if line =~# '[^\/]*' . current_file . ':'
            let a = split(line, ':')
            let b = split(a[1])

            let l:count = b[2]
            let l:stmt = b[1]

            let coverage = split(b[0], ',')
            let from = split(coverage[0], '\.')
            let to = split(coverage[1], '\.')

            let cov = (l:count > 0) ? 'covered' : 'uncovered'

            for l:l in range(from[0], to[0])
                if index(lines['covered'], l:l) == -1 && index(lines['uncovered'], l:l) == -1
                    let lines[cov] += [l:l]
                endif
            endfor
        endif
    endfor
  catch
    echoerr v:exception
  endtry
  return lines
endfunction

function! coverage#get_covered_lines(lines_map) abort
  let lines = filter(keys(a:lines_map), 'v:val != "0" && get(a:lines_map, v:val) != "0"')
  let lines = map(lines, 'str2nr(v:val)')
  return lines
endfunction

function! coverage#get_uncovered_lines(lines_map) abort
  let lines = filter(keys(a:lines_map), 'v:val != "0" && get(a:lines_map, v:val) == "0"')
  let lines = map(lines, 'str2nr(v:val)')
  return lines
endfunction

function! coverage#calc_line_from_statementsMap(json) abort
  let statementMap = get(a:json, 'statementMap')
  let statements = get(a:json, 's')
  let lines = {}
  for key in keys(statements)
    if !has_key(statementMap, key)
      continue
    endif
    let line = statementMap[key].start.line
    let line_count = statements[key]
    let pre_line_count = get(lines, line, 'undefined')
    if line_count == 0 && get(statementMap[key], 'skip')
      let line_count = 1
    endif
    if pre_line_count == 'undefined' || pre_line_count < line_count
      let lines[line] = line_count
    endif
  endfor
  return lines
endfunction

function! coverage#find_coverage_json() abort
  let cwd = fnamemodify('.', ':p')
  return cwd . g:coverage_json_report_path
endfunction

function! coverage#find_coverage_go() abort
  let cwd = fnamemodify('.', ':p')
  return cwd . g:coverage_go_report_path
endfunction
