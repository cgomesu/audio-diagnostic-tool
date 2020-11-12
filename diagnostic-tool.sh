#!/bin/bash

# author: cgomesu
# original repo: https://github.com/cgomesu/audio-diagnostic-tool
# tools docs:
#   flac: https://xiph.org/flac/documentation_tools_flac.html
#   mp3val: http://mp3val.sourceforge.net/docs/manual.html

are_you_sure () {
  unset ARE_YOU_SURE_INPUT
  while [[ ! $ARE_YOU_SURE_INPUT = 'y' && ! $ARE_YOU_SURE_INPUT = 'n' ]]; do
    read -r -p 'Are you sure you want to continue? (y/n): ' ARE_YOU_SURE_INPUT
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
        read -r -p '[audio-diag] Would you like to provide a custom path? (y/n): ' LOG_DIR_INPUT
      done
      if [[ $LOG_DIR_INPUT = 'n' ]]; then
        echo '[audio-diag] The log directory is required.'
        end 'Unable to make a log directory.' 1
      else
        while [[ ! -d "$NEW_LOG_DIR" ]]; do
          read -r -p '[audio-diag] Enter the full path to an existing directory (/path/to/dir/): ' NEW_LOG_DIR
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
  local PACKAGES=('flac' 'mp3val')
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
  echo '---------------'
  while read -r audio_file; do
    echo '[audio-diag] Processing: '"$audio_file"
    echo '[audio-diag] Date: '$(date)
    # skip files that have been tested before
    if [[ $(cat "$GOOD_LOG") =~ "$audio_file" ]]; then
      echo '[audio-diag] This file has already been processed before and it was GOOD then.'
      echo '[audio-diag] If you want to retest and process it, remove it from the following log: '"$GOOD_LOG"
      echo '---------------'
      continue
    elif [[ $(cat "$BAD_LOG") =~ "$audio_file" ]]; then
      echo '[audio-diag] This file has already been processed before and it was BAD then.'
      echo '[audio-diag] If you want to retest and process it, remove it from the following log: '"$BAD_LOG"
      echo '---------------'
      continue
    # unmounting/moving/renaming may cause $audio_file to not be accessible anymore
    elif [[ ! -f "$audio_file" ]]; then
      echo '[audio-diag] The file does not exist anymore.'
      if [[ ! -d "$(dirname "$audio_file")" ]]; then
        echo '[audio-diag] ERROR: It looks like the directory '"$(dirname "$audio_file")"' has been moved/deleted/unmounted.'
      fi
      echo '---------------'
      continue
    fi
    # test file
    unset FLAG_CORRUPTED
    cache audio_file_test
    AUDIO_FILE_TEST="$CACHE"
    if [[ "$audio_file" =~ (F|f)(L|l)(A|a)(C|c)$ ]]; then
      echo '[audio-diag] Testing with flac...'
      # flac cli tool in test mode, output only errors
      flac -st "$audio_file" > "$AUDIO_FILE_TEST" 2>&1
      if [[  $(cat "$AUDIO_FILE_TEST")  ]]; then
        # catch file not being accessible after testing
        if [[ -f "$audio_file" ]]; then
          echo '[audio-diag] Uh-oh! The file HAS AN ERROR!'
          # TODO: Parse errors because some are not critical
          FLAG_CORRUPTED=true
        else
          echo '[audio-diag] WARNING: This file is NO LONGER ACCESSIBLE. Skipping file.'
          echo '---------------'
          continue
        fi
      else
        echo '[audio-diag] Good news, everyone! The audio file is OKAY!'
        FLAG_CORRUPTED=false
      fi
    elif [[ $audio_file =~ (M|m)(P|p)(1|2|3)$ ]]; then
      echo '[audio-diag] Testing with mp3val...'
      mp3val -si "$audio_file" > "$AUDIO_FILE_TEST" 2>&1
      if [[  $(cat "$AUDIO_FILE_TEST") =~ (WARNING\:|ERROR\:) ]]; then
        if [[ -f "$audio_file" ]]; then
          echo '[audio-diag] Uh-oh! The file HAS AN ERROR!'
          # TODO: Parse errors because some are not critical
          FLAG_CORRUPTED=true
        else
          echo '[audio-diag] WARNING: This file is NO LONGER ACCESSIBLE. Skipping file.'
          echo '---------------'
          continue
        fi
      else
        echo '[audio-diag] Good news, everyone! The audio file is OKAY!'
        FLAG_CORRUPTED=false
      fi
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
        echo '[audio-diag] Unable to parse the filename. Using random number as name.'
        ERROR_FILE="$ERRORS"$RANDOM'.txt'
        cat "$AUDIO_FILE_TEST" > "$ERROR_FILE"
        echo '[audio-diag] Saved to: '"$ERROR_FILE"
      fi
      if [[ $POST_PROCESSING = fix ]]; then
        echo '[audio-diag] POST-PROCESSING: FIX'
        cache audio_file_fix
        AUDIO_FILE_FIX="$CACHE"
        echo '[audio-diag] Fixing file: '"$audio_file"
        if [[ "$audio_file" =~ (F|f)(L|l)(A|a)(C|c)$ ]]; then
          # silent, force overwwrite, decode through errors
          flac -sfF "$audio_file" > "$AUDIO_FILE_FIX" 2>&1
          if [[ ! -z $(cat "$AUDIO_FILE_FIX") ]]; then
            echo '[audio-diag] WARNING: There was an error while fixing the file.'
            echo '[audio-diag] Message: '$(cat "$AUDIO_FILE_FIX")
            echo '[audio-diag] Testing and fixing it one more time...'
            > "$AUDIO_FILE_TEST"
            flac -st "$audio_file" > "$AUDIO_FILE_TEST" 2>&1
            if [[ ! -z $(cat "$AUDIO_FILE_TEST") ]]; then
              > "$AUDIO_FILE_FIX"
              flac -sfF "$audio_file" > "$AUDIO_FILE_FIX" 2>&1
              if [[ ! -z $(cat "$AUDIO_FILE_FIX") ]]; then
                echo '[audio-diag] WARNING: Continued to get an error while fixing the file. File might be unfixable.'
                echo '[audio-diag] WARNING: Manually check its error file at '"$ERRORS"
              else
                echo '[audio-diag] Good news, everyone! Finished fixing without errors.'
              fi
            else
              echo '[audio-diag] Good news, everyone! Finished fixing without errors.'
            fi
          else
            echo '[audio-diag] Good news, everyone! Finished fixing without errors.'
          fi
        elif [[ "$audio_file" =~ (M|m)(P|p)(1|2|3)$ ]]; then
          # suppress info msgs, fix, remove backup
          mp3val -si -f -nb "$audio_file" > "$AUDIO_FILE_TEST" 2>&1
          if [[  $(cat "$AUDIO_FILE_TEST") =~ FIXED\: ]]; then
            echo '[audio-diag] Good news, everyone! The file was fixed.'
          else
            echo '[audio-diag] WARNING: Unable to fix this file.'
          fi
        fi
      elif [[ $POST_PROCESSING = delete ]]; then
        echo '[audio-diag] POST-PROCESSING: DELETE'
        cache audio_file_delete
        AUDIO_FILE_DELETE="$CACHE"
        echo '[audio-diag] Deleting file: '"$audio_file"
        rm -f "$audio_file" 2> "$AUDIO_FILE_DELETE"
        if [[ ! -z $(cat "$AUDIO_FILE_DELETE") ]]; then
          echo '[audio-diag] There was an error deleting the file.'
          echo '[audio-diag] Message: '$(cat "$AUDIO_FILE_DELETE")
        else
          echo '[audio-diag] File deleted!'
        fi
      fi
    elif [[ $FLAG_CORRUPTED = false ]]; then
      echo '[audio-diag] The file will be appended to '"$GOOD_LOG"
      echo "$audio_file" >> "$GOOD_LOG"
    else
      echo '[audio-diag] The file has not been flagged yet. Nothing has been done to it.'
    fi
    echo '---------------'
  done < "$AUDIO_FILES"
}

defaults () {
  # required then optional
  if [[ -z "$TARGET" ]]; then
    echo 'ERROR: The argument -t is required.'
    exit 1
  fi
  if [[ -z $EXTENSIONS ]]; then
    EXTENSIONS=('flac' 'mp1' 'mp2' 'mp3')
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
  echo "$1"
  echo '#################################################'
  exit $2
}

# takes a package as arg
install () {
  local PACKAGE_NAME="$1"
  # TODO: On install failure, we could flag the package and try to skip its usage instead of exiting
  echo '---------------'
  while [[ ! $INSTALL_INPUT = 'y' && ! $INSTALL_INPUT = 'n' ]]; do
    read -r -p '[audio-diag] Would you like to install the missing package now? (y/n): ' INSTALL_INPUT
  done
  if [[ $INSTALL_INPUT = 'n' ]]; then
    echo '[audio-diag] All packages are required.'
    echo '---------------'
    exit 1
  else
    if [[ -z $OS ]]; then
      if [[ $(hostnamectl) =~ Operating\ System\:\ (.*) || $(cat /etc/*-release) =~ NAME=\"(.*)\" ]]; then
        OS="${BASH_REMATCH[1]}"
      else
        echo '[audio-diag] Unable to parse the name of the operating system.'
        # try finding a package manager then
        local PACKAGE_MANAGERS=('apt' 'pacman' 'yum')
        for pckmng in ${PACKAGE_MANAGERS[@]}; do
          if [[ -z $(command -v $pckmng) ]]; then
            PACKAGE_MANAGER=$pckmng
            break
          fi
        done
        if [[ -z $PACKAGE_MANAGER ]]; then
          echo '[audio-diag] Also unable to find a package manager.'
          echo '[audio-diag] Please manually install '$PACKAGE_NAME' and try again.'
          echo '---------------'
          exit 1
        fi
      fi
    fi
    if [[ "$OS" =~ b(ian|untu) || $PACKAGE_NAME = apt ]]; then
      sudo apt install $PACKAGE_NAME -yy
    elif [[ "$OS" =~ (A|a)rch || $PACKAGE_NAME = pacman ]]; then
      sudo pacman -S $PACKAGE_NAME --noconfirm
    elif [[ "$OS" =~ ((R|r)ed(H|h)at|(F|f)edora|(C|c)ent(OS|os)|(SUSE|suse)) || $PACKAGE_NAME = yum ]]; then
      sudo yum -y install $PACKAGE_NAME
    else
      echo '[audio-diag] Could not identify the distro.'
      echo '[audio-diag] Please manually install '$PACKAGE_NAME' and try again.'
      echo '---------------'
      exit 1
    fi
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
  echo '    -t  str  Path to a dir or file to be tested. If dir, it works recursively as well.'
  echo ''
  echo '  Optional:'
  echo '    -e  str  File extension to test (e.g., mp3). Default: common audio file extensions.'
  echo '    -h       Show this help message.'
  echo '    -l  str  Path to an existing dir where the log/ will be stored. Default: ./'
  echo '    -p  str  Post-processing mode for flagged files: fix, delete, none. Default: none.'
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
