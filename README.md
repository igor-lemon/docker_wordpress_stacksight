# Docker wordpress site with stacksight plugin
Up Wordpress instance with Stacksight plugin

System requirements
--------------------

* Docker
* Docker compose

Install
--------------------

1) Clone source
`git clone https://github.com/igor-lemon/docker_wordpress_stacksight.git`

2) Run `composer up -d` command. 

3) Waiting to set environment (you can see status in php-fpm container)

4) Open site in browser _(Default: http://localhost:8081/)_

Options
--------------------
You can add/remove some options to entrypoint script

##### `--force` - force reinstall Wordpress
##### `--with-stacksight` - Install Stacksight plugin
##### `--stacksight-from-git` - Install Stacksight plugin from GitHub. _(Default: Wordpress.org repository)_