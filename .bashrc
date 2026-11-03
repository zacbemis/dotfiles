#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

alias ..='cd ..'
export EDITOR='nvim'
export VISUAL='nvim'


# Added by Antigravity CLI installer
export PATH="$HOME/.local/bin:$PATH"
