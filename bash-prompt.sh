#!/bin/bash

is_git_prompt_useful_here () {
	git rev-parse HEAD &> /dev/null || return 1

	return 0
}

parse_git_branch () {
	git branch | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/'
}

parse_git_ahead_behind () {
	local curr_branch
	local curr_remote
	local curr_merge_branch
	local count
	local ahead
	local behind
	local ab

	curr_branch=$(git rev-parse --abbrev-ref HEAD)
	curr_remote=$(git config branch.${curr_branch}.remote)

	# If the branch is local only, it won't have a remote
	[[ "$?" -gt 0 ]] && return 1

	curr_merge_branch=$(git config branch.${curr_branch}.merge | cut -d / -f 3)
	count=$(git rev-list --left-right --count ${curr_branch}...${curr_remote}/${curr_merge_branch} 2> /dev/null)

	# Might be the first commit which is not pushed yet
	[[ "$?" -gt 0 ]] && return 1

	ahead=$(printf "${count}" | cut -f1)
	behind=$(printf "${count}" | cut -f2)

	ab=''
	[[ "$ahead" -gt 0 ]] && ab+="↑${ahead}"

	if [[ "$behind" -gt 0 ]]; then
		[[ -n "$ab" ]] && ab+=" ↓${behind}" || ab+="↓${behind}"
	fi

	[[ -n "$ab" ]] && printf "${ab}" || printf ''
}

parse_git_last_fetch () {
	local f
	local now
	local last_fetch

	f=$(git rev-parse --show-toplevel)
	now=$(date +%s)
	last_fetch=$(stat -f%m ${f}/.git/FETCH_HEAD 2> /dev/null || printf '')

	[[ -n "$last_fetch" ]] && [[ $(( now > (last_fetch + 15*60) )) -eq 1 ]] && printf '☇' || printf ''
}

parse_git_status () {
	local bits
	local dirty
	local deleted
	local untracked
	local newfile
	local ahead
	local renamed

	git status --porcelain | (
		unset dirty deleted untracked newfile ahead renamed
		while read line ; do
			case "$line" in
				'M'*)	dirty='m' ;;
				'UU'*)	dirty='u' ;;
				'D'*)	deleted='d' ;;
				'??'*)	untracked='t' ;;
				'A'*)	newfile='n' ;;
				'C'*)	ahead='a' ;;
				'R'*)	renamed='r' ;;
			esac
		done

		bits="$dirty$deleted$untracked$newfile$ahead$renamed"
		[[ -n "$bits" ]] && printf "${bits}" || printf ''
	)
}

gen_git_status () {
	local ahead_behind
	local fetch
	local status

	ahead_behind=$(parse_git_ahead_behind)
	fetch=$(parse_git_last_fetch)
	status=$(parse_git_status)

	[[ -n "$ahead_behind" ]] && [[ -n "$status" ]] && status+=" ${ahead_behind}" || status+="${ahead_behind}"
	[[ -n "$fetch" ]] && [[ -n "$status" ]] && status+=" ${fetch}" || status+="${fetch}"

	printf "${status}"
}

gen_ps1 () {
	# This needs to be the first command otherwise it will not have correct exit code
	local ec="$?"

	local red
	local green
	local cyan
	local grey
	local nocol
	local prompt
	local branch
	local status
	local git_prompt
	local venv
	local root
	local top
	local bottom

	PS1=''
	red='\[\e[0;31m\]'
	green='\[\e[0;32m\]'
	cyan='\[\e[0;96m\]'
	grey='\[\e[0;90m\]'
	nocol='\[\e[0m\]'

	# Indicate if previous command succeeded or not
	prompt=''
	if [[ "$ec" -eq 0 ]]; then
		prompt="${grey}⑉"
	else
		prompt="${red}⑉"
	fi

	# If inside git managed directory show git information
	git_prompt=''
	branch=''
	status=''

	is_git_prompt_useful_here
	if [[ $? -eq 0 ]]; then
		branch=$(parse_git_branch)
		status=$(gen_git_status)

		git_prompt=" ${grey}{ ${branch} }${nocol}"
		[[ -n "$status" ]] && git_prompt+=" ${grey}{ ${status} }${nocol}"
	fi

	# If venv is active show it
	venv="${VIRTUAL_ENV}${CONDA_PREFIX}"
	venv=$([[ -n "$venv" ]] && printf " ${grey}{ ${cyan}${venv##*/} ${grey}}${nocol}" || printf '')

	# Display the username in red if running as root
	root=''
	if [[ "$USER" == "root" ]]; then
		root=" ${grey}{ ${red}root ${grey}}"
	fi

	# If host nickname is not set use the hostname
	if [[ -z "$MY_HOST_NICKNAME" ]]; then
		MY_HOST_NICKNAME=$(hostname -s)
	fi

	top="${grey}{ ${cyan}${MY_HOST_NICKNAME} ${grey}}${root} { ${cyan}\w ${grey}}${nocol}"
	bottom="${grey}${prompt} ${nocol}"

	PS1="${top}${venv}${git_prompt}\n${bottom}"
}

unset PS1
PROMPT_COMMAND=gen_ps1
