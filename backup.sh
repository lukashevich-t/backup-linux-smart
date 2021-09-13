#!/usr/bin/env bash
# Скрипт занимается бэкапом указанной папки и отправкой бэкапа на Яндекс.диск
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

#Версия скрипта:
ver=2
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

if [ \( -z "${dirs}" \) -o \( -z "${cred}" \) -o \( -z "${gpgKeyname}" \) -o \( -z "${backupRoot}" \) ]
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
tarArgs=(-cJf ${archivePath})
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

tar "${tarArgs[@]}"
gpg -e -r timoha --output - ${archivePath} | split -a 5 -b 5242880 - ${targetPath}/back_

curl -X MKCOL --user $cred https://webdav.yandex.ru/backups
curl -X MKCOL --user $cred https://webdav.yandex.ru/backups/${targetPath1}
curl -X MKCOL --user $cred https://webdav.yandex.ru/backups/${targetPath1}/${targetPath2}
curl -X MKCOL --user $cred https://webdav.yandex.ru/backups/${targetPath1}/${targetPath2}/${targetPath3}
for f in ${targetPath}/back_*; do
    curl -T ${f} --user $cred https://webdav.yandex.ru/backups/${targetPath1}/${targetPath2}/${targetPath3}/
done
rm -rf ${targetPath}/back_*

touch ${timestampfile}

#ls -tpd /var/backups/bitbucket/archive/* | grep -v '/$' | tail -n +7 | xargs rm
