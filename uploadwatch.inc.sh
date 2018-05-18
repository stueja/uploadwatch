### Functions



## Datenbankabfrage
function QueryDB() {
# call: x=$(QueryDB databasename "query")
local qdb="$1"
shift
local query="$@"

declare -A DB
declare -A UN
	declare -A PW

	# needs information from /root/uploadwatch.passwords
	# format:
	#DB[database1]="database1"
	#UN[database1]="username1"
	#PW[database1]="password1"
	#DB[database2]="database2"
	#UN[database2]="username2"
	#PW[database2]="password2"

	local DBused="${DB[$qdb]}"
	local UNused="${UN[$qdb]}"
	local PWused="${PW[$qdb]}"

	local RESULT=$(mysql --default-character-set=utf8 -u$UNused -p$PWused $DBused -se "$query") 
	echo $RESULT
}


function CheckFolder() {
# call: x=$(CheckFolder foldername)
	local folder="$@"

	mkdir -p "$folder"
	if [[ ! -d "$folder" ]]
	then
		echo false
	else
		echo true
	fi
}


function CheckFile() {
	local filename="$@"

	if [[ ! -f "$filename" ]]
	then
		echo true
	else
		echo false
	fi
}


function CheckFileSize() {
	local incomingfile="$1"
	local existingfile="$2"

	local incomingfilesize="$vIncomingBytes"
	local existingfilesize=$(stat -c%s "$existingfile")

	if (( $incomingfilesize > $existingfilesize ))
	then
		echo true
	else
		echo false
	fi
}


function logit() {
  # valid levels
  # emerg
  # alert
  # crit
  # err
  # warning
  # notice
  # info
  # debug

  local criticality=$1
  shift
  local string="$@"
  local RED
  local NC
  local verbosity

  case "$criticality" in
    "emerg"|"alert"|"crit")
      RED="\033[0;31m"
      NC="\033[0m" # No Color
      verbosity="-v"
      ;;
    *)
      RED=""
      NC=""
      verbosity=$VERBOSE
      ;;
  esac

  if [[ "$verbosity" == "-v" ]]
  then
    printf "${RED}[$(date --rfc-3339=seconds)]: $string${NC}\n"
    logger -p $criticality -t vod "$string"
  fi

}

function TestCommand() {
	local fcommand="$@"

	if [[ "$TESTFLAG" == "-t" ]]
	then
		logger -p info -t vod "Test flag set:: $fcommand"
	else
		logger -p info -t vod "executing: $fcommand"
		eval "${fcommand}"
		if [[ $? -ne 0 ]]
		then
			critic=err
		else
			critic=info
		fi
		logger -p $critic -t vod "Rückgabe: $?"
	fi

	return $?
}


