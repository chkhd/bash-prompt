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
	curr_remote=$(git config branch."$curr_branch".remote)

	# If the branch is local only, it won't have a remote
	test $? -gt 0 && return 1

	curr_merge_branch=$(git config branch."$curr_branch".merge | cut -d / -f 3)
	count=$(git rev-list --left-right --count "$curr_branch"..."${curr_remote}/${curr_merge_branch}" 2> /dev/null)

	# Might be the first commit which is not pushed yet
	test $? -gt 0 && return 1

	ahead=$(printf "%s" "$count" | cut -f1)
	behind=$(printf "%s" "$count" | cut -f2)

	ab=''
	test "$ahead" -gt 0 && ab+="↑${ahead}"

	if [[ "$behind" -gt 0 ]]; then
		[[ -n "$ab" ]] && ab+=" ↓${behind}" || ab+="↓${behind}"
	fi

	[[ -n "$ab" ]] && printf "%s" "$ab" || printf ''
}

parse_git_last_fetch () {
	local f
	local now
	local last_fetch
	local opts

	opts=$([[ $(uname -s) == "Darwin" ]] && printf -- '-f%%m' || printf -- '-c%%Y')
	f=$(git rev-parse --show-toplevel)
	now=$(date +%s)
	last_fetch=$(stat "$opts" "${f}/.git/FETCH_HEAD" 2> /dev/null || printf '')

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
		while read -r line ; do
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
		[[ -n "$bits" ]] && printf "%s" "$bits" || printf ''
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

	printf "%s" "$status"
}

gen_ps1 () {
	# This needs to be the first command otherwise it will not have correct exit code
	local ec="$?"

	local red
	local cyan
	local grey
	local nocol
	local prompt
	local profile
	local k8s_context
	local kube_config
	local branch
	local status
	local git_prompt
	local venv
	local root
	local top
	local bottom

	PS1=''
	red='\[\e[0;31m\]'
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

	if is_git_prompt_useful_here; then
		branch=$(parse_git_branch)
		status=$(gen_git_status)

		git_prompt=" ${grey}{ ${branch} }${nocol}"
		[[ -n "$status" ]] && git_prompt+=" ${grey}{ ${status} }${nocol}"
	fi

	# If venv is active show it
	venv="${VIRTUAL_ENV}${CONDA_PREFIX}"
	venv=$([[ -n "$venv" ]] && printf " %s{ %s%s %s}%s" "$grey" "$cyan" "${venv##*/}" "$grey" "$nocol" || printf '')

	# Display the username in red if running as root
	root=''
	if [[ "$USER" == "root" ]]; then
		root=" ${grey}{ ${red}root ${grey}}"
	fi

	# If host nickname is not set use the hostname
	if [[ -z "$MY_HOST_NICKNAME" ]]; then
		MY_HOST_NICKNAME=$(hostname -s)
	fi

	# Show AWS profile if user asked to and it is set
	if ! test -z "$SHOW_AWS_PROFILE"; then
	  if [[ -z "$AWS_PROFILE" ]]; then
	    profile=""
	  else
	    profile=$(printf " ${grey}{ aws/%s }${nocol}" "$AWS_PROFILE")
	  fi
	fi

	# Shows current Kubernetes context if user asked to and there is one
	kube_config="${HOME}/.kube/config"
	if ! test -z "$SHOW_K8S_CONTEXT" && ! test -z "$kube_config"; then
	  k8s_context=$(printf " ${grey}{ k8s/%s }${nocol}" "$(cat ${kube_config} | grep current-context | cut -f2 -d\ )")
	fi

	top="${grey}{ ${cyan}${MY_HOST_NICKNAME} ${grey}}${root} { ${cyan}\\w ${grey}}${nocol}"
	bottom="${grey}${prompt} ${nocol}"

	PS1="${top}${profile}${k8s_context}${venv}${git_prompt}\\n${bottom}"
}

unset PS1
PROMPT_COMMAND=gen_ps1
