#
# ~/.bash_profile
#

# Bash skips .profile when .bash_profile exists; retain host SDK setup.
[[ -f ~/.profile ]] && . ~/.profile
[[ -f ~/.bashrc ]] && . ~/.bashrc


# Added by Antigravity CLI installer
export PATH="$HOME/.local/bin:$PATH"
