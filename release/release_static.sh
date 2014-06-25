#!/bin/bash
#
# description: 该文件是基于 Git 为版本管理系统的前端自动化发布脚本，也实用与如 PHP、Python 等脚本语言系统。
#              该脚本主要是为了实现 javascript、css 文件的在发布时自动压缩。
#              该脚本是基于 YUI Compressor (http://yui.github.io/yuicompressor/) 来实现 javascript、css 文件的压缩。
#			   所以，运行该脚本，需要 Java 环境支持。
#              由于，在 javascript 代码书写不规范的情况下，容易导致压缩后的 javascript 不可用；所以，在生产环境发布之前，一定要经过严格的测试.
#
#              执行流程：(1)如果是第一次发布时，会从 Git 仓库 clone 一份代码到 PROJECT_DIR；或非第一次发布时，会切换到 PROJECT_DIR 执行 git pull 命令；
#                        (2)将当次更新的文件，记录到 UPDATE_LIST_FILE 文件中；
#                        (3)将 javascript 和 css 文件，压缩输出到 WEB_ROOT，非 javascript 和 css 文件或在压缩文件时出错，则 copy 到 WEB_ROOT；
#                        (4)从 WEB_ROOT 下删除已经从 Git 仓库中删除了的文件和目录；
#                        (5)发布完成。
#
#              PROJECT_DIR：项目源目录，WEB_ROOT：网站根目录。之所以，不直接在 WEB_ROOT 下压缩，是为了，避免压缩后的文件与 Git 仓库中更新下来的文件产生冲突。
#
#              当您在使用此脚本之前，需要修改部分变量
#

set -e

PROJECT_NAME="project name"
DOMAIN="mydomain"
HOME_ROOT="/data/projects"
SOURCE_DIR=$HOME_ROOT"/source"
PROJECT_DIR=$SOURCE_DIR"/"$PROJECT_NAME
WEB_ROOT="/data/wwwroot/"$DOMAIN
LOG_DIR=$HOME_ROOT"/logs/"$PROJECT_NAME
RELEASE_LOG=$LOG_DIR"/release.log"
UPDATE_LIST_FILE=$LOG_DIR"/update_list.txt"
ROLLBACK_LIST_FILE=$LOG_DIR"/rollback_list.txt"
YUICOMPRESSOR_JAR=$HOME_ROOT"/lib/yuicompressor.jar"
LAST_BACKUP_FILE=""

CHARSET="UTF-8"
GIT_CHAESET="UTF-8"

GIT_PROTOCOL=${GIT_PROTOCOL-"ssh"}
GIT_HOST=${GIT_HOST-"git host"}
GIT_PORT=${GIT_PORT-git port}
GIT_USER=${GIT_USER-"git user"}
# WEB_ROOT 所属用户组
GROUP="www"
# WEB_ROOT 所属用户
USER="www"

warning() {
    printf "warning: $*\n" 1>&2;
}

error() {
    printf "error: $*\n" 1>&2;
    exit 1
}

update_files_init() {
    local arg=$1
    local path="$PROJECT_DIR/$arg"

    if [ -d "$path" ]
    then
        local files=`ls "$path"`

        for file in $files
        do
            local _path="$path/$file"
            local temp="$file"

            if [ ! "$arg" == "" ]
            then
                temp="$arg/$temp"
            fi

            if [ -d "$_path" ]
            then
                update_files_init "$temp"
            else
                echo "$temp" >> $UPDATE_LIST_FILE
            fi
        done
    elif  [ -f "$path" ]
    then
        echo "$arg" >> $UPDATE_LIST_FILE
    else
        warning "$path is not exists";
    fi

    return 0
}

condense() {
    local type=$1
    local source_file=$2
    local target_file=$3
    local MSG="Compression "

    if [ "$type" == "js" ]
    then
        MSG=$MSG"javascript"
    else
        MSG=$MSG"css"
    fi
    MSG=$MSG" file $source_file to $target_file"

    echo $MSG" success"
    java -jar ${YUICOMPRESSOR_JAR} --type ${type} --charset ${CHARSET} "$source_file" -o "$target_file" || { warning "$MSG failure"; echo "so copy $source_file to $target_file"; cp $source_file $target_file; }

    chown ${USER}:${GROUP} "$target_file"
}

operate() {
	local file=$1

	if [ ! -z "$file" ]
	then
		local source_file="$PROJECT_DIR/$file"
		local target_file="$WEB_ROOT/$file"
		local target_dir=`dirname "$target_file"`

		if [ -f "$source_file" ]
		then
			mkdir -p "$target_dir" || { warning "create target directory $target_dir failure"; }

			if [[ "$source_file" =~ .js$ ]]
			then
				condense "js" "$source_file" "$target_file"
			elif [[ "$source_file" =~ .css$ ]]
			then
				condense "css" "$source_file" "$target_file"
			else
				echo $"Copy file $source_file to $target_file"
				cp "$source_file" "$target_file"
			fi

			chown ${USER}:${GROUP} "$target_file"
		fi
	fi
}

delete_file() {
	local file=$1

	if [ ! -z "$file" ]
	then
		local source_dir=`dirname "$PROJECT_DIR/$file"`
		local target_file="$WEB_ROOT/$file"
		local target_dir=`dirname "$target_file"`
		
		if [ ! -d "$source_dir" ]
		then
			echo "clear directory $target_dir"
			rm -fR "$target_dir"
		else
			echo "Delete file $target_file"
			rm -f "$target_file"
		fi
	fi
}

release() {
    mkdir -p $LOG_DIR || { error "create log directory $LOG_DIR failure"; }

    if [ -f $UPDATE_LIST_FILE ]
    then
        rm $UPDATE_LIST_FILE || { error "Remove $UPDATE_LIST_FILE failure"; }
    fi

    if [ -d $PROJECT_DIR ]
    then
        cd $PROJECT_DIR
        git pull > $RELEASE_LOG || { error "git pull code failure"; }

        local temp=`grep 'Already up-to-date' $RELEASE_LOG`
        if [ "$temp" == "" ]
        then
            echo "List update files";
        else
            warning "Already up-to-date";
            exit 1;
        fi

        cd $PROJECT_DIR
		git diff-tree HEAD -r --name-status > $UPDATE_LIST_FILE

		while read i;
        do
			temp=`echo $i|awk -F 'A' '{gsub("\"", "", $2); gsub(/^ *| *$/, "", $2); print $2;}'`;
            operate "$temp";
        done < $UPDATE_LIST_FILE

		while read i;
        do
			temp=`echo $i|awk -F 'M' '{gsub("\"", "", $2); gsub(/^ *| *$/, "", $2); print $2;}'`;
            operate "$temp";
        done < $UPDATE_LIST_FILE

		while read i;
        do
            temp=`echo $i|awk -F 'D' '{gsub("\"", "", $2); gsub(/^ *| *$/, "", $2); print $2;}'`;
			delete_file "$temp";
        done < $UPDATE_LIST_FILE
    else
        cd $SOURCE_DIR

        local project_git_url=${GIT_PROTOCOL}://${GIT_USER}@${GIT_HOST}:${GIT_PORT}/${PROJECT_NAME}
        git clone ${project_git_url} > $RELEASE_LOG || { error "git clone $PROJECT_NAME form $project_git_url error"; }

        echo "List update files"

        update_files_init "" || { error "update files init failure"; }

		local files=`cat $UPDATE_LIST_FILE`

		for file in $files
		do
			operate "$file"
		done

		chown ${USER}:${GROUP} "$WEB_ROOT"
    fi
}

rollback() {
    local commit=$1

    if [ "$commit" == "" ]
    then
        error "commit could not be empty";
    else
        cd $PROJECT_DIR

        git reset --hard $commit
        git diff-tree HEAD HEAD^ -r --name-status > $ROLLBACK_LIST_FILE

		while read i;
        do
			temp=`echo $i|awk -F 'A' '{gsub("\"", "", $2); gsub(/^ *| *$/, "", $2); print $2;}'`;
            delete_file "$temp";
        done < $ROLLBACK_LIST_FILE

		while read i;
        do
			temp=`echo $i|awk -F 'M' '{gsub("\"", "", $2); gsub(/^ *| *$/, "", $2); print $2;}'`;
            operate "$temp";
        done < $UPDATE_LIST_FILE

		while read i;
        do
			temp=`echo $i|awk -F 'D' '{gsub("\"", "", $2); gsub(/^ *| *$/, "", $2); print $2;}'`;
			operate "$temp";
        done < $UPDATE_LIST_FILE
    fi
}

# 设置编码和文件名允许中文等字符  
git config --global core.quotepath false         # 设置文件名允许中文等字符
git config --global i18n.logoutputencoding ${GIT_CHAESET} # 设置git log输出时编码
export LESSCHARSET=${GIT_CHAESET}

case "$1" in
    release)
		release
        ;;
    rollback)
        case "$2" in
            --help|-h|?)
                echo "Usage: $0 <commit>"
                echo "       commit: use command 'git reset --hard [<commit>]' rollback code"
                ;;
            *)
                rollback $2
                ;;
        esac
        ;;
    *)
        echo "Usage: $0 {release|rollback}"
        ;;
esac

exit 0