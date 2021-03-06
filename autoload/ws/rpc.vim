let s:wf = fnamemodify(expand('<sfile>'), ':h:h:h') . '/main.py'
let s:logfile = fnamemodify(expand('<sfile>'), ':h:h:h') . '/wfrpc.log'


function! ws#rpc#register_notify_callback(name, callback) abort
    if !exists('s:notify_map')
        let s:notify_map = {}
    endif
    let s:notify_map[a:name] = a:callback
endfunction

function! ws#rpc#start(argv) abort
    if exists('s:job_id') && s:job_id
        call ws#rpc#stop()
    endif
    let s:next_request_id = 1
    let s:job_map = {}
    let s:buffer = ''

    let s:job_id = async#job#start(a:argv, {
        \ 'on_stdout': function('s:on_stdout'),
        \ 'on_stderr': function('s:on_stderr'),
        \ 'on_exit': function('s:on_exit'),
    \ })
    if !s:job_id
        echoerr 'job failed to start'
        return 0
    endif

    echom printf('job started: %d', s:job_id)
    return s:job_id
endfunction

function! ws#rpc#stop() abort
    if exists('s:job_id') && s:job_id
        call async#job#stop(s:job_id)
        echom printf('stop %d', s:job_id)
    end
    let s:job_id=0
    let s:next_request_id = 0
    let s:job_map = {}
    let s:buffer = ''
endfunction

function! s:get_or_create_job() abort
    if exists('s:job_id') && s:job_id
        return s:job_id
    endif

    let l:argv = [g:python3_host_prog, '-u', s:wf, '--rpc', '--debug', '--logfile', s:logfile]
    return ws#rpc#start(l:argv)
endfunction

function! s:on_stdout(job_id, data, event_type) abort
    let s:buffer = s:buffer . join(a:data, "\n")

    while len(s:buffer)
        " find HTTP header
        let m = matchstrpos(s:buffer, '^Content-Length: *\zs\d\+', 0)
        if m[1] == -1
            echom printf('not match: %s', s:buffer)
            break
        endif
        "echom printf('match: %s %d %d', m[0], m[1], m[2])

        " Content-Length: 40
        let l:content_length = str2nr(m[0])
        let l:body_pos = m[2] + 4
        let l:consume = l:body_pos + l:content_length
        "echom printf('%d + %d/%d', l:content_length, l:body_pos, len(s:buffer))

        let l:body = s:buffer[l:body_pos : l:body_pos + l:content_length-1]
        let s:buffer = s:buffer[l:consume :]

        call s:on_body(l:body)
    endwhile
endfunction

function! s:on_stderr(job_id, data, event_type) abort
    echom printf('%d ##> %s: %s', a:job_id, a:event_type, join(a:data, "\n"))
endfunction

function! s:on_exit(job_id, data, event_type) abort
    if a:job_id == s:job_id
        echom printf('%d exit', a:job_id)
        let s:job_id=0
    else
        echoerr printf('unknown %d exit', a:job_id)
    endif
endfunction

function! s:on_body(body) abort
    let l:parsed = json_decode(a:body)
    if l:parsed['jsonrpc'] != '2.0'
        echoerr printf("%s is not json-rpc", a:body)
        return
    endif

    if has_key(l:parsed, 'id')
        " request or response
        if has_key(l:parsed, 'method')
            call ws#logger#log(g:WS_SERVER_REQUEST, parsed)
        else
            " response
            if has_key(l:parsed, 'result')
                call ws#logger#log(g:WS_SERVER_RESPONSE, parsed)

                let Callback = s:job_map[parsed.id]
                call Callback(l:parsed.result)
            elseif has_key(l:parsed, 'error')
                call ws#logger#log(g:WS_SERVER_ERROR, parsed)

            else
                call ws#logger#log(g:WS_SERVER_ERROR, parsed)
            endif
        endif
    else
        if has_key(l:parsed, 'method')
            call ws#logger#log(g:WS_SERVER_NOTIFY, parsed)

            if exists('s:notify_map') && has_key(s:notify_map, l:parsed.method)
                let Callback = s:notify_map[l:parsed.method]
                call Callback(l:parsed.params)
            else
                echoerr printf("no notify callback for %s", l.parsed.method)
            endif
        else
            call ws#logger#log(g:WS_SERVER_ERROR, parsed)
        endif
    endif
endfunction

function! ws#rpc#request(callback, method, ...) abort
    let l:job_id = s:get_or_create_job()

    let l:request_id = s:next_request_id
    let s:next_request_id = s:next_request_id + 1
    let l:request = {
        \ 'jsonrpc': '2.0',
        \ 'method': a:method,
        \ 'id': l:request_id,
        \ 'params': a:000,
        \ }

    let l:data = json_encode(l:request)
    let s:job_map[l:request_id] = a:callback
    call async#job#send(l:job_id, printf("Content-Length: %d\r\n\r\n%s", len(l:data), l:data))

    call ws#logger#log(g:WS_CLIENT_REQUEST, l:request)
endfunction

function! ws#rpc#notify(method, ...) abort
    let l:job_id = s:get_or_create_job()

    let l:notify = {
        \ 'jsonrpc': '2.0',
        \ 'method': a:method,
        \ 'params': a:000,
        \ }
    let l:data = json_encode(l:notify)
    call async#job#send(l:job_id, printf("Content-Length: %d\r\n\r\n%s", len(l:data), l:data))

    call ws#logger#log(g:WS_CLIENT_NOTIFY, l:notify)
endfunction

