#!/usr/bin/env python3

import sys

from jinja2 import Template


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: mkinstaller.py <repo_type> <tarantool_version>")
        sys.exit(1)
    else:
        repo_type = sys.argv[1]
        ver = sys.argv[2]

    if ver >= "1" and ver < "3":
        with open("installer.tpl.sh", 'r') as file:
            template = Template(file.read())
    elif ver >= "3":
        with open("installer-static.tpl.sh", 'r') as file:
            template = Template(file.read())
    else:
        print('Wrong version')
        exit(1)

    installer = template.render({
        'tarantool_version': ver,
        'rtype': repo_type,
    })

    with open("installer.sh", 'w+') as file:
        file.write(installer)
