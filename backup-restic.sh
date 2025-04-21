#!/usr/bin/env bash

# Вызывать так:
# ./backup-restic.sh <config-name> [force]
# где config-name - название папки внутри папки confs-restic
# force - необязательный параметр. Может быть каким угодно. Его наличие приводит к тому, что бэкап будет сделан даже в том случае, если файлы не изменились со времени предыдущего бэкапа.
#
# Конфигурация:
# confs-restic
# |- [config-name-1]
# |  |- backup.config
# |  |- paths
# |  |- excludes
# |  |- actions.sh
# |- [config-name-2]

# backup.config должен содержать следующие переменные:
# export RESTIC_REPOSITORY=sftp://tim@[127.0.0.1]:22//home/tim/restic-repo
# Для более старых версий restic надо указывать порт в ~/.ssh/config и писать так:
# export RESTIC_REPOSITORY=sftp://tim@127.0.0.1//home/tim/restic-repo
# export RESTIC_PASSWORD=123456
# export RESTIC_BIN=/opt/restic/restic
# export TELEGRAM_GROUP_ID="<telegram id>" (необязательно)
# export TELEGRAM_BOT_TOKEN="<telegram bot token>" (необязательно)
# Файл paths содержит пути к файлам/папкам, которые нужно бэкапить, по одному на строку
# Файл excludes не обязателен. Содержит пути к файлам/папкам, которые нужно исключить из бэкапа, по одному на строку
# Файл actions.sh, если он присутствует и исполняемый, будет выполнен перед началом резервного копирования. Можно использовать для выгрузки в файлы каких-либо runtime конфигураций.

# Также необходимо настроить вход по ключу ssh. Для этого положить в папку пользователя, от имени которого запускается бэкап (напр. root) ключевой файл id_rsa_tim и вот такой конфиг:
# /root/.ssh/config:
# Host 127.0.0.1
#   IdentityFile /root/.ssh/id_rsa_tim
#   Port 22002

function sendMail {
    echo -e "${2}" | mail -a "From: ltv@gto.by" -s "error while backup ${configName}: ${1}" ltv@gto.by
}

function appendLog {
    echo "=============================== $(date) ===============================" >> /var/log/backup-restic.log
    echo -e "${1}\n${2}" >> /var/log/backup-restic.log
}

function rawurlencode {
  local string="${1}"
  local strlen=${#string}
  local encoded=""
  local pos c o

  for (( pos=0 ; pos<strlen ; pos++ )); do
     c=${string:$pos:1}
     case "$c" in
        [-_.~a-zA-Z0-9] ) o="${c}" ;;
        * )               printf -v o '%%%02x' "'$c"
     esac
     encoded+="${o}"
  done
  echo "${encoded}"    # You can either set a return variable (FASTER)
  REPLY="${encoded}"   #+or echo the result (EASIER)... or both... :p
}

function sendTelegram {
    tempdir=$(mktemp -d)
    tempfile="$tempdir/report.txt"
    echo -e "$2" > "$tempfile"
    mailSubject=$(rawurlencode "$1")
    curl -F document=@"$tempfile" https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument?chat_id=${TELEGRAM_GROUP_ID}\&caption=${mailSubject}
    rm -rf "$tempdir"
}

scriptAbsolutePath=`realpath $0`
scriptDir=`dirname "$scriptAbsolutePath"`
configName=${1}
if [ -z ${configName} ]
then
    echo Необходимо ввести название конфигурации
    exit -1
fi
configDir="${scriptDir}/confs-restic/${configName}"
source "${configDir}/backup.config"

if [ -x "${configDir}/actions.sh" ]
then
    "${configDir}/actions.sh"
fi

timestampdir="${scriptDir}/_ts_"

if [ ! -e "${configDir}/paths" ]
then
    echo Нет файла "${configDir}/paths"
    exit -1
fi

if [ \( -z "${RESTIC_REPOSITORY}" \) -o \( -z "${RESTIC_PASSWORD}" \) ]
then
    echo "Не задано RESTIC_REPOSITORY или RESTIC_PASSWORD"
    exit -1
fi

timestampfile="${timestampdir}/${configName}-e2be8842-5f9f-11ed-9b6a-0242ac120002"
if [ ! -e ${timestampfile} ]
then
    mkdir -p "${timestampdir}"
    touch -t 197001010000 ${timestampfile}
fi

readarray -t dirs < ${configDir}/paths
if [ ${#dirs[*]} -eq 0 ]
then
    echo "Нет ни одного пути для бэкапа"
    exit -1
fi

if [ -e ${configDir}/excludes ]
then
    readarray -t excludes < ${configDir}/excludes
else
    excludes=()
fi
excludes+=($timestampdir)


findargs=("${dirs[@]}")
findargs+=(-newer ${timestampfile})
if [ ${#excludes[*]} -ne 0 ]
then
    findargs+=(-not \()
    first=1
    for d in ${excludes[*]}
    do
        tarArgs+=(--exclude $d)

        if [ ${first} -ne 1 ]
        then
            findargs+=(-o)
        fi
        findargs+=(-path $d -prune)
        first=0
    done
    findargs+=(\))
fi

count=`find "${findargs[@]}"|head -1|wc -l`

if [ \( _${2}_ = __ \) -a \( ${count} -eq 0 \) ]
then
    echo не буду бэкапить
    exit
fi

echo надо бэкапить
if [ -e ${configDir}/excludes ]
then
    MESSAGE=$(${RESTIC_BIN:-restic} backup --files-from-verbatim ${configDir}/paths --exclude-file ${configDir}/excludes 2>&1)
    RESULT=$?
else
    MESSAGE=$(${RESTIC_BIN:-restic} backup --files-from-verbatim ${configDir}/paths 2>&1)
    RESULT=$?
fi

if [ $RESULT -ne 0 ]
then
    SUBJECT="$(hostname) restic failed with code $RESULT"
    echo -e "$SUBJECT\n$MESSAGE"
    appendLog "$SUBJECT" "$MESSAGE"
    if [ -n ${TELEGRAM_GROUP_ID} ]
    then
        sendTelegram "$SUBJECT" "$MESSAGE"
    fi
    sendMail "$SUBJECT" "$MESSAGE"
    exit
else
    sendTelegram "$(hostname) restic backup OK" "$MESSAGE"
fi

touch ${timestampfile}
