#!/bin/bash
#
# author: cgomesu
# original repo: https://github.com/cgomesu/audio-diagnostic-tool
#
# tools doc:
#   flac: https://xiph.org/flac/documentation_tools_flac.html
#   ffmpeg: 
#   mp3diag: 
#

# TODO: Check spaces and tabs

cache () {
	if [[ -z "$1" ]]; then
		echo '[audio-diag] Cache file was not specified. Assuming generic.'
		local FILENAME='generic'
	else
		local FILENAME="$1"
	fi
	# cache to memory
	CACHE_ROOT='/tmp/audio-diag/'
	if [[ ! -d "$CACHE_ROOT" ]]; then
		mkdir "$CACHE_ROOT"
	fi
	CACHE=$CACHE_ROOT$FILENAME'.cache'
	if [[ ! -f "$CACHE" ]]; then
		touch "$CACHE"
	else
		> "$CACHE"
	fi
}

cleanup () {
	# remove cache file
	if [[ -f $CACHE ]]; then
		rm -f $CACHE
	fi
}

# takes a package as arg
install () {
	local package_name="$1"
	if [[ -z $package_name ]]; then
		echo '[audio-diag] Tried to install a missing package. Skipping.'
		return
	fi
	echo '---------------'
	while [[ ! $install_input = 'y' && ! $install_input = 'n' ]]; do
		read -p '[audio-diag] Would you like to install the missing package now? (y/n): ' install_input
	done
	if [[ $install_input = 'n' ]]; then
		echo '[audio-diag] All packages are required.'
		# Alternatively, we could flag the package and try to skip it
		exit 1
	else
		# TODO: check OS and run the appropriate install command
		# assume debian-based
		sudo apt install "$package_name" -yy
		# TODO: Verify that package was installed succesfully
	fi
	echo '---------------'
}

requisites_packages () {
	local PACKAGES=('ffmpeg' 'flac' 'mp3diag')
	echo '[audio-diag] Checking that the following package are installed and accessible:'
	echo '[audio-diag] '${PACKAGES[@]}
	for package in ${PACKAGES[@]}; do
		if [[ -z $(command -v $package) ]]; then
			echo '[audio-diag] The following package is not installed or cannot be found in this users $PATH:' $package
			install "$package"
		else
			echo '[audio-diag] '$package': Okay!'
		fi
	done
}

requisites_commands () {
	# TODO: update array with all required commands
	local COMMANDS=('cat' 'echo' 'find' 'mkdir' 'rm')
	echo 'Checking that the following commands can be found in the users $PATH:'
	echo ${COMMANDS[@]}
	for cmd in ${COMMANDS[@]}; do
		if [[ -z $(command -v $cmd) ]]; then
			echo '[audio-diag] The following command cannot be found in this users $PATH:' $cmd
			echo '[audio-diag] Fix it and  try again.'
			exit 1
		else
			echo '[audio-diag] '$cmd': Okay!'
		fi
	done
}

config_diag () {
	requisites_packages
	requisites_commands
	requisites_dirs_files
}

requisites_dirs_files () {
	cache requisites_dirs_files
	LOG_DIR='./log/'
	if [[ ! -d $LOG_DIR ]]; then
		echo '---------------'
		echo '[audio-diag] '$LOG_DIR' is missing. Creating one...'
		mkdir $LOG_DIR 2> $CACHE
		if [[ ! -z $(cat $CACHE) ]]; then
			echo '[audio-diag] There was an error making the directory '$LOG_DIR
			echo '[audio-diag] Message: '$(cat $CACHE)
			while [[ ! $LOG_DIR_input = 'y' && ! $LOG_DIR_input = 'n' ]]; do
				read -p '[audio-diag] Would you like to provide a custom path? (y/n): ' LOG_DIR_input
			done
			if [[ $LOG_DIR_input = 'n' ]]; then
				echo '[audio-diag] The log directory is required.'
				echo '---------------'
				end_diag 'Unable to make a log directory.' 1
			else
				while [[ ! -d $new_LOG_DIR && $new_LOG_DIR =~ ^\/.*$ ]]; do
					read -p '[audio-diag] Enter the full path to an existing directory (/path/to/dir/): ' new_LOG_DIR
				done
				if [[ ! $new_LOG_DIR =~ \/$ ]]; then
					LOG_DIR=$new_LOG_DIR'/log/'
				else
					LOG_DIR=$new_LOG_DIR'log/'
				fi
				> $CACHE
				mkdir $LOG_DIR 2> $CACHE
				if [[ ! -z $(cat $CACHE) ]]; then
					echo '[audio-diag] There was an error making the directory at '$LOG_DIR
					echo '[audio-diag] Message: '$(cat $CACHE)
					echo '---------------'
					end_diag 'Unable to make a log directory.' 1
				else
					echo '[audio-diag] The log directory will be at '$LOG_DIR
				fi
			fi
		fi
	    echo '[audio-diag] Done.'
	    echo '---------------'
	fi
	GOOD_LOG=$LOG_DIR'good_files.log'
	if [[ ! -f $GOOD_LOG ]]; then
		echo '---------------'
		echo '[audio-diag] '$GOOD_LOG' is missing. Creating one...'
	    touch $GOOD_LOG
	    echo '[audio-diag] Done.'
	    echo '---------------'
	fi
	BAD_LOG=$LOG_DIR'bad_files.log'
	if [[ ! -f $BAD_LOG ]]; then
		echo '---------------'
		echo '[audio-diag] '$BAD_LOG' is missing. Creating one...' 
	    touch $BAD_LOG
	    echo '[audio-diag] Done.'
	    echo '---------------'
	fi
	CACHE_ERRORS=$LOG_DIR'errors/'
	if [[ ! -d $CACHE_ERRORS ]]; then
		echo '---------------'
		echo '[audio-diag] '$CACHE_ERRORS' is missing. Creating one...'
		mkdir $CACHE_ERRORS
	    echo '[audio-diag] Done.'
	    echo '---------------'
	fi
}

