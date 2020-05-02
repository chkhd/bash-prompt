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
	count=$(git rev-list --left-right --count "${curr_branch}...${curr_remote}/${curr_merge_branch}" 2> /dev/null)

	# Might be the first commit, which is not pushed yet
	test $? -gt 0 && return 1

	ahead=$(printf "$count" | cut -f1)
	behind=$(printf "$count" | cut -f2)

	ab=''
	test "$ahead" -gt 0 && ab+="↑${ahead}"

	if test "$behind" -gt 0; then
		test -n "$ab" && ab+=" ↓${behind}" || ab+="↓${behind}"
	fi

	test -n "$ab" && printf "$ab" || printf ''
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

	test -n "$last_fetch" && test $(( now > (last_fetch + 15*60) )) -eq 1 && printf '☇' || printf ''
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
		test -n "$bits" && printf "$bits" || printf ''
	)
}

gen_git_status () {
	local ahead_behind
	local fetch
	local status

	ahead_behind=$(parse_git_ahead_behind)
	fetch=$(parse_git_last_fetch)
	status=$(parse_git_status)

	test -n "$ahead_behind" && test -n "$status" && status+=" ${ahead_behind}" || status+="${ahead_behind}"
	test -n "$fetch" && test -n "$status" && status+=" ${fetch}" || status+="${fetch}"

	printf "$status"
}

gen_ps1 () {
	# This needs to be the first command otherwise it will not have correct exit code
	local ec="$?"

	local red
	local cyan
	local grey
	local nocol
	local prompt
	local aws_profile
	local k8s_context
	local k8s_ns
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
	yellow='\[\e[1;33m\]'
	green='\[\e[1;32m\]'
	nocol='\[\e[0m\]'

	# Indicate if previous command succeeded or not
	prompt='⑉'
	test ${ec} -eq 0 && prompt="${grey}${prompt}" || prompt="${red}${prompt}"

	# If inside git managed directory show git information
	git_prompt=''
	branch=''
	status=''

	if is_git_prompt_useful_here; then
		branch=$(parse_git_branch)
		status=$(gen_git_status)

		git_prompt=" ${grey}{ ${branch} }${nocol}"
		test -n "$status" && git_prompt+=" ${grey}{ ${status} }${nocol}"
	fi

	# If venv is active show it
	venv="${VIRTUAL_ENV}${CONDA_PREFIX}"
	venv=$(test -n "$venv" && printf " %s{ %s%s %s}%s" "$grey" "$cyan" "${venv##*/}" "$grey" "$nocol" || printf '')

	# Display the username in red if running as root
	root=''
	if test "$USER" == "root"; then
		root=" ${grey}{ ${red}root ${grey}}"
	fi

	# If host nickname is not set use the hostname
	if test -z "$MY_HOST_NICKNAME"; then
		MY_HOST_NICKNAME=$(hostname -s)
	fi

	# Show AWS profile if user asked, and it is set
	if ! test -z "$SHOW_AWS_PROFILE"; then
	  if test -z "$AWS_PROFILE"; then
	    aws_profile=""
	  else
	    aws_profile=$(printf " ${grey}{ aws: %s }${nocol}" "$AWS_PROFILE")
	  fi
	fi

  if ! test -z "$SHOW_K8S_CONTEXT" || ! test -z "$SHOW_K8S_NS"; then
	  kube_config="${KUBECONFIG:-${HOME}/.kube/config}"
	  k8s_context=$(cat "$kube_config" | grep current-context | cut -d\  -f2)
	fi

	# Show Kubernetes namespace if user asked, and it is not default one
	if ! test -z "$SHOW_K8S_NS"; then
	  k8s_ns=$(cat "$kube_config" | yq r -j - | ctx="$k8s_context" jq -r '.contexts[] | select(.name | contains($ENV.ctx)) | .context.namespace')
	  if [[ "$k8s_ns" != "default" && "$k8s_ns" != "" && "$k8s_ns" != "null" ]]; then
	    k8s_ns=$(printf " ${grey}{ k8s-ns: %s }${nocol}" "$k8s_ns")
	  else
	    k8s_ns=""
	  fi
	fi

	# Shows current Kubernetes context if user asked and there is one
	if ! test -z "$SHOW_K8S_CONTEXT" && ! test -z "$kube_config"; then
	  k8s_context=$(printf " ${grey}{ k8s: %s }${nocol}" "$k8s_context")
	fi

	top="${grey}{ ${yellow}${MY_HOST_NICKNAME} ${grey}}${root} { ${yellow}\\w ${grey}}${nocol}"
	bottom="${grey}${prompt} ${nocol}"

	PS1="${top}${aws_profile}${k8s_context}${k8s_ns}${venv}${git_prompt}\\n${bottom}"
}

unset PS1
PROMPT_COMMAND=gen_ps1
