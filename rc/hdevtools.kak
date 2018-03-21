
# hdevtools.kak
#
# This is based on lint.kak. See also clang.kak at the extra-dir.


# Do we need something like this?
# 
# declare-option -docstring %{shell command to which the path of a copy of the current buffer will be passed
# The output returned by this command is expected to comply with the following format:
#  {filename}:{line}:{column}: {kind}: {message}} \
#     str lintcmd

declare-option -hidden line-specs  hdevt_flags
declare-option -hidden range-specs hdevt_errors

# kak_buffile contains the full path
# kak_bufname contains the relative path

define-command hdevt -docstring 'Parse the current buffer with a hdevtools' %{
    %sh{
        dir=$(mktemp -d "${TMPDIR:-/tmp}"/kak-hdevt.XXXXXXXX)
        mkfifo "$dir"/fifo
        printf '%s\n' "evaluate-commands -no-hooks write $dir/buf"

        printf '%s\n' "evaluate-commands -draft %{
                  edit! -fifo $dir/fifo -debug *hdevt-output*
                  set-option buffer filetype make
                  set-option buffer make_current_error_line 0
                  hook -group fifo buffer BufCloseFifo .* %{
                      nop %sh{ rm -r '$dir' }
                      remove-hooks buffer fifo
                  }
              }"

        { # do the parsing in the background and when ready send to the session

        eval "hdevtools check " $kak_bufname  > "$dir"/stderr
        printf '%s\n' "evaluate-commands -client $kak_client echo 'hdevting done'" | kak -p "$kak_session"
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
        sed -e 's/X/ZYYYYYYYYZ/g' "$dir"/stderr | sed -e 's/\(^\/\)\(.*\):\([0-9]\+\):\([0-9]\+\):\(.*\):/XXXXXXXX\2X\3X\4X\5/g' | sed -e 's/:/\\:/g' | sed -e 's/ZYYYYYYYYZ/X/g' | awk -v file="$kak_buffile" -v stamp="$kak_timestamp" '
            BEGIN {
                RS="XXXXXXXX";
                FS="X";
            }
            /X[0-9]+X[0-9]+X error/ {
                flags = flags $2 "|{red}█:"
            }
            /X[0-9]+X[0-9]+X warning/ {
                flags = flags $2 "|{yellow}█:"
            }
            /X[0-9]+X[0-9]+X/ {
                errors = errors ":" $2 "." $3 "," $2 "." $3 "|" ;
                errs = $4;
                for (i=5; i<=NF; i++) errs = errs $i;
                # gsub("\n","  ", errs);
                gsub("\n","XXYXXYXX", errs);
                errors = errors errs;
            }
            END {
                flags = substr(flags, 1, length(flags)-1)
                gsub("~", "\\~", errors)
                # gsub("\n", "", errors)
                # gsub("\n","XXYXXYXX", errors);
                print "set-option \"buffer=" file "\" hdevt_flags %{" stamp ":" flags "}"
                # print "set-option \"buffer=" file "\" hdevt_flags %{" stamp flags "}"
                print "set-option \"buffer=" file "\" hdevt_errors %~" stamp errors "~"
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
    %sh{
        # Pick up the line on which the cursor is, and put row and column number
        # with a point in between.  Also decode the newlines back into the text.
        desc=$(printf '%s\n' "${kak_opt_hdevt_errors}" | sed -e 's/\([^\\]\):/\1\n/g' | tail -n +2 | sed -ne "/^${kak_cursor_line}\.[^|]\+|.*/ { s/^[^|]\+|//g; s/'/\\\\'/g; s/\\\\:/:/g; p; }"  | sed -e 's/XXYXXYXX/\n/g' )
        if [ -n "${desc}" ]; then
            printf '%s\n' "info -anchor ${kak_cursor_line}.${kak_cursor_column} '${desc}'"
        fi
    } }

define-command hdevt-enable -docstring "Activate automatic diagnostics of the code" %{
    add-highlighter window flag_lines default hdevt_flags
    #echo -debug "hdevt_flags: %opt{hdevt_flags}"
    #echo -debug "timestamp: %val{timestamp}"
    hook window -group hdevt-diagnostics NormalIdle .* %{ hdevt-show }
    hook window -group hdevt-diagnostics WinSetOption hdevt_flags=.* %{ info; hdevt-show }
}

define-command hdevt-disable -docstring "Disable automatic diagnostics of the code" %{
    remove-highlighter window/hlflags_hdevt_flags
    remove-hooks window hdevt-diagnostics
}

define-command hdevt-next-error -docstring "Jump to the next line that contains an error" %{
    update-option buffer hdevt_errors
    %sh{
        printf '%s\n' "$kak_opt_hdevt_errors" | sed -e 's/\([^\\]\):/\1\n/g' | tail -n +2 | {
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
                printf 'echo -markup "{Error}no hdevtools diagnostics"\n'
            fi
        }
    }}

define-command hdevt-previous-error -docstring "Jump to the previous line that contains an error" %{
    update-option buffer hdevt_errors
    %sh{
        printf '%s\n' "$kak_opt_hdevt_errors" | sed -e 's/\([^\\]\):/\1\n/g' | tail -n +2 | sort -t. -k1,1 -rn | {
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
                printf 'echo -markup "{Error}no hdevtools diagnostics"\n'
            fi
        }
    }}
