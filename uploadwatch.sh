#!/bin/bash

# uploadwatch.neu.sh
# a new take on the uploadwatch, 2018-05-14

# Reihenfolge:
# - Filenamen parsen (Datum, Sender, Dateigröße, Videolänge, Kategorie)
# - Episodenname generieren, wenn Tatort
# - Vorschaubild generieren 
# - ist es ein avi?
# - ist bereits eine Datei mit diesem Namen vorhanden?
# - welche Datei ist größer?
# - neue Datei linken.

# Fälle zu testen:
# - exe-File als avi getarnt
# - echtes mp4/avi, noch nicht vorhanden
# - ./., bereits vorhanden, aber kleiner
# - ./., bereits vorhanden, aber größer
# - jeweils Tatort, Maria Wern, Autopsie



progname=$(basename $0)
usage="Usage:\t$progname -p path [-t] [-v]\n\t[-n] noSQL [-o] original state\n\t$progname -h"


if [ ! -f "/usr/local/bin/uploadwatch.inc.sh" ]
then
  echo "uploadwatch.inc.sh not found, exiting"
  exit 1
else
  source /usr/local/bin/uploadwatch.inc.sh
fi

if [ ! -f "/root/uploadwatch.passwords" ]
then
  echo "/root/uploadwatch.passwords not found, exiting"
  exit 1
else
  source /usr/local/bin/uploadwatch.inc.sh
fi

while getopts "p:tnovh" options ; do
  case $options in
    p) IncomingPath="$OPTARG" ;;
	n) NOSQL="-n" ;;
	o) Originalstate="-o" ;;
    t) TESTFLAG="-t" ;;
    v) VERBOSE="-v" ;;
    h) echo -e $usage ; exit ;;
  esac
done


if [ ! "$IncomingPath" ]
then
  echo "no path given"
  echo -e $usage
  exit 1
fi


# mandatory programs
for NEEDED in logger ffmpeg gm mediainfo mysql clamscan
do
	command -v $NEEDED >/dev/null 2>&1
	if [[ $? -ne 0 ]]
	then
		echo "$NEEDED not installed"
		logger -p alert -t vod $0 "needed program $NEEDED not found -- exiting"
		exit 2
	fi
done




# VARIABLES
# CamelCasing for better readability
# final folders per filetype
# IncomingPath="$1"
declare -A pCorrect
declare -A FinalFolder

IncomingFolder=$(dirname "$IncomingPath")
IncomingFilename=$(basename "$IncomingPath")
Extension="${IncomingFilename##*.}"
pCorrect[Extension]=$Extension
FinalFolder[mp4]=/media/data/var/www/upload/otr
FinalFolder[avi]=/media/data/MyVideos/TVShows
FinalFilename="$IncomingFilename"
ImageFolder=/media/data/var/www/upload/otrimages

if [[ ! -f "$IncomingPath" ]]
then
	logit alert "$IncomingPath not found"
	exit 3
fi

if [[ $(file --mime-type -b "$IncomingPath") =~ "video/"* ]]
then
	logit warning "###################################################"
	logit info "new videofile $IncomingFilename"
else
	logit crit "WARNING: videofile $IncomingPath is not an mp4, m4v, nor avi file, exiting"
	logit crit "scanning for viruses"
	/usr/bin/clamscan "$IncomingPath" | logger -p crit -t vod && mv "$IncomingPath" "$IncomingPath.notavideo" | logger -p crit -t vod
	exit 4
fi


vSender=$(echo "$IncomingFilename"  | rev | cut -d_ -f4 | rev)
vUhrzeit=$(echo "$IncomingFilename" | rev | cut -d_ -f5 | rev | sed 's/-/:/g')
	if [[ "$vUhrzeit" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]
	then
		pCorrect[Uhrzeit]=true
	else
		pCorrect[Uhrzeit]=false
		logit warn "Uhrzeit $vUhrzeit seems not correct"
	fi
vDatum=$(echo "$IncomingFilename"   | rev | cut -d_ -f6 | rev | sed 's/\./-/g')
vDatum="20$vDatum"
	if [[ "$vDatum" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
	then
		pCorrect[Datum]=true
	else
		pCorrect[Datum]=false
		logit warn "Date $vDatum seems not correct"
	fi

# Maria_Wern_Kripo_Gotland_Stille_Wasser_S04E01_18.05.05_23-40_ard_88_TVOON_DE.mpg.HQ.avi
# Tatort_18.05.11_22-00_ard_90_TVOON_DE.mpg.HD.avi
vEpisodenstring=$(echo "$IncomingFilename" | rev | cut -d_ -f7 | rev)
	if [[ "$vEpisodenstring" =~ ^S[0-9]{2}E[0-9]{2}$ ]]
	then
		vStaffel=$(echo "$vEpisodenstring" | cut -c 2-3)
		vEpisode=$(echo "$vEpisodenstring" | cut -c 5-6)
		if [[ "$vStaffel" =~ [0-9]{2} ]] || [[ "$vEpisode" =~ [0-9]{2} ]]
		then
			pCorrect[Episode]=true
		else
			pCorrect[Episode]=false
			logit warn "Staffel $vStaffel or Episode $vEpisode seems not correct"
		fi
	else
		pCorrect[Episode]=false
		logit warn "Episodenstring $vEpisodenstring seems not correct"
	fi

vIncomingBytes=$(stat -c%s "$IncomingPath")
vLength=$(/usr/bin/mediainfo "$IncomingPath" | grep 'Duration' | head -n 1 | cut -d':' -f 2 | sed -e 's/^[ \t]*//')
      VPARTONE=$(echo $vLength | cut -d' ' -f 1 )
      VMINUTES=$(echo $vLength | cut -d' ' -f 3 )
      MINORH=$(echo $vLength | cut -d' ' -f 2 )
      if [[ "$MINORH" == "h" ]] ;
      then
        VHSUM=$(($VPARTONE * 60))
        vLengthMinutes=$((VHSUM + VMINUTES))
      else
        vLengthMinutes=$VPARTONE
      fi


if [[ "$IncomingFilename" =~ ^Tatort.* ]] ;				then Kategorie=Tatort
elif [[ "$IncomingFilename" =~ ^Autopsie.* ]] ; 		then Kategorie=Autopsie
elif [[ "$IncomingFilename" =~ ^Medical.* ]] ;			then Kategorie=Medical_Detectives
elif [[ "$IncomingFilename" =~ ^Sherlock.* ]] ; 		then Kategorie=Sherlock
elif [[ "$IncomingFilename" =~ ^Frag.* ]] ; 		    then Kategorie=Frag_Den_Lesch
elif [[ "$IncomingFilename" =~ ^Richter.* ]] ;			then Kategorie=Richter_Alexander_Hold
elif [[ "$IncomingFilename" =~ ^James.* ]] ;			then Kategorie=James_Bond
elif [[ "$IncomingFilename" =~ ^Trapped.* ]] ;			then Kategorie=Trapped
elif [[ "$IncomingFilename" =~ ^Die_Bruecke.* ]] ;		then Kategorie=Die_Bruecke
elif [[ "$IncomingFilename" =~ ^The_Wire.* ]] ; 		then Kategorie=The_Wire
elif [[ "$IncomingFilename" =~ ^Birkenbihl.* ]] ;	 	then Kategorie=Birkenbihl
elif [[ "$IncomingFilename" =~ ^Maria.* ]] ;			then Kategorie=Maria_Wern
else Kategorie=Andere
fi


### Kategorie-spezifische Aktionen
## Tatort: Tatortfolge (z. B. 646) und Episodenname (z. B. Tatort_646_s2006e25.avi) generieren
if [[ "$Kategorie" == "Tatort" ]]
then
	query="SELECT f.folge
	FROM folgen f
	JOIN ausstrahlungen a ON a.folgenid = f.id
	JOIN sender s ON s.id = a.senderid
	WHERE a.datum='$vDatum $vUhrzeit:00'
	AND s.otrsender = '$vSender'"
	Tatortfolge=$(QueryDB "tatort" "$query")
	logit info "Result Tatortfolge: $Tatortfolge"
	if [[ "$Tatortfolge" =~ ^[0-9]+$ ]]
	then
		pCorrect[Tatortfolge]=true
	else
		logit warning "Tatortfolge seems not correct."
		pCorrect[Tatortfolge]=false
	fi

	query="SELECT CONCAT('Tatort_${Tatortfolge}_s',tj.jahr,'e',LPAD(tf2d.episodeinyear,2,0),'.$Extension') AS episodenname
	FROM tatort.folge2details tf2d
	JOIN tatort.jahre tj ON tj.id = tf2d.jahrid
	JOIN tatort.folgen tf ON tf.id = tf2d.folgenid
	WHERE tf.folge = '$Tatortfolge'"
	#logit info "Query Episodenname: $query"
	Episodenname=$(QueryDB "tatort" "$query")
	logit info "Result Episodenname: $Episodenname"
	if [[ "$Episodenname" =~ Tatort_[0-9]+_s[1-2][0-9]{3}e[0-9]+ ]]
	then
		pCorrect[Episodenname]=true
	else
		logit warning "Episodenname seems not correct."
		pCorrect[Episodenname]=false
	fi

	FinalFilename="$Episodenname"
fi


## Maria Wern: wenn avi, dann die Kategorie ändern, damit die Funktionen weiter unten
## es in den richtigen Ordner kopieren
if [[ "$Kategorie" == "Maria_Wern" ]] && [[ "$Extension" == "avi" ]]
then
	Kategorie="Maria Wern, Kripo Gotland/Staffel $vStaffel"
	FinalFilename="Maria Wern, Kripo Gotland s${vStaffel}e${vEpisode}.$Extension"
fi


if [[ "$Extension" == "avi" ]]
then
	SQLAction=false
	IMGAction=false
fi


FinalFolder="${FinalFolder[$Extension]}/$Kategorie"
pCorrect[FinalFolder]=$(CheckFolder "$FinalFolder")
pCorrect[FileDoesNotYetExist]=$(CheckFile "$FinalFolder/$FinalFilename")

## wenn File schon existiert
if [[ "${pCorrect[FileDoesNotYetExist]}" == "false" ]]
then
	logit warning $FinalFolder/$FinalFilename already exists
	pCorrect[NewFileIsBigger]=$(CheckFileSize "$IncomingPath" "$FinalFolder/$FinalFilename")
	# Annahme: wenn File schon existiert, dann existiert auch schon ein Previewbild
	IMGAction=false

	# wenn IncomingFile größer ist
	if [[ "${pCorrect[NewFileIsBigger]}" == "true" ]]
	then
		logit warning "new file is bigger than existing $FinalFolder/$FinalFilename"
		# existierendes File mit IncomingFile überschreiben
		logit warning "Overwriting $FinalFolder/$FinalFilename with $IncomingPath"
		$(TestCommand "mv -f $IncomingPath $FinalFolder/$FinalFilename")
		# wenn fehlerfrei überschrieben
		if [[ $? -eq 0 ]]
		then
			pCorrect[FileOverwrite]=true
		else
			pCorrect[FileOverwrite]=false
		fi
	# wenn IncomingFile kleiner ist
	else
		logit warning "new file is smaller than existing $FinalFolder/$FinalFilename"
		# IncomingFile löschen
		logit warning "removing $IncomingPath"
		$(TestCommand "rm $IncomingPath")
		if [[ $? -eq 0 ]]
		then
			pCorrect[FileDelete]=true
		else
			pCorrect[FileDelete]=false
		fi
		SQLAction=false
		IMGAction=false
	fi

# wenn File noch nicht existiert
else
	logit info "$FinalFolder/$FinalFilename doesn't exist yet"
	# existierendes File verschieben
	logit warning "Moving $IncomingPath to \"$FinalFolder/$FinalFilename\""
	$(TestCommand "mv -f $IncomingPath \"$FinalFolder/$FinalFilename\"")
	# wenn erfolgreich verschoben
	if [[ $? -eq 0 ]]
	then
		pCorrect[FileMove]=true
	else
		pCorrect[FileMove]=false
	fi
fi



if [[ ! "$IMGAction" == "false" ]]
then
	TMPPATH="/tmp/$FinalFilename"
	mkdir -p "$TMPPATH"

	logit info "Generating preview images"
	$(TestCommand "/usr/bin/ffmpeg -ss 00:05:50 -i $FinalFolder/$FinalFilename -vf \"select='eq(pict_type,PICT_TYPE_I)'\" -s 160x120 -vf fps=1/30 -vframes 4 -f image2 $TMPPATH/%02d.jpg")
	$(TestCommand "/usr/bin/gm montage -tile 2x2 -geometry +0+0 $TMPPATH/* $ImageFolder/$FinalFilename.jpg")
	$(TestCommand "rm -rf $TMPPATH")
fi


if [[ ! "$SQLAction" == "false" ]]
then

	#nur Tatort
	if [[ "$Kategorie" == "Tatort" ]]
	then
		query="SELECT f.id
		FROM folgen f
		JOIN ausstrahlungen a ON f.id = a.folgenid
		JOIN sender s ON a.senderid = s.id
		WHERE a.datum='$vDatum $vUhrzeit:00'
		AND s.otrsender='$vSender';"
		logit debug "$query"
		TatortID=$(QueryDB tatort "$query")
		logit debug "TatortID: $TatortID"
		if [[ "$TatortID" =~ ^[0-9]+$ ]]
		then
			pCorrect[TatortID]=true
		else
			logit warning "TatortID seems not correct."
			pCorrect[TatortID]=false
		fi
	fi


	#für alle Sendungen
	#query="SELECT AddSendung('$Kategorie','$vSender','$vDatum $vUhrzeit:00','$FinalFilename',
	#$vIncomingBytes,'$vLength',$vLengthMinutes,'$FinalFilename.jpg');"
	query="START TRANSACTION; SELECT AddSendung('$Kategorie','$vSender','$vDatum $vUhrzeit:00','$FinalFilename',
	$vIncomingBytes,'$vLength',$vLengthMinutes,'$FinalFilename.jpg');"
	if [[ "$TESTFLAG" == "-t" ]] || [[ "$NOSQL" == "-n" ]]
	then
		query="$query ROLLBACK;"
	else
		query="$query COMMIT;"
	fi
	logit debug "$query"
	SendungID=$(QueryDB vod "$query")
	logit debug "SendungID: $SendungID"
	if [[ "$SendungID" =~ ^[0-9]+$ ]]
	then
		pCorrect[SendungID]=true
	else
		logit warning "SendungID seems not correct."
		pCorrect[SendungID]=false
	fi

	#nur Tatort
	if [[ "$Kategorie" == "Tatort" ]]
	then
		query="START TRANSACTION; INSERT INTO sendung2tatort (sendungid, tatortid, fromwhere) VALUES ($SendungID, $TatortID, 'linkquery');"
		if [[ "$TESTFLAG" == "-t" ]] || [[ "$NOSQL" == "-n" ]]
		then
			query="$query ROLLBACK;"
		else
			query="$query COMMIT;"
		fi
		logit debug "$query"
		InsertS2T=$(QueryDB vod "$query")
		logit debug "InsertS2T: $InsertS2T"
	fi
fi

if [[ "$Originalstate" == "-o" ]] && [[ "$NOSQL" == "-n" ]]
then
	logit info "re-moving $FinalFolder/$FinalFilename to $IncomingPath"
	$(mv -f "$FinalFolder/$FinalFilename" "$IncomingPath")
fi


# for compatibility with journal-triggerd
reportsize=$((vIncomingBytes / 1024 / 1024))
leftondevice=$(df -h "$FinalFolder/$FinalFilename" | grep -oE '[0-9]+%')
logit info "videofile finished: $FinalFilename, ${reportsize}MB, ${leftondevice} left on device"



NOCOLOR="\033[0m" # No Color
BOLD="\033[1m"
printf "${BOLD}%-25s %-8s %-8s${NOCOLOR}\n" "Check" "Current" "Planned"
for p in Uhrzeit Datum Episode FinalFolder FileDoesNotYetExist Tatortfolge Episodenname Extension FileOverwrite FileMove FileDelete TatortID SendungID
do
	if [[ "${pCorrect[$p]}" != "true" ]]
	then
		COLOR="\033[0;31m"
	else
		COLOR="\033[0;32m"
	fi
	printf "%-25s ${COLOR}%-8s %-8s${NOCOLOR}\n" "$p" "${pCorrect[$p]}" "true"
done
