# Tarantool installer.sh

We have two installer.sh scripts.

`tarantool.tpl.sh`
It is generated every time the script is downloaded from
https://tarantool.io/release/2.6/installer.sh using the 
values form the url. It sets up the repo only.

`static/tarantool.sh`
This script has everything on board for every supported OS.
https://tarantool.io/installer.sh
It installs Tarantool after the repository is set up.