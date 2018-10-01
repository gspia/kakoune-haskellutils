
# hdevtools.kak
#
# This is based on lint.kak. See also clang.kak at the extra-dir.


# Do we need something like this? Note that the format is a bit different.
# 
# declare-option -docstring %{shell command to which the path of a copy of the current buffer will be passed
# The output returned by this command is expected to comply with the following format:
#  {filename}:{line}:{column}: {kind}: {message}} \
#     str lintcmd

declare-option -hidden line-specs  hdevt_flags
declare-option -hidden range-specs hdevt_errors
declare-option -hidden int hdevt_error_count
declare-option -hidden int hdevt_warning_count

# kak_buffile contains the full path
# kak_bufname contains the relative path

define-command hdevt -docstring 'Parse the current buffer with a hdevtools' %{
    evaluate-commands %sh{
        dir=$(mktemp -d "${TMPDIR:-/tmp}"/kak-hdevt.XXXXXXXX)
        mkfifo "$dir"/fifo
        printf '%s\n' "evaluate-commands -no-hooks write -sync $dir/buf"

        printf '%s\n' "evaluate-commands -draft %{
                  edit! -fifo $dir/fifo -debug *hdevt-output*
                  set-option buffer filetype make
                  set-option buffer make_current_error_line 0
                  hook -always -once buffer BufCloseFifo .* %{
                      nop %sh{ rm -r '$dir' }
                  }
              }"

        { # do the parsing in the background and when ready send to the session

        eval "hdevtools check " $kak_bufname  > "$dir"/stderr
        printf '%s\n' "evaluate-commands -client $kak_client echo 'hdevting done'" | kak -p "$kak_session"
        # Flags for the gutter:
        #   stamp line3|{red} line11|{yellow}
        # Contextual error messages:
        #   stamp 'l1.c1,l1.c1|err1' 'l2.c2,l2.c2|err2'
        #   
        # Thus, we take the first line of an error, encode the field sep's and escape the
        # :-char's on the error msg in the sed's.  We also add a RS-mark (X's) into
        # the beginning of error that works as a record separator.
        # Note, that we remove the newlines from the error messages and put markers there
        # so that we can put the newlines back later when showing the error message. 
        # This doesn't work if there is ZYYYYYYYYZ123 ZYYYYYYYYZ15ZYYYYYYYYZ
        # in the name of the file.
        # TODO, change it to something not so ugly.  Couldn't get the number of
        # backslashes correct which is why these codings are here.  It would be better to
        # use something like '/\n^\//' as a RS and FS=":" and remove those sed's.
        sed -e 's/X/ZYYYYYYYYZ/g' "$dir"/stderr | sed -e 's/\(^\/\)\(.*\):\([0-9]\+\):\([0-9]\+\):\(.*\):/XXXXXXXX\2X\3X\4X\5/g' | sed -e 's/:/\\:/g' | sed -e 's/ZYYYYYYYYZ/X/g' | awk -v file="$kak_buffile" -v stamp="$kak_timestamp" -v client="$kak_client" '
            BEGIN {
                RS="XXXXXXXX";
                FS="X";
                error_count = 0;
                warning_count = 0;
            }
            /X[0-9]+X[0-9]+X error/ {
                flags = flags " " $2 "|{red}█"
                error_count++;
            }
            /X[0-9]+X[0-9]+X warning/ {
                flags = flags " " $2 "|{yellow}█"
                warning_count++;
            }
            /X[0-9]+X[0-9]+X/ {
                error = $2 "." $3 "," $2 "." $3 "|" ;
                errs = $4;
                for (i=5; i<=NF; i++) errs = errs $i;
                # gsub("\n","  ", errs);
                gsub("\n","XXYXXYXX", errs);
                # error2 = error errs;
                error2 = error "error Some error";
                errors = errors " '\''" error2 "'\''"  
            }
            END {
                gsub("~", "\\~", errors)
                # gsub("\n", "", errors)
                # gsub("\n","XXYXXYXX", errors);
                print "set-option \"buffer=" file "\" hdevt_flags " stamp flags 
                print "set-option \"buffer=" file "\" hdevt_errors " stamp errors 
                print "set-option \"buffer=" file "\" hdevt_warning_count " warning_count
                print "set-option \"buffer=" file "\" hdevt_error_count " error_count
                print "evaluate-commands -client " client " hdevt-show-counters"
            }
        ' | kak -p "$kak_session"
        # cut -d: -f2- "$dir"/stderr | sed "s@^@$kak_bufname:@" > "$dir"/fifo

        # Replace the beginning with the bufname and make sure that
        # it is :-separated and that the original :'s are escaped... To do that
        # we replace :-char's with \X's in the lines that contain fname:row:col:...
        # 
        # Note that this takes the dir/stderr input just like the previous awk-script.
        sed -e 's/\(^\/\)\(.*\):\([0-9]\+\):\([0-9]\+\):\(.*\):/XXXXXXXX\2\\X\3\\X\4\\X\5/g' "$dir"/stderr | sed -e 's/:/\\:/g'  | sed -e "s@\(^XXXXXXXX\)\(.*\)\\\X\([0-9]\+\)\\\X\([0-9]\+\)\\\X\(.*\)@$kak_bufname:\3:\4:\5@" > "$dir"/fifo
        # The following doesn't try to escpage X's.
        # sed -e 's/\(^\/\)\(.*\):\([0-9]\+\):\([0-9]\+\):\(.*\):/XXXXXXXX\2X\3X\4X\5/g' "$dir"/stderr | sed -e 's/:/\\:/g'  | sed -e "s@\(^XXXXXXXX\)\(.*\)X\([0-9]\+\)X\([0-9]\+\)X\(.*\)@$kak_bufname:\3:\4:\5@" > "$dir"/fifo
        } >/dev/null 2>&1 </dev/null &
    }
}

# 
define-command -hidden hdevt-show %{
    update-option buffer hdevt_errors
    # echo -debug "hmm $kak_opt_hdevt_errors"
    evaluate-commands %sh{
        eval "set -- ${kak_opt_hdevt_errors}"
        shift

        s=""
        for i in "$@"; do
            s="${s}
${i}"
        done

        # printf '%s helloreX\\n' "${s}"
        printf %s\\n "${s}" | awk -v line="${kak_cursor_line}" \
                                  -v column="${kak_cursor_column}" \
           "/^${kak_cursor_line}\./"' {
               gsub(/"/, "\"\"")
               msg = substr($0, index($0, "|"))
               sub(/^[^ \t]+[ \t]+/, "", msg)
               gsub("XXYXXYXX","\n", msg)
               printf "info -anchor %d.%d \"%s\"\n", line, column, msg
           }'

        # Pick up the line on which the cursor is, and put row and column number
        # with a point in between.  Also decode the newlines back into the text.
        # desc=$(printf '%s\n' "${kak_opt_hdevt_errors}" | sed -e 's/\([^\\]\):/\1\n/g' | tail -n +2 | sed -ne "/^${kak_cursor_line}\.[^|]\+|.*/ { s/^[^|]\+|//g; s/'/\\\\'/g; s/\\\\:/:/g; p; }"  | sed -e 's/XXYXXYXX/\n/g' )
        #  if [ -n "${desc}" ]; then
        #     printf '%s\n' "info -anchor ${kak_cursor_line}.${kak_cursor_column} '${desc}'"
        # fi
    } }

define-command hdevt-enable -docstring "Activate automatic diagnostics of the code" %{
    add-highlighter window/hdevt flag-lines default hdevt_flags
    #echo -debug "hdevt_flags: %opt{hdevt_flags}"
    #echo -debug "timestamp: %val{timestamp}"
    hook window -group hdevt-diagnostics NormalIdle .* %{ hdevt-show }
    hook window -group hdevt-diagnostics WinSetOption hdevt_flags=.* %{ info; hdevt-show }
}

define-command -hidden hdevt-show-counters %{
    echo -markup hdevtool results:{red} %opt{hdevt_error_count} erros(s){yellow} %opt{hdevt_warning_count} warning(s)
}

define-command hdevt-disable -docstring "Disable automatic diagnostics of the code" %{
    remove-highlighter window/hlflags_hdevt_flags
    remove-hooks window hdevt-diagnostics
}

define-command hdevt-next-error -docstring "Jump to the next line that contains an error" %{
    update-option buffer hdevt_errors
    evaluate-commands %sh{
        eval "set -- ${kak_opt_hdevt_errors}"
        shift

        for i in "$@"; do
            candidate="${i%%|*}"
            if [ "${candidate%%.*}" -gt "${kak_cursor_line}" ]; then
                range="${candidate}"
                break
            fi
        done

        range="${range-${1%%|*}}"
        if [ -n "${range}" ]; then
            printf 'select %s\n' "${range}"
        else
            printf 'echo -markup "{Error}no hdevtools diagnostics"\n'
        fi
    }
}


define-command hdevt-previous-error \
        -docstring "Jump to the previous line that contains an error" %{
    update-option buffer hdevt_errors
    evaluate-commands %sh{
        eval "set -- ${kak_opt_hdevt_errors}"
        shift

        for i in "$@"; do
            candidate="${i%%|*}"

            if [ "${candidate%%.*}" -ge "${kak_cursor_line}" ]; then
                range="${last_candidate}"
                break
            fi

            last_candidate="${candidate}"
        done

        if [ $# -ge 1 ]; then
            shift $(($# - 1))
            range="${range:-${1%%|*}}"
            printf 'select %s\n' "${range}"
        else
            printf 'echo -markup "{Error}no hdevtools diagnostics"\n'
        fi
    }
}


define-command hdevt-findsymbol -params .. \
        -docstring "Either select the symbol-string or :hdevt-findsymbol symbol" %{
    evaluate-commands %sh{
    if [ $# -gt 0 ]; then
        symbols=$(printf %s | eval "hdevtools findsymbol $@ ")
    else 
        symbols=$(printf %s | eval "hdevtools findsymbol '${kak_selection}' ")
    fi
    menu=$(printf %s "${symbols#?}" |  awk -F'\n' '
        {
            for (i=1; i<=NF; i++)
                printf "%s", "%{"$i"} %{execute-keys i"$i".<esc>}"
        }
    ')
    if [ -n "${symbols}" ]; then
        printf 'try %%{ menu -auto-single %s }' "${menu}"
    else
        printf 'echo -markup "{Error}No symbols found."'
    fi
}}


