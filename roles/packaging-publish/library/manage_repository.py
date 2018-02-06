import glob
import os
import subprocess

from ansible.module_utils.basic import AnsibleModule
from datetime import datetime
from jinja2 import Template

ANSIBLE_METADATA = {
    'metadata_version': '1.1',
    'status': ['preview'],
    'supported_by': 'community'
}

result = dict(
    changed=True,
    original_message='',
    message='',
)

MASTER_RELEASE = '5.0'

REPREPRO_DISTRIBUTIONS = """
Codename: {{ linux_release }}
Components: main
Architectures: amd64

"""

class RepositoryType(object):
    DEB = 'deb'
    RPM = 'rpm'


class RepositoryManager(object):
    def check_location(self):
        if not os.path.exists(self._repo_location):
            msg = "Repository directory '%s' is missing. Exiting." % (self._repo_location)
            raise RuntimeError(msg)

    def create(self):
        pass


class DebRepositoryManager(RepositoryManager):
    def __init__(self, linux_release, repo_name):
        super(DebRepositoryManager, self).__init__()
        self._type = RepositoryType.DEB
        self._linux_release = linux_release
        self._repo_location = '/var/www/ci-repos/deb/%s/' % (repo_name,)
        self._repo_name = repo_name

    def check_location(self):
        super(DebRepositoryManager, self).check_location()

        # check if there are any *.deb files
        if not glob.glob(os.path.join(self._repo_location, '*.deb')):
            raise RuntimeError("No deb packages has been found in %s. Exiting" % (self._repo_location,))

    def create(self):
        super(DebRepositoryManager, self).create()

        self.check_location()

        # create reprepro configuration for the repository
        os.mkdir(os.path.join(self._repo_location, "conf"))
        Template(REPREPRO_DISTRIBUTIONS) \
            .stream(linux_release=self._linux_release) \
            .dump(os.path.join(self._repo_location, "conf", "distributions"))

        packages = glob.glob(os.path.join(self._repo_location, "*.deb"))
        cmd = ["reprepro", "-b", self._repo_location,
               "includedeb", self._linux_release] + packages

        subprocess.check_call(cmd)

        # files have been copied to pool/ by reprepro so clean-up what's left
        for pkg in packages:
            os.remove(pkg)

    def get_repo_path(self):
        return "/ci-repos/%s/%s/" % (self._type, self._repo_name)


def main():
    module = AnsibleModule(
        argument_spec=dict(
            type=dict(type='str', required=True),
            state=dict(type='str', required=True),
            linux_release=dict(type='str', required=True),
            repository=dict(type='str', required=True),
        )
    )

    type_ = module.params['type']
    state = module.params['state']
    linux_release = module.params['linux_release']
    repository = module.params['repository']

    if type_ == 'deb':
        manager = DebRepositoryManager(linux_release, repository)
    else:
        module.fail_json(msg="Unknown repository type: %s" % (type_,),
                         **result)

    if state == "present":
        manager.create()
    else:
        manager.delete()

    module.exit_json(ansible_facts={'repository_path': manager.get_repo_path() }, **result)

if __name__ == "__main__":
    main()

