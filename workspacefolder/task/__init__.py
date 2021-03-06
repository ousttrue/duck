import platform
import pathlib
from typing import List, Optional
import toml
import logging
from . import entry
logger = logging.getLogger(__name__)


def get_tasks(toml):
    if 'tasks' not in toml:
        return []
    return toml['tasks']


class Duck:
    def __init__(self, path: pathlib.Path, verbose: bool, system: str) -> None:
        self.path = path
        self.toml = toml.load(path)
        self.verbose = verbose
        if self.verbose:
            logger.debug(self.toml)
        self.system = system

        self.tasks = {
            t['name']: entry.Entry(self.verbose, system, t)
            for t in get_tasks(self.toml)
        }
        for _, task in self.tasks.items():
            depends = [self.tasks[x] for x in task.depends]
            task.depends = depends

        self.root = []
        for _, task in self.tasks.items():
            if not any((task in _v.depends) for _k, _v in self.tasks.items()):
                self.root.append(task)

        self.defaults = self.toml.get('defaults')

    def start(self, starts: List[str]) -> None:
        if self.verbose:
            print(starts)

        for key in starts:
            self.tasks[key].do_entry(self.path.parent)


def find_toml(current: pathlib.Path, verbose: bool) -> Optional[pathlib.Path]:

    while True:
        if verbose:
            print(current)
        duck_file = current / 'Workspace.toml'
        if duck_file.exists():
            return duck_file

        if current == current.parent:
            print('Workspace.toml not found')
            return None
        current = current.parent


def execute(parsed) -> bool:
    # find Workspace.toml
    here = pathlib.Path('.').resolve()
    duck_file = find_toml(here, parsed.debug)
    if not duck_file:
        print('[Workspace.toml]')
        print('not found')
        print()
        return False

    duck = Duck(duck_file, parsed.debug, platform.system().lower())

    if parsed.task:
        duck.start(parsed.task)
    else:
        if duck.defaults:
            duck.start(duck.defaults)
        else:
            print('[Workspace.toml]')
            print(duck_file.resolve())
            print()
            if duck.tasks:
                print('[task entries]')

                def traverse(task, level=0):
                    print(f'{"    " * level}{task}')
                    if task.depends:
                        for depend in task.depends:
                            traverse(depend, level + 1)

                for task in duck.root:
                    traverse(task)
    return True
