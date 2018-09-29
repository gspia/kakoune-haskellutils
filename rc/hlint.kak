
# hlint.kak
#
# This is based on hdevtools.kak (which is based on lint.kak).
# See also clang.kak at the extra-dir.


# Do we need something like this?
# 
# declare-option -docstring %{shell command to which the path of a copy of the current buffer will be passed
# The output returned by this command is expected to comply with the following format:
#  {filename}:{line}:{column}: {kind}: {message}} \
#     str lintcmd

declare-option -hidden line-specs  hlint_flags
declare-option -hidden range-specs hlint_errors
declare-option -hidden int hlint_error_count
declare-option -hidden int hlint_warning_count

# kak_buffile contains the full path
# kak_bufname contains the relative path

define-command hlint -docstring 'Parse the current buffer with a hlint' %{
    evaluate-commands %sh{
        dir=$(mktemp -d "${TMPDIR:-/tmp}"/kak-hlint.XXXXXXXX)
        mkfifo "$dir"/fifo
        printf '%s\n' "evaluate-commands -no-hooks write -sync $dir/buf"

        printf '%s\n' "evaluate-commands -draft %{
                  edit! -fifo $dir/fifo -debug *hlint-output*
                  set-option buffer filetype make
                  set-option buffer make_current_error_line 0
                  hook -always -once buffer BufCloseFifo .* %{
                      nop %sh{ rm -r '$dir' }
                  }
              }"
                  # hook -group fifo buffer BufCloseFifo .* percent curlyB
                      # remove-hooks buffer fifo
             
        { # do the parsing in the background and when ready send to the session

        # Remove the two last lines ("3 hints" or "No hints" at the end).
        eval "hlint " $kak_bufname | head -n -2  > "$dir"/stderr
        printf '%s\n' "evaluate-commands -client $kak_client echo 'hlinting done'" | kak -p "$kak_session"
        # Flags for the gutter:
        #   line3|{red}:line11|{yellow}
        # Contextual error messages:
        #   l1,c1,err1
        #   ln,cn,err2
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
        sed -e 's/X/ZYYYYYYYYZ/g' "$dir"/stderr | sed -e 's/\(^[\/0-9a-zA-Z]\)\(.*\):\([0-9]\+\):\([0-9]\+\):\(.*\):/XXXXXXXX\1\2X\3X\4X\5/g' | sed -e 's/:/\\:/g' | sed -e 's/ZYYYYYYYYZ/X/g' | awk -v file="$kak_buffile" -v stamp="$kak_timestamp" -v client="$kak_client" '
            BEGIN {
                RS="XXXXXXXX";
                FS="X";
                error_count = 0;
                warning_count = 0;
            }
            /X[0-9]+X[0-9]+X [Ee]rror/ {
                flags = flags " " $2 "|{red}█:";
                error_count++;
            }
            /X[0-9]+X[0-9]+X Warning/ {
                flags = flags " " $2 "|{yellow}█:";
                warning_count++;
            }
            /X[0-9]+X[0-9]+X Suggestion/ {
                flags = flags $2 "|{green}█:";
            }
            /X[0-9]+X[0-9]+X/ {
                errors = errors ":" $2 "." $3 "," $2 "." $3 "|" ;
                # error = $2 "." $3 "," $2 "." $3 "|" ;
                errs = $4;
                for (i=5; i<=NF; i++) errs = errs $i;
                # gsub("\n","  ", errs);
                gsub("\n","XXYXXYXX", errs);
                # errors = errors errs;
                error2 = error errs;
                errors = errors " '\''" error2 "'\''"  
            }
            END {
                flags = substr(flags, 1, length(flags)-1)
                gsub("~", "\\~", errors)
                # gsub("\n", "", errors)
                # gsub("\n","XXYXXYXX", errors);
                # print "set-option \"buffer=" file "\" hlint_flags " stamp ":" flags 
                # print "set-option \"buffer=" file "\" hlint_flags " stamp flags 
                # print "set-option \"buffer=" file "\" hlint_flags %{" stamp ":" flags "}"
                # print "set-option \"buffer=" file "\" hlint_flags %{" stamp flags "}"
                print "set-option \"buffer=" file "\" hlint_errors %~" stamp errors "~"
                # print "set-option \"buffer=" file "\" hlint_errors " stamp errors 
                # print "set-option \"buffer=" file "\" hlint_warning_count " warning_count
                # print "set-option \"buffer=" file "\" hlint_error_count " error_count
                print "evaluate-commands -client " client " hlint-show-counters"
            }
        ' "$dir"/stderr | kak -p "$kak_session"
        # cut -d: -f2- "$dir"/stderr | sed "s@^@$kak_bufname:@" > "$dir"/fifo
        cat "$dir"/stderr > /tmp/koe.txt

        # Replace the beginning with the bufname and make sure that
        # it is :-separated and that the original :'s are escaped... To do that
        # we replace :-char's with \X's in the lines that contain fname:row:col:...
        # 
        # Note that this takes the dir/stderr input just like the previous awk-script.
        sed -e 's/\(^[\/0-9a-zA-Z]\)\(.*\):\([0-9]\+\):\([0-9]\+\):\(.*\):/XXXXXXXX\1\2\\X\3\\X\4\\X\5/g' "$dir"/stderr | sed -e 's/:/\\:/g'  | sed -e "s@\(^XXXXXXXX\)\(.*\)\\\X\([0-9]\+\)\\\X\([0-9]\+\)\\\X\(.*\)@$kak_bufname:\3:\4:\5@" > "$dir"/fifo
        sed -e 's/\(^[\/0-9a-zA-Z]\)\(.*\):\([0-9]\+\):\([0-9]\+\):\(.*\):/XXXXXXXX\1\2\\X\3\\X\4\\X\5/g' "$dir"/stderr | sed -e 's/:/\\:/g'  | sed -e "s@\(^XXXXXXXX\)\(.*\)\\\X\([0-9]\+\)\\\X\([0-9]\+\)\\\X\(.*\)@$kak_bufname:\3:\4:\5@" > /tmp/koe2.txt
        # The following doesn't try to escpage X's.
        # sed -e 's/\(^\/\)\(.*\):\([0-9]\+\):\([0-9]\+\):\(.*\):/XXXXXXXX\2X\3X\4X\5/g' "$dir"/stderr | sed -e 's/:/\\:/g'  | sed -e "s@\(^XXXXXXXX\)\(.*\)X\([0-9]\+\)X\([0-9]\+\)X\(.*\)@$kak_bufname:\3:\4:\5@" > "$dir"/fifo
        cat "$dir"/stderr > /tmp/koe3.txt
        # cat "$dir"/fifo > /tmp/koe3.txt
        } >/dev/null 2>&1 </dev/null &
    }
}

# 
define-command -hidden hlint-show %{
    update-option buffer hlint_errors
    # echo -debug "option value %opt{ hlint_errors }"
    # echo -debug "option value %opt{ kak_opt_hlint_errors }"
    # echo -debug "hmm2 ${kak_opt_hlint_errors}"
    evaluate-commands %sh{
        eval "set -- ${kak_opt_hlint_errors}"
        shift 
        # Pick up the line on which the cursor is, and put row and column number
        # with a point in between.  Also decode the newlines back into the text.
        desc=$(printf '%s\n' "${kak_opt_hlint_errors}" | sed -e 's/\([^\\]\):/\1\n/g' | tail -n +2 | sed -ne "/^${kak_cursor_line}\.[^|]\+|.*/ { s/^[^|]\+|//g; s/'/\\\\'/g; s/\\\\:/:/g; p; }"  | sed -e 's/XXYXXYXX/\n/g' )
        if [ -n "${desc}" ]; then
            printf '%s\n' "info -anchor ${kak_cursor_line}.${kak_cursor_column} '${desc}'"
        fi
        printf '%s\n'  "echo -debug \nhmm\n ${kak_opt_hlint_errors}  "
    }
}

define-command -hidden hlint-show-counters %{
    echo -markup hlinting results:{red} %opt{hlint_error_count} erros(s){yellow} %opt{hlint_warning_count} warning(s)
}



define-command hlint-enable -docstring "Activate automatic diagnostics of the code" %{
    add-highlighter window/hlint flag-lines default hlint_flags
    #echo -debug "hlint_flags: %opt{hlint_flags}"
    #echo -debug "timestamp: %val{timestamp}"
    hook window -group hlint-diagnostics NormalIdle .* %{ hlint-show }
    hook window -group hlint-diagnostics WinSetOption hlint_flags=.* %{ info; hlint-show }
}

define-command hlint-disable -docstring "Disable automatic diagnostics of the code" %{
    remove-highlighter window/hlint
    remove-hooks window hlint-diagnostics
}
    # remove-highlighter window/hlflags_hlint_flags

define-command hlint-next-error -docstring "Jump to the next line that contains an error, warning or suggestion" %{
    update-option buffer hlint_errors
    evaluate-commands %sh{
        printf '%s\n' "$kak_opt_hlint_errors" | sed -e 's/\([^\\]\):/\1\n/g' | tail -n +2 | {
            # IFS = internal field separator
            # read -r = read one line from stdin and backslashes don't escape ;-char,
            # and put the first one into candidate and rest contains, hmm, the rest..
            while IFS='|' read -r candidate rest
            do
                # substitute the first_range, if it is set, otherwise substitute candidate.
                first_range=${first_range-$candidate}
                if [ "${candidate%%.*}" -gt "$kak_cursor_line" ]; then
                    range=$candidate
                    break
                fi
            done
            range=${range-$first_range}
            if [ -n "$range" ]; then
                printf '%s\n' "select $range"
            else
                printf 'echo -markup "{Error}no hlint diagnostics"\n'
            fi
        }
    }}

define-command hlint-previous-error -docstring "Jump to the previous line that contains an error, warning or suggestion" %{
    update-option buffer hlint_errors
    evaluate-commands %sh{
        printf '%s\n' "$kak_opt_hlint_errors" | sed -e 's/\([^\\]\):/\1\n/g' | tail -n +2 | sort -t. -k1,1 -rn | {
            while IFS='|' read -r candidate rest
            do
                first_range=${first_range-$candidate}
                if [ "${candidate%%.*}" -lt "$kak_cursor_line" ]; then
                    range=$candidate
                    break
                fi
            done
            range=${range-$first_range}
            if [ -n "$range" ]; then
                printf '%s\n' "select $range"
            else
                printf 'echo -markup "{Error}no hlint diagnostics"\n'
            fi
        }
    }}
