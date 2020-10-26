#!/bin/bash

# author: cgomesu
# original repo: https://github.com/cgomesu/audio-diagnostic-tool
# tools docs:
#   ffmpeg: https://ffmpeg.org/documentation.html
#   flac: https://xiph.org/flac/documentation_tools_flac.html
#   mp3val: http://mp3val.sourceforge.net/docs/manual.html

are_you_sure () {
	unset ARE_YOU_SURE_INPUT
	while [[ ! $ARE_YOU_SURE_INPUT = 'y' && ! $ARE_YOU_SURE_INPUT = 'n' ]]; do
		read -p 'Are you sure you want to continue? (y/n): ' ARE_YOU_SURE_INPUT
	done
}

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
	CACHE=$CACHE_ROOT$FILENAME'.tmp'
	if [[ ! -f "$CACHE" ]]; then
		touch "$CACHE"
	else
		> "$CACHE"
	fi
}

check_commands () {
	echo '+++++++++++++++'
	local COMMANDS=('cat' 'date' 'dirname' 'echo' 'find' 'mkdir' 'read' 'rm' 'touch' 'tr' 'unset' 'wc')
	echo '[audio-diag] Checking the required commands: '${COMMANDS[@]}
	for cmd in ${COMMANDS[@]}; do
		if [[ -z $(command -v $cmd) ]]; then
			echo '[audio-diag] The following command cannot be found in this users $PATH:' $cmd
			echo '[audio-diag] Fix it and  try again.'
			exit 1
		else
			echo '[audio-diag] '$cmd': OK'
		fi
	done
	echo '+++++++++++++++'
}

check_dirs_files () {
	echo '+++++++++++++++'
	cache check_dirs_files
	echo '[audio-diag] Checking log dir and files...'
	if [[ ! -d "$LOG_DIR" ]]; then
		echo '[audio-diag] '"$LOG_DIR"' is missing. Creating one...'
		mkdir "$LOG_DIR" 2> "$CACHE"
		# error checking here because others depend on this dir
		if [[ ! -z $(cat "$CACHE") ]]; then
			echo '[audio-diag] There was an error making the directory '"$LOG_DIR"
			echo '[audio-diag] Message: '$(cat "$CACHE")
			while [[ ! $LOG_DIR_INPUT = 'y' && ! $LOG_DIR_INPUT = 'n' ]]; do
				read -p '[audio-diag] Would you like to provide a custom path? (y/n): ' LOG_DIR_INPUT
			done
			if [[ $LOG_DIR_INPUT = 'n' ]]; then
				echo '[audio-diag] The log directory is required.'
				end 'Unable to make a log directory.' 1
			else
				while [[ ! -d "$NEW_LOG_DIR" ]]; do
					read -p '[audio-diag] Enter the full path to an existing directory (/path/to/dir/): ' NEW_LOG_DIR
				done
				if [[ ! "$NEW_LOG_DIR" =~ \/$ ]]; then
					LOG_DIR=$NEW_LOG_DIR'/log/'
				else
					LOG_DIR=$NEW_LOG_DIR'log/'
				fi
				> "$CACHE"
				mkdir "$LOG_DIR" 2> "$CACHE"
				if [[ ! -z $(cat "$CACHE") ]]; then
					echo '[audio-diag] There was an error making the directory at '"$LOG_DIR"
					echo '[audio-diag] Message: '$(cat "$CACHE")
					end 'Unable to make a log directory.' 1
				else
					echo '[audio-diag] The log directory will be at '"$LOG_DIR"
				fi
			fi
		fi
	fi
	GOOD_LOG=$LOG_DIR'good_files.log'
	if [[ ! -f "$GOOD_LOG" ]]; then
		echo '[audio-diag] '"$GOOD_LOG"' is missing. Creating one...'
		touch "$GOOD_LOG"
	fi
	BAD_LOG=$LOG_DIR'bad_files.log'
	if [[ ! -f "$BAD_LOG" ]]; then
		echo '[audio-diag] '"$BAD_LOG"' is missing. Creating one...' 
		touch "$BAD_LOG"
	fi
	ERRORS=$LOG_DIR'errors/'
	if [[ ! -d "$ERRORS" ]]; then
		echo '[audio-diag] '"$ERRORS"' is missing. Creating one...'
		mkdir "$ERRORS"
	fi
	echo '[audio-diag] Done.'
	echo '+++++++++++++++'
}

check_packages () {
	echo '+++++++++++++++'
	local PACKAGES=('ffmpeg' 'flac' 'mp3val')
	echo '[audio-diag] Checking required packages: '${PACKAGES[@]}
	for pkg in ${PACKAGES[@]}; do
		if [[ -z $(command -v $pkg) ]]; then
			echo '[audio-diag] The following package is not installed or cannot be found in this users $PATH:' $pkg
			install $pkg
		else
			echo '[audio-diag] '$pkg': OK'
		fi
	done
	echo '+++++++++++++++'
}

cleanup () {
	# remove cache file
	if [[ -d "$CACHE_ROOT" ]]; then
		rm -rf "$CACHE_ROOT"
	fi
}

diagnosis_config () {
	check_packages
	check_commands
	check_dirs_files
}

diagnosis_run () {
	echo '---------------'
	cache audio_files
	AUDIO_FILES="$CACHE"
	if [[ -d "$TARGET" ]]; then
		echo '[audio-diag] Searching for audio files in '"$TARGET"'. This may take a while...'
		for ext in ${EXTENSIONS[@]}; do
		find "$TARGET" -iname "*$ext" -printf "%p\n" >> "$AUDIO_FILES"
		done
		if [[ -z $(cat "$AUDIO_FILES") ]]; then
			echo '[audio-diag] Did not find a single audio file in '"$TARGET"' and its subdirs.'
			end 'No audio files found.' 0
		else
			echo '[audio-diag] Found a total of '$(wc -l "$AUDIO_FILES" | tr -cd [:digit:])' audio files in '"$TARGET"' and its subdirs.'
		fi
	else
		echo "$TARGET" > "$AUDIO_FILES"
	fi
	while read audio_file; do
		echo '---------------'
		echo '[audio-diag] Processing: '"$audio_file"
		echo '[audio-diag] Date: '$(date)
		# skip files that have been analyzed before
		if [[ $(cat "$GOOD_LOG" | grep -F "$audio_file") ]]; then
			echo '[audio-diag] This file has already been processed before and it was GOOD then.'
			echo '[audio-diag] If you want to reanalyze it, clean: '"$GOOD_LOG"
			echo '---------------'
			continue
		elif [[ $(cat "$BAD_LOG" | grep -F "$audio_file") ]]; then
			echo '[audio-diag] This file has already been processed before and it was BAD then.'
			echo '[audio-diag] If you want to reanalyze it, clean: '"$BAD_LOG"
			echo '---------------'
			continue
		# unmounting/moving/renaming may cause $audio_file to not be accessible anymore
		elif [[ ! -f "$audio_file" ]]; then
			echo '[audio-diag] The file does not exist anymore.'
			if [[ ! -d "$(dirname "$audio_file")" ]]; then
				echo '[audio-diag] ERROR: It looks like the directory '"$(dirname "$audio_file")"' has been moved/deleted/unmounted.'
				echo '---------------'
				end "An entire directory is no longer accessible." 1
			else
				echo '[audio-diag] WARNING: Could not process this file but the directory is still accessible.'
				echo '---------------'
			fi
			continue
		fi
		# test file
		unset FLAG_CORRUPTED
		cache audio_file_test
		AUDIO_FILE_TEST="$CACHE"
		if [[ "$audio_file" =~ (flac|FLAC)$ ]]; then
			# flac cli tool in test mode, output only errors
			flac -st "$audio_file" > "$AUDIO_FILE_TEST" 2>&1
			if [[  $(cat "$AUDIO_FILE_TEST")  ]]; then
				# catch file not being accessible after testing
				if [[ -f "$audio_file" ]]; then
					echo '[audio-diag] Uh-oh! The file HAS AN ERROR!'
					# compare flac versions
					if [[ "$(flac --version)" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
						local CLI_vMAJOR=${BASH_REMATCH[1]}
						local CLI_vMINOR=${BASH_REMATCH[2]}
						local CLI_vPATCH=${BASH_REMATCH[3]}
					else
						echo '[audio-diag] WARNING: Unable to parse the version of the flac cli.'
					fi
					if [[ "$(metaflac --show-vendor-tag "$audio_file")" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
						local FILE_vMAJOR=${BASH_REMATCH[1]}
						local FILE_vMINOR=${BASH_REMATCH[2]}
						local FILE_vPATCH=${BASH_REMATCH[3]}
					else
						echo '[audio-diag] WARNING: Unable to parse the flac version of the file.'
					fi
					if [[ $CLI_vMAJOR -lt $FILE_vMAJOR ]] || [[ $CLI_vMAJOR -eq $FILE_vMAJOR && $CLI_vMINOR -lt $FILE_vMINOR ]] || [[ $CLI_vMAJOR -eq $FILE_vMAJOR && $CLI_vMINOR -eq $FILE_vMINOR && $CLI_vPATCH -lt $FILE_vPATCH ]]; then
						echo '[audio-diag] WARNING: You are possibly using an OUTDATED FLAC VERSION.'
						echo '[audio-diag] WARNING: Update your flac cli tool and run this script again. Skipping file.'
						echo '---------------'
						continue
					else
						echo '[audio-diag] The audio file is LIKELY CORRUPTED.'
						FLAG_CORRUPTED=true
					fi
				else
					echo '[audio-diag] WARNING: This file is NO LONGER ACCESSIBLE. Skipping file.'
					echo '---------------'
					continue
				fi
			else
				echo '[audio-diag] Good news, everyone! The audio file is OKAY!'
				FLAG_CORRUPTED=false
			fi
		# TODO: Other testing tools
		elif [[ $audio_file =~ (mp3|MP3|mp2|MP2|mp1|MP1)$ ]]; then
			# mp3val
			echo 'mp3val'
		else
			# ffmpeg
			echo 'ffmpeg'
		fi
		# post-processing
		if [[ $FLAG_CORRUPTED = true ]]; then
			echo '[audio-diag] The file will be appended to '"$BAD_LOG"
			echo "$audio_file" >> "$BAD_LOG"
			if [[ "$audio_file" =~ [^\/]+$ ]]; then
				echo '[audio-diag] To investigate the error, check '"$ERRORS"
				ERROR_FILE="$ERRORS""${BASH_REMATCH[0]}"'.txt'
				cat "$AUDIO_FILE_TEST" > "$ERROR_FILE"
			else
				echo '[audio-diag] Unable to save the error file'
			fi
			if [[ $POST_PROCESSING = fix ]]; then
				# TODO: Fix postprocessing
				echo 'fix'
			elif [[ $POST_PROCESSING = delete ]]; then
				# TODO: Delete postprocessing
				echo 'delete'
			fi
		elif [[ $FLAG_CORRUPTED = false ]]; then
			echo '[audio-diag] The file will be appended to '"$GOOD_LOG"
				echo "$audio_file" >> "$GOOD_LOG"
		fi
		echo '---------------'
	done < $AUDIO_FILES
}

defaults () {
	# required then optional
	if [[ -z "$TARGET" ]]; then
		echo 'ERROR: The argument -t is required.'
		usage
		exit 1
	fi
	if [[ -z $EXTENSIONS ]]; then
		# https://en.wikipedia.org/wiki/Audio_file_format#List_of_formats
		EXTENSIONS=('3gp' 'aa' 'aac' 'aax' 'act' 'aiff' 'alac' 'amr' 'ape' 'au' 'awb' 'dct' 'dss' 
			'dvf' 'flac' 'gsm' 'iklax' 'ivs' 'm4a' 'm4b' 'm4p' 'mmf' 'mp1' 'mp2' 'mp3' 'mpc' 'msv' 
			'nmf' 'ogg' 'oga' 'mogg' 'opus' 'ra' 'rm' 'raw' 'rf64' 'sln' 'tta' 'voc' 'vox' 'wav' 
			'wma' 'wv' 'webm' '8svx' 'cda')
	fi
	if [[ -z "$LOG_DIR" ]]; then
		LOG_DIR=./log/
	fi
	if [[ -z $POST_PROCESSING ]]; then
		POST_PROCESSING='none'
	fi
}

# takes msg and status as arg
end () {
	cleanup
	echo '#################################################'
	echo 'EXITING THE PROGRAM WITH THE FOLLOWING MESSAGE:'
	echo $1 
	echo '#################################################'
	exit $2
}

# takes a package as arg
install () {
	local PACKAGE_NAME="$1"
	if [[ -z $PACKAGE_NAME ]]; then
		echo '[audio-diag] Tried to install a missing package. Skipping.'
		return
	fi
	echo '---------------'
	while [[ ! $INSTALL_INPUT = 'y' && ! $INSTALL_INPUT = 'n' ]]; do
		read -p '[audio-diag] Would you like to install the missing package now? (y/n): ' INSTALL_INPUT
	done
	if [[ $INSTALL_INPUT = 'n' ]]; then
		echo '[audio-diag] All packages are required.'
		# Alternatively, we could flag the package and try to skip it
		exit 1
	else
		# TODO: check OS and run the appropriate install command
		# assume debian-based
		sudo apt install $PACKAGE_NAME -yy
		# TODO: Verify that package was installed succesfully
	fi
	echo '---------------'
}

start () {
	echo '#################################################'
	echo '############# AUDIO DIAGNOSTIC TOOL #############'
	echo '#################################################'
	echo 'This program tests a single or multiple audio '
	echo 'files for errors and generates logs with good '
	echo 'files (no errors found) and bad ones (at least '
	echo 'one error found). Files tagged as corrupted '
	echo 'can also be fixed or deleted by changing the '
	echo 'post-processing mode (-p).'
	echo ''
	echo 'For more information, check the repo:'
	echo 'https://github.com/cgomesu/audio-diagnostic-tool'
	echo '#################################################'
	echo 'Date: '$(date)
	echo '#################################################'
}

usage () {
	echo ''	
	echo 'Author: cgomesu'
	echo 'Repo: https://github.com/cgomesu/audio-diagnostic-tool'
	echo ''
	echo 'This is free. There is NO WARRANTY. Use at your own risk.'
	echo ''
	echo 'Usage:'
	echo ''
	echo "$0" '-t /path/to/dir/or/file [OPTIONS]'
	echo ''
	echo '  Required:'
	echo '    -t  str  Full path to a directory or file to be tested. If dir, it works recursively as well.'
	echo ''
	echo '  Optional:'
	echo '    -e  str  The audio file extension to test (e.g., mp3). Default: any of the common audio file extensions.'
	echo '    -h       Show this help message.'
	echo '    -l  str  Full path to an existing directory where the log/ subdir will be stored. Default: ./'
	echo '    -p  str  Post-processing mode for corrupted files: fix, delete, none. Fix mode uses tool-specific solutions or re-encoding. Default: none.'
	echo ''
}

while getopts 'e:hl:p:t:' OPT; do
	case ${OPT} in
		e)
			EXTENSION="$OPTARG"
            if [[ ! $EXTENSION =~ ^[a-zA-Z0-9]+$ ]]; then
				echo 'The audio file extension can only contain alphanumeric characters.'
				exit 1
			else
				EXTENSIONS=($EXTENSION)
			fi
			;;
		h)
			usage
			exit 0
			;;
		l)
			ROOT_LOG_DIR="$OPTARG"
			if [[ ! -d "$ROOT_LOG_DIR" ]]; then
				echo 'The directory '"$ROOT_LOG_DIR"' does not exist.'
				exit 1
			else
				if [[ ! "$ROOT_LOG_DIR" =~ \/$ ]]; then
					LOG_DIR="$ROOT_LOG_DIR"'/log/'
				else
					LOG_DIR="$ROOT_LOG_DIR"'log/'
				fi
			fi
			;;
		p)
			POST_PROCESSING="$OPTARG"
			if [[ ! $POST_PROCESSING =~ ^(fix|delete|none)$ ]]; then
				echo 'Post-processing mode must be either fix or delete or none.'
				exit 1
			elif [[ $POST_PROCESSING =~ ^fix$ ]]; then
				echo 'Post-processing mode is set to FIX corrupted files.'
				echo 'WARNING: This mode will permanently OVERWRITE ALL audio files tagged as corrupted.'
				are_you_sure
			elif [[ $POST_PROCESSING =~ ^delete$ ]]; then
				echo 'Post-processing mode is set to DELETE corrupted files.'
				echo 'WARNING: This mode will permanently REMOVE ALL audio files tagged as corrupted.'
				are_you_sure
			fi
			if [[ $ARE_YOU_SURE_INPUT = 'n' ]]; then
				echo 'Better safe than sorry!'
				exit 0
			fi
			;;
		t)
			TARGET="$OPTARG"
			if [[ ! -d "$TARGET" && ! -f "$TARGET" ]]; then
				echo 'The argument -t must be either a directory or a file.'
				exit 1
			fi
			;;
		\?)
			echo 'ERROR: Invalid option in the arguments.'
			usage
			exit 1
			;;
	esac
done

defaults
start
trap 'echo "!! ATTENTION !!"; end "Received a signal to stop" 1' SIGINT SIGHUP SIGTERM SIGKILL
diagnosis_config
diagnosis_run
end "Finished running succesfully!" 0
