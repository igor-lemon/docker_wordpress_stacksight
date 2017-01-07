#!/bin/bash
# set -euo pipefail

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"
    if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
        echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
        exit 1
    fi
    local val="$def"
    if [ "${!var:-}" ]; then
        val="${!var}"
    elif [ "${!fileVar:-}" ]; then
        val="$(< "${!fileVar}")"
    fi
    export "$var"="$val"
    unset "$fileVar"
}

file_env 'APP_PATH' "${APP_PATH:-/var/www/html}"
cd $APP_PATH

APP_FORCE="false"
WITH_STACKSIGHT="false"
STACKSIGHT_FROM_GIT="false"

for i in "$@"
do
case $i in
    -f|--force) APP_FORCE="true"
    shift # past argument
    ;;
    -ws|--with-stacksight) WITH_STACKSIGHT="true"
    shift # past argument
    ;;
    -wsg|--stacksight-from-git) STACKSIGHT_FROM_GIT="true"
    shift # past argument
    ;;
    --default)
    ;;
    *)
            # unknown option
    ;;
esac
done

shift $((OPTIND-1))
[ "$1" = "--" ] && shift

if ! [ -e index.php -a -e wp-includes/version.php ] || [ "$APP_FORCE" == "true" ]; then
    echo >&2 "WordPress install - let's start now..."

    rm -rf *

    curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x wp-cli.phar
    mv wp-cli.phar /usr/local/bin/wp

    file_env 'APP_HOST' "${APP_HOST:-localhost}"
    file_env 'APP_TABLE_PREFIX' "${APP_TABLE_PREFIX:-}"
    file_env 'APP_ADMIN_EMAIL' "${APP_ADMIN_EMAIL:-admin@localhost.local}"
    file_env 'APP_ADMIN_PASSWD' "${APP_ADMIN_PASSWD:-admin}"
    file_env 'APP_ADMIN_LOGIN' "${APP_ADMIN_LOGIN:-admin}"
    file_env 'APP_TITLE' "${APP_TITLE:-DockerSite}"

    file_env 'APP_VERSION' "${APP_VERSION:-latest}"


    file_env 'APP_DB_HOST' "${MYSQL_HOST:-db}"
    file_env 'APP_DB_USER' "${MYSQL_USER:-root}"
    if [ "$APP_DB_USER" = 'root' ]; then
        file_env 'APP_DB_PASSWORD' "${MYSQL_ROOT_PASSWORD:-wordpress}"
    else
        file_env 'APP_DB_PASSWORD' "${MYSQL_PASSWORD:-wordpress}"
    fi
    file_env 'APP_DB_NAME' "${MYSQL_DATABASE:-wordpress}"
    if [ -z "$APP_DB_PASSWORD" ]; then
        echo >&2 'error: missing required APP_DB_PASSWORD environment variable'
        echo >&2 '  Did you forget to -e APP_DB_PASSWORD=... ?'
        echo >&2
        echo >&2 '  (Also of interest might be APP_DB_USER and APP_DB_NAME.)'
        exit 1
    fi

    TERM=dumb php -- "$APP_DB_HOST" "$APP_DB_USER" "$APP_DB_PASSWORD" "$APP_DB_NAME" <<'EOPHP'
        <?php
        $stderr = fopen('php://stderr', 'w');
        list($host, $socket) = explode(':', $argv[1], 2);
        $port = 0;
        if (is_numeric($socket)) {
            $port = (int) $socket;
            $socket = null;
        }
        $maxTries = 3;
        do {
            $mysql = new mysqli($host, $argv[2], $argv[3], '', $port, $socket);
            if ($mysql->connect_error) {
                fwrite($stderr, "\n" . 'MySQL Connection Error: (' . $mysql->connect_errno . ') ' . $mysql->connect_error . "\n");
                --$maxTries;
                if ($maxTries <= 0) {
                    exit(1);
                }
                sleep(3);
            }
        } while ($mysql->connect_error);

        $mysql->query('DROP DATABASE IF EXISTS `' . $mysql->real_escape_string($argv[4]) . '`');

        if (!$mysql->query('CREATE DATABASE IF NOT EXISTS `' . $mysql->real_escape_string($argv[4]) . '`')) {
            fwrite($stderr, "\n" . 'MySQL "CREATE DATABASE" Error: ' . $mysql->error . "\n");
            $mysql->close();
            exit(1);
        }
        $mysql->close();
EOPHP

    wp core download --path="$APP_PATH" --version="$APP_VERSION" --allow-root
    wp core config --path="$APP_PATH" --dbname="$APP_DB_NAME" --dbuser="$APP_DB_USER" --dbpass="$APP_DB_PASSWORD" --dbhost="$APP_DB_HOST" --dbprefix="$APP_TABLE_PREFIX" --allow-root --skip-check
    wp core install --path="$APP_PATH" --url="$APP_HOST" --title="$APP_TITLE" --admin_user="$APP_ADMIN_LOGIN" --admin_password="$APP_ADMIN_PASSWD" --admin_email="$APP_ADMIN_EMAIL" --allow-root

    if [ "$WITH_STACKSIGHT" == "true" ]; then
        echo "Install Stacksight plugin"
        if [ "$STACKSIGHT_FROM_GIT" == "true" ]; then
            echo "Install from GIT"
            cd ./wp-content/plugins/
            git clone https://github.com/stacksight/wordpress.git --recursive
            mkdir ./stacksight
            mv ./wordpress/* ./stacksight/
            mv ./wordpress/.* ./stacksight/
            rm -rf ./wordpress
            cd ./stacksight/
            git checkout develop
        else
            echo "Install from Wordpress.org"
            wp plugin install stacksight --activate-network --activate --force --allow-root
        fi
#        $APP_PATH/wp-config.php
        cat << EOF >> $APP_PATH/tmp.txt
// StackSight start config
\$ss_inc = dirname(__FILE__) . '/wp-content/plugins/stacksight/stacksight-php-sdk/bootstrap-wp.php';
if(is_file(\$ss_inc)) {
    define('STACKSIGHT_DEBUG', true);
    require_once(\$ss_inc);
}
// StackSight end config
EOF
sed -i -e "/Sets up WordPress vars and included files/r $APP_PATH/tmp.txt" $APP_PATH/wp-config.php
rm $APP_PATH/tmp.txt
    fi

fi
exec php-fpm