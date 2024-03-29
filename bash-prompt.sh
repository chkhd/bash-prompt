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

	curr_merge_branch=$(git config branch."$curr_branch".merge | sed 's#refs/heads/###' )
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


gen_ibm_account_info () {
	local config="$HOME/.bluemix/config.json"

	if ! test -f "$config"; then
		return
	fi

	local account_name=$(jq -r '.Account.Name' < "$config")
	# local account_region=$(jq -r '.Region' < "$config")

	# printf "${account_name}/${account_region}"
	printf "${account_name}"
}


now () {
	[[ $(uname -s) == 'Darwin' ]] && gdate +%s%N \
	|| date +%s%N
}


# Function calls to skip for the DEBUG trap
SKIP_FUNCS=(__zoxide_hook gen_ps1)


debug () {
	# Skip for specific functions, during startup, in command chains and during completion
	[[ " ${SKIP_FUNCS[@]} " =~ " $BASH_COMMAND " ]] && return
	[[ -z $PROMPT_LOADED ]] && return
	[[ -z $PROMPT_ACTIVE ]] && return
	[[ -n $COMP_LINE ]] && return

	# Indicate the beginning of a command chain
	unset PROMPT_ACTIVE

	cmd_start_time=$(now)
}

format_time () {
	local formatted_time=$(( $1 / 1000 ))

	local us=$(( formatted_time % 1000 ))
	local ms=$(( (formatted_time / 1000) % 1000 ))
	local s=$(( (formatted_time / 1000000) % 60 ))
	local m=$(( (formatted_time / 60000000) % 60 ))
	local h=$(( formatted_time / 3600000000 ))

	# Goal: always show around 3 digits of accuracy
	if (( h > 0 )); then formatted_time=${h}h${m}m
	elif ((m > 0)); then formatted_time=${m}m${s}s
	elif ((s >= 10)); then formatted_time=${s}.$((ms / 100))s
	elif ((s > 0)); then formatted_time=${s}.$(printf %03d $ms)s
	elif ((ms >= 100)); then formatted_time=${ms}ms
	elif ((ms > 0)); then formatted_time=${ms}.$((us / 100))ms
	else formatted_time=${us}us
	fi

	echo "$formatted_time"
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
	local k8s
	local kube_config
	local branch
	local black
	local blue
	local brown
	local bright_cyan
	local orange
	local status
	local div
	local mdiv
	local magenta
	local ediv
	local git_prompt
	local venv
	local root
	local top
	local bottom

	PS1=''
	black='\[\e[0;30m\]'
	red='\[\e[38;5;160m\]'
	cyan='\[\e[38;5;80m\]'
	bright_cyan='\[\e[38;5;110m\]'
	blue='\[\e[0;34m\]'
	grey='\[\e[38;5;242m\]'
	yellow='\[\e[38;5;178m\]'
	green='\[\e[38;5;70m\]'
	orange='\[\e[38;5;142m\]'
	magenta='\[\e[38;5;140m\]'
	brown='\[\e[38;5;137m\]'
	nocol='\[\e[0m\]'

	prompt='$ '
	div="${grey}|${nocol} "
	mdiv='⎨ '
	ediv=' ⎬'

	# How long did it take to run the previous command? Only display if the user ran a
	# command since last time prompt was shown and SHOW_CMD_TIME is set
	if test -n "$SHOW_CMD_TIME" && test -n "$PROMPT_LOADED" && test ! "$cmd_start_time" == "$PREV_START_TIME"; then
		local cmd_timer=$(( $(now) - cmd_start_time ))
		PREV_START_TIME="$cmd_start_time"

		cmd_timer=$(format_time "$cmd_timer")
		cmd_timer=" ${grey}${cmd_timer}${nocol}"
	fi

	# Indicate if previous command succeeded or not
	if ! test ${ec} -eq 0; then
		prompt="${red}${prompt}"
	fi

	# If inside git managed directory show git information
	git_prompt=''
	branch=''
	status=''

	if is_git_prompt_useful_here; then
		branch=$(parse_git_branch)
		status=$(gen_git_status)

		git_prompt="${branch}"
		test -n "$status" && git_prompt+=" ${bright_cyan}${status}${nocol}"
		git_prompt=" ${div}${cyan}${git_prompt}${nocol}"
	fi

	# If venv is active show it
	venv="${VIRTUAL_ENV}${CONDA_PREFIX}"
	venv=$(test -n "$venv" && printf " ${div}${yellow}${venv##*/}${nocol}" || printf '')

	# Display the username in red if running as root
	root=''
	if test "$USER" == "root"; then
		root=" ${nocol}${div}${red}root${nocol}"
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
	    aws_profile=$(printf " ${div}${bright_cyan}%s${nocol}" "$AWS_PROFILE")
	  fi
	fi

	# Shows current Kubernetes context if user asked and there is one
	if ! test -z "$SHOW_K8S" || ! test -z "$SHOW_K8S_NS"; then
		kube_config="${KUBECONFIG:-${HOME}/.kube/config}"
		k8s_context=$(kubectl config current-context | cut -d\  -f2 | cut -d/ -f1 )

		# Show Kubernetes namespace if user asked, and it is not default one
		if ! test -z "$SHOW_K8S_NS"; then
			k8s_ns=$(kubectl config view --minify -o json | jq -r '.contexts[0].context.namespace')

			if [[ "$k8s_ns" != "default" && "$k8s_ns" != "" && "$k8s_ns" != "null" ]]; then
				k8s_ns=$(printf "%s" "$k8s_ns")
			else
				k8s_ns=""
			fi
		fi

		test ! -z "$SHOW_K8S" && k8s_context="${k8s_context}${grey}/${nocol}" || k8s_context=""
		k8s=" ${div}${green}${k8s_context}${orange}${k8s_ns}${nocol}"
	fi

	# Current IBM Cloud account name and region
	ibm_acct_info=$(gen_ibm_account_info)
	if ! test -z "$ibm_acct_info"; then
		ibm_acct_info=" ${div}${magenta}${ibm_acct_info}${nocol}"
	fi

	# For detecting the first invocation
	[[ -n $PROMPT_LOADED ]] || PROMPT_LOADED=t

	# For tracking the start of command chains
	PROMPT_ACTIVE=t

	# Final formatting
	top="${mdiv}${orange}${MY_HOST_NICKNAME}${nocol}${root}"
	bottom="${prompt}${nocol}"

	PS1="${top}${venv}${aws_profile}${k8s}${ibm_acct_info}${git_prompt} ${div}${brown}\\w${nocol}${cmd_timer}${ediv}\\n${bottom}"
}


unset PS1
trap 'debug' DEBUG
PROMPT_COMMAND=gen_ps1
