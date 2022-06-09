#!/usr/bin/env python
# -*- coding: utf-8 -*-

"""The setup script."""

from setuptools import find_packages, setup


with open('README.md') as readme_file:
    readme = readme_file.read()


requirements = []
setup_requirements = []
test_requirements = []

setup(
    author="nevermined-io",
    author_email='root@nevermined.io',
    classifiers=[
        'Development Status :: 5 - Production/Stable',
        'Intended Audience :: Developers',
        'License :: OSI Approved :: Apache Software License',
        'Natural Language :: English',
        'Programming Language :: Python :: 3.7',
        'Programming Language :: Python :: 3.8',
    ],
    description="Smart Contracts for Nevermined Data platform",
    install_requires=requirements,
    packages=find_packages("python"),
    package_dir={"": "python"},
    package_data={"": ["artifacts/*"]},
    license="Apache Software License 2.0",
    long_description=readme,
    long_description_content_type='text/markdown',
    keywords='nevermined-contracts',
    name='nevermined-contracts',
    setup_requires=setup_requirements,
    test_suite='tests',
    tests_require=test_requirements,
    url='https://github.com/nevermined-io/contracts',
    version='2.0.0-rc5',
    zip_safe=False,
)
