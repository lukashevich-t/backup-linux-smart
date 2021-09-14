#!/usr/bin/env bash
# Скрипт занимается бэкапом указанной папки и отправкой бэкапа на другой хост по протоколу ssh.
# При этом проверяется, есть ли измененные файлы со времени последнего бэкапа
# Бэкап происходит, если есть изменения ИЛИ в скрипт передан второй параметр с ЛЮБЫМ содержимым
# Все настройки лежат в файле в папке confs, имя которого передается первым параметром в командной строке.
# ФАЙЛ С НАСТРОЙКАМИ ДОЛЖЕН ИМЕТЬ ПЕРЕВОДЫ СТРОК LF!!!!!:
#   cred - учетка для yandex.disk в виде имя:пароль (через двоеточие)
#   gpgKeyname - название ключа для шифрования gpg (должен присутствовать в keyring пользователя, от имени которого запускается скрипт)
#   dirs - массив файлов и папок для резервного копирования. ПРимер:
#	dirs=(/etc /root/scripts \
#	/var/atlassian/application-data/bitbucket/shared/bitbucket.properties \
#	/var/atlassian/application-data/bitbucket/shared/config \
#	/var/atlassian/application-data/bitbucket/shared/plugins \
#	/var/lib/dpkg /var/lib/apt/extended_states /usr/bin/loginlog)
#    excludes - массив файлов, исключенных из бэкапа
#    backupRoot - путь к папке для бэкапа
#    includeDpkg - включать или нет вывод команд dpkg --list и dpkg --get-selections. Любая непустая строка включает опцию
#    sshHost - имя ssh-хоста, куда отправлять backup
#    sshPort - порт ssh-хоста, куда отправлять backup. По умолчанию 22

#Версия скрипта:
ver=3
scriptAbsolutePath=`realpath $0`
ddd=`dirname "$scriptAbsolutePath"`
prefix=${1}
if [ -z ${prefix} ]
then
    echo Необходимо ввести название конфигурации
    exit -1
fi
source "$ddd/confs/${1}"

timestampdir="${ddd}/_ts_"
excludes+=($timestampdir)

if [ \( -z "${dirs}" \) -o \( -z "${sshHost}" \) -o \( -z "${backupRoot}" \) ]
then 
    echo "Заданы не все параметры"
    exit -1
fi
targetPath1=`hostname`
targetPath2=`date +%Y-%m-%d`
targetPath3=`hostname`_${prefix}_`date +%Y%m%d-%H%M%S`_v${ver}
targetPath=$backupRoot/${targetPath1}/${targetPath2}/${targetPath3}
archivePath=${targetPath}/1.tar.xz
#archivePath=${targetpath}/`hostname`_${prefix}_`date +%Y%m%d-%H%M%S`_v${ver}.tar.xz
echo ${targetPath}
timestampfile="${timestampdir}/${prefix}-2146d24e-95d4-4f43-a87d-86d86e1c67ee"
if [ ! -e ${timestampfile} ]
then
    mkdir -p "${timestampdir}"
    touch -t 197001010000 ${timestampfile}
fi

findargs=("${dirs[@]}")
tarArgs=(-cJf -)
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
tarArgs+=("${dirs[@]}")

count=`find "${findargs[@]}"|head -1|wc -l`

if [ \( _${2}_ = __ \) -a \( ${count} -eq 0 \) ]
then
    echo не буду бэкапить
    exit
fi

echo надо бэкапить
mkdir -p ${targetPath}

if [ ! \( -z "${includeDpkg}" \) ]
then
    echo добавляем dpkg
    dpkg --list >${targetPath}/dpkg.list.txt
    dpkg --get-selections > ${targetPath}/dpkg-selections.txt
    tarArgs+=(${targetPath}/dpkg.list.txt ${targetPath}/dpkg-selections.txt)
fi

ssh -p ${sshPort:-22} -i "/home/backuper/.ssh/id_rsa" backuper@${sshHost} "mkdir -p /var/backups/${targetPath1}/${targetPath2}/${targetPath3}"
tar "${tarArgs[@]}" | ssh -i "/home/backuper/.ssh/id_rsa" -p ${sshPort:-22} backuper@${sshHost} "cat - > /var/backups/${targetPath1}/${targetPath2}/${targetPath3}/${1}.tar.xz"

touch ${timestampfile}
