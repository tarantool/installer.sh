#!/usr/bin/env python3

import sys

from jinja2 import Template


if __name__ == "__main__":
    repo_type = sys.argv[1]
    ver = sys.argv[2]

    with open("installer.tpl.sh", 'r') as file:
        template = Template(file.read())

    installer = template.render({
        'tarantool_version': ver,
        'rtype': repo_type,
    })

    with open("installer.sh", 'w+') as file:
        file.write(installer)
